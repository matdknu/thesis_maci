"""
Analisis profundo de polarizacion para tesis Reddit Chile 2025.

Sin embeddings pesados ni BERT.
Usa:
- scipy.stats para inferencia no parametrica
- sklearn para TF-IDF, clasificacion, regresion y SVD
- seaborn/matplotlib para visualizacion

Outputs:
- PNG y CSV en outputs_ml/
- tabla resumen de estadisticos reportables para tesis
"""

from __future__ import annotations

import math
import warnings
from itertools import combinations
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from scipy import stats
from sklearn.compose import ColumnTransformer
from sklearn.decomposition import TruncatedSVD
from sklearn.ensemble import (
    GradientBoostingClassifier,
    RandomForestClassifier,
    RandomForestRegressor,
)
from sklearn.feature_extraction.text import CountVectorizer, TfidfVectorizer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    mean_absolute_error,
    mean_squared_error,
    precision_score,
    recall_score,
    r2_score,
)
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

warnings.filterwarnings("ignore")

try:
    from statsmodels.nonparametric.smoothers_lowess import lowess

    LOWESS_OK = True
except Exception:
    LOWESS_OK = False


try:
    BASE_DIR = Path(__file__).parent.parent.parent
except NameError:
    BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_maci")

CSV_PATH = BASE_DIR / "data" / "processed" / "analisis_API.csv"
OUT_DIR = BASE_DIR / "outputs_ml"
OUT_DIR.mkdir(parents=True, exist_ok=True)

FIRST_ROUND_DATE = pd.Timestamp("2025-10-31")
RANDOM_STATE = 42
CANDIDATOS = ["kast", "kaiser", "matthei", "jara"]
HOSTILES = {"ira", "desprecio", "indignacion"}
MODERADAS = {"esperanza", "alegria", "ninguna"}
VALID_SENT = {"NEGATIVO", "NEUTRO", "POSITIVO"}

COLORES_CAND = {
    "kast": "#C0392B",
    "kaiser": "#E67E22",
    "matthei": "#2980B9",
    "jara": "#27AE60",
}
COLORES_POL = {
    "baja": "#73C6B6",
    "media": "#F7DC6F",
    "alta": "#CB4335",
}
COLORES_EMO = {
    "indignacion": "#8E2C2C",
    "ira": "#C0392B",
    "desprecio": "#7B241C",
    "miedo": "#6C5CE7",
    "esperanza": "#27AE60",
    "alegria": "#F1C40F",
    "ironia": "#5D6D7E",
    "ninguna": "#95A5A6",
}

SPANISH_STOPWORDS = {
    "a", "acá", "ahi", "ahora", "al", "algo", "algun", "alguna", "algunas",
    "alguno", "algunos", "alla", "alli", "ambos", "ante", "antes", "aquel",
    "aquella", "aquellas", "aquello", "aquellos", "aqui", "asi", "aun", "aunque",
    "bajo", "bastante", "bien", "cada", "casi", "como", "con", "contra", "cual",
    "cuales", "cualquier", "cuando", "de", "del", "desde", "donde", "dos", "el",
    "ella", "ellas", "ello", "ellos", "en", "entre", "era", "erais", "eramos",
    "eran", "eras", "eres", "es", "esa", "esas", "ese", "eso", "esos", "esta",
    "estaba", "estado", "estais", "estamos", "estan", "estar", "estas", "este",
    "esto", "estos", "fue", "fueron", "fui", "fuimos", "ha", "habia", "han",
    "hasta", "hay", "la", "las", "le", "les", "lo", "los", "mas", "me", "mi",
    "mis", "mucho", "muy", "nada", "ni", "no", "nos", "nosotros", "nuestra",
    "nuestras", "nuestro", "nuestros", "o", "os", "otra", "otras", "otro", "otros",
    "para", "pero", "poco", "por", "porque", "que", "quien", "quienes", "se",
    "sea", "ser", "si", "siempre", "sin", "sobre", "sois", "solo", "son", "soy",
    "su", "sus", "tambien", "te", "teneis", "tenemos", "tener", "tengo", "ti",
    "tiene", "tienen", "todo", "todos", "tu", "tus", "un", "una", "unas", "uno",
    "unos", "usted", "ustedes", "va", "vais", "vamos", "van", "y", "ya",
    "kast", "kaiser", "matthei", "jara", "jose", "antonio", "jeannette", "johannes",
    "evelyn", "q", "xd", "jaja", "jeje", "wn", "weon", "weona", "wna", "wno",
}

sns.set_theme(style="whitegrid", context="talk")
plt.rcParams["axes.spines.top"] = False
plt.rcParams["axes.spines.right"] = False


def print_header(title: str) -> None:
    print(f"\n{'=' * 80}\n{title}\n{'=' * 80}")


def ci95(series: pd.Series) -> float:
    series = pd.to_numeric(series, errors="coerce").dropna()
    if len(series) < 2:
        return 0.0
    return 1.96 * series.std(ddof=1) / math.sqrt(len(series))


def cohen_d(x: pd.Series, y: pd.Series) -> float:
    x = pd.to_numeric(pd.Series(x), errors="coerce").dropna().to_numpy()
    y = pd.to_numeric(pd.Series(y), errors="coerce").dropna().to_numpy()
    if len(x) < 2 or len(y) < 2:
        return np.nan
    vx = x.var(ddof=1)
    vy = y.var(ddof=1)
    pooled = math.sqrt(((len(x) - 1) * vx + (len(y) - 1) * vy) / (len(x) + len(y) - 2))
    if pooled == 0:
        return 0.0
    return (x.mean() - y.mean()) / pooled


def rank_biserial_from_u(u_stat: float, n1: int, n2: int) -> float:
    if n1 == 0 or n2 == 0:
        return np.nan
    return 1 - (2 * u_stat) / (n1 * n2)


def eta_squared_kruskal(h_stat: float, k: int, n: int) -> float:
    if n <= k:
        return np.nan
    return max(0.0, (h_stat - k + 1) / (n - k))


def p_bonferroni(p_values: list[float]) -> list[float]:
    m = max(len(p_values), 1)
    return [min(p * m, 1.0) for p in p_values]


def phase_from_date(fecha: pd.Series) -> pd.Series:
    return np.where(fecha <= FIRST_ROUND_DATE, "posicionamiento", "segunda_vuelta")


def polar_level(x: float) -> str:
    if pd.isna(x):
        return np.nan
    if x < 0.3:
        return "baja"
    if x <= 0.6:
        return "media"
    return "alta"


def emotion_family(x: str) -> str:
    if x in HOSTILES:
        return "hostil"
    if x in MODERADAS:
        return "moderada"
    return "intermedia"


def safe_filename(text: str) -> str:
    return (
        str(text)
        .lower()
        .replace(" ", "_")
        .replace("/", "_")
        .replace("-", "_")
    )


def save_df(df: pd.DataFrame, filename: str) -> None:
    path = OUT_DIR / filename
    df.to_csv(path, index=False)
    print(f"  CSV guardado: {path.name}")


def save_figure(fig: plt.Figure, filename: str, dpi: int = 220) -> None:
    path = OUT_DIR / filename
    fig.tight_layout()
    fig.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close(fig)
    print(f"  Figura guardada: {path.name}")


def save_cm(y_true, y_pred, labels, title, filename: str) -> None:
    cm = confusion_matrix(y_true, y_pred, labels=labels)
    fig, ax = plt.subplots(figsize=(6, 5))
    sns.heatmap(
        cm,
        annot=True,
        fmt="d",
        cmap="Blues",
        cbar=False,
        xticklabels=labels,
        yticklabels=labels,
        ax=ax,
    )
    ax.set_xlabel("Predicho", fontweight="bold")
    ax.set_ylabel("Real", fontweight="bold")
    ax.set_title(title, fontweight="bold")
    save_figure(fig, filename)


def ensure_columns(df: pd.DataFrame, cols: list[str], fill_value: str = "missing") -> pd.DataFrame:
    out = df.copy()
    for col in cols:
        if col not in out.columns:
            out[col] = fill_value
        out[col] = out[col].fillna(fill_value).astype(str).replace({"nan": fill_value})
    return out


def add_text_features(data: pd.DataFrame, text_col: str = "texto") -> pd.DataFrame:
    d = data.copy()
    d[text_col] = d[text_col].fillna("").astype(str)
    d["n_chars"] = d[text_col].str.len()
    d["n_words"] = d[text_col].str.split().str.len()
    d["n_exclam"] = d[text_col].str.count("!")
    d["n_question"] = d[text_col].str.count(r"\?")
    d["n_upper"] = d[text_col].apply(lambda x: sum(1 for c in x if c.isupper()))
    d["has_url"] = d[text_col].str.contains(r"http|www", case=False, regex=True).astype(int)
    d["has_laughter"] = d[text_col].str.contains(r"jaja|jeje|xd|ajj", case=False, regex=True).astype(int)
    d["has_number"] = d[text_col].str.contains(r"\d", regex=True).astype(int)
    return d


def load_data() -> tuple[pd.DataFrame, pd.DataFrame]:
    print_header("[1] CARGA Y PREPARACION")
    df = pd.read_csv(CSV_PATH, on_bad_lines="skip", encoding="utf-8")
    if "post_id" in df.columns:
        df = df[df["post_id"].astype(str) != "post_id"].copy()
    df["fecha"] = pd.to_datetime(df["fecha"], errors="coerce")
    df["polarizacion_consenso"] = pd.to_numeric(df["polarizacion_consenso"], errors="coerce")
    df["oa_polarizacion"] = pd.to_numeric(df.get("oa_polarizacion"), errors="coerce")
    df["ds_polarizacion"] = pd.to_numeric(df.get("ds_polarizacion"), errors="coerce")
    df["comment_score"] = pd.to_numeric(df.get("comment_score"), errors="coerce")
    df["texto"] = df["comentario_texto"].fillna("").astype(str).str.strip()
    if "fase" not in df.columns:
        df["fase"] = phase_from_date(df["fecha"])
    df["pol_grupo"] = df["polarizacion_consenso"].apply(polar_level)
    df["emocion_grupo"] = df["emocion_final"].astype(str).map(emotion_family)
    df = add_text_features(df, "texto")

    print(f"Filas base: {len(df):,}")
    print(f"Texto no vacio: {(df['texto'].str.len() > 0).sum():,}")
    print(f"Polarizacion valida: {df['polarizacion_consenso'].notna().sum():,}")

    frames = []
    for cand in CANDIDATOS:
        sent_col = f"sent_final_{cand}"
        oa_col = f"oa_sent_{cand}"
        ds_col = f"ds_sent_{cand}"
        if sent_col not in df.columns:
            continue
        sub = df[df["candidatos"].fillna("").str.contains(rf"\b{cand}\b", regex=True, na=False)].copy()
        sub["candidato"] = cand
        sub["sentimiento"] = sub[sent_col]
        sub["oa_sent"] = sub[oa_col] if oa_col in sub.columns else np.nan
        sub["ds_sent"] = sub[ds_col] if ds_col in sub.columns else np.nan
        sub["desacuerdo"] = (sub["oa_sent"] != sub["ds_sent"]).astype(int)
        frames.append(sub)

    df_long = pd.concat(frames, ignore_index=True)
    df_long = add_text_features(df_long, "texto")
    df_long["pol_grupo"] = df_long["polarizacion_consenso"].apply(polar_level)
    fase_long = pd.Series(phase_from_date(df_long["fecha"]), index=df_long.index)
    df_long["fase"] = df_long["fase"].fillna(fase_long)

    print(f"Dataset largo: {len(df_long):,}")
    print(df_long["candidato"].value_counts().to_string())

    save_df(df_long, "dataset_largo_enriquecido.csv")
    return df, df_long


NUM_COLS = [
    "comment_score",
    "n_chars",
    "n_words",
    "n_exclam",
    "n_question",
    "n_upper",
    "has_url",
    "has_laughter",
    "has_number",
]
CAT_DISCURSIVAS = [
    "marco_final",
    "emocion_final",
    "estrategia_final",
    "frontera_final",
    "candidato",
    "fase",
    "tipo_hilo",
]


def make_preprocessor(
    text_col: str | None = None,
    cat_cols: list[str] | None = None,
    num_cols: list[str] | None = None,
) -> ColumnTransformer:
    transformers = []
    if text_col:
        transformers.append(
            (
                "tfidf",
                TfidfVectorizer(
                    lowercase=True,
                    ngram_range=(1, 2),
                    min_df=5,
                    max_df=0.95,
                    sublinear_tf=True,
                    stop_words=list(SPANISH_STOPWORDS),
                    max_features=20000,
                ),
                text_col,
            )
        )
    if cat_cols:
        transformers.append(("cat", OneHotEncoder(handle_unknown="ignore"), cat_cols))
    if num_cols:
        transformers.append(
            (
                "num",
                Pipeline(
                    [
                        ("imp", SimpleImputer(strategy="median")),
                        ("sc", StandardScaler(with_mean=False)),
                    ]
                ),
                num_cols,
            )
        )
    return ColumnTransformer(transformers=transformers, remainder="drop")


def split_xy(df: pd.DataFrame, y_col: str, feature_cols: list[str], stratify: bool = False):
    data = df.copy()
    for col in feature_cols:
        if col not in data.columns:
            data[col] = np.nan
    y = data[y_col]
    strat = y if stratify and y.nunique() > 1 and y.value_counts().min() >= 2 else None
    return train_test_split(
        data[feature_cols],
        y,
        test_size=0.2,
        random_state=RANDOM_STATE,
        stratify=strat,
    )


def top_terms_from_texts(
    texts: pd.Series,
    top_n: int = 25,
    min_df: int = 5,
    ngram_range: tuple[int, int] = (1, 1),
) -> pd.DataFrame:
    texts = pd.Series(texts).fillna("").astype(str)
    nonempty = texts[texts.str.len() > 0]
    if len(nonempty) < max(10, min_df):
        return pd.DataFrame(columns=["term", "score"])
    vec = TfidfVectorizer(
        lowercase=True,
        stop_words=list(SPANISH_STOPWORDS),
        sublinear_tf=True,
        min_df=min_df,
        max_df=0.95,
        ngram_range=ngram_range,
    )
    try:
        X = vec.fit_transform(nonempty)
    except ValueError:
        return pd.DataFrame(columns=["term", "score"])
    scores = np.asarray(X.mean(axis=0)).ravel()
    terms = np.array(vec.get_feature_names_out())
    idx = scores.argsort()[::-1][:top_n]
    return pd.DataFrame({"term": terms[idx], "score": scores[idx]})


def count_top_bigrams(texts: pd.Series, top_n: int = 20, min_df: int = 3) -> pd.DataFrame:
    texts = pd.Series(texts).fillna("").astype(str)
    nonempty = texts[texts.str.len() > 0]
    if len(nonempty) < max(5, min_df):
        return pd.DataFrame(columns=["bigram", "count"])
    vec = CountVectorizer(
        lowercase=True,
        stop_words=list(SPANISH_STOPWORDS),
        ngram_range=(2, 2),
        min_df=min_df,
    )
    try:
        X = vec.fit_transform(nonempty)
    except ValueError:
        return pd.DataFrame(columns=["bigram", "count"])
    counts = np.asarray(X.sum(axis=0)).ravel()
    terms = np.array(vec.get_feature_names_out())
    idx = counts.argsort()[::-1][:top_n]
    return pd.DataFrame({"bigram": terms[idx], "count": counts[idx]})


def mean_ci_table(df: pd.DataFrame, group_col: str, value_col: str) -> pd.DataFrame:
    out = (
        df.groupby(group_col)[value_col]
        .agg(["mean", "std", "count"])
        .reset_index()
        .rename(columns={"count": "n"})
    )
    out["se"] = out["std"] / np.sqrt(out["n"].clip(lower=1))
    out["ci95"] = 1.96 * out["se"].fillna(0)
    return out.sort_values("mean", ascending=False)


def block_a_candidate_distribution(df_long: pd.DataFrame, summary_rows: list[dict]) -> None:
    print_header("[A1] POLARIZACION POR CANDIDATO")
    d = df_long[df_long["polarizacion_consenso"].notna()].copy()
    order = [c for c in CANDIDATOS if c in set(d["candidato"])]

    fig, ax = plt.subplots(figsize=(10, 6))
    sns.violinplot(
        data=d, x="candidato", y="polarizacion_consenso",
        order=order, inner=None, cut=0, palette=COLORES_CAND, ax=ax
    )
    sns.boxplot(
        data=d, x="candidato", y="polarizacion_consenso",
        order=order, width=0.2, showcaps=True,
        boxprops={"facecolor": "white", "zorder": 3},
        whiskerprops={"linewidth": 1.2},
        medianprops={"color": "black", "linewidth": 1.8},
        showfliers=False,
        ax=ax,
    )
    ax.set_title("Distribucion de polarizacion por candidato", fontweight="bold")
    ax.set_xlabel("Candidato")
    ax.set_ylabel("Polarizacion consenso")
    save_figure(fig, "polarizacion_por_candidato_violin.png")

    groups = [d.loc[d["candidato"] == c, "polarizacion_consenso"] for c in order]
    h_stat, p_val = stats.kruskal(*groups)
    eta2 = eta_squared_kruskal(h_stat, len(groups), len(d))
    summary_rows.append(
        {
            "bloque": "A1",
            "analisis": "Kruskal polarizacion por candidato",
            "grupo_1": "todos",
            "grupo_2": "candidato",
            "estadistico": h_stat,
            "p_value": p_val,
            "efecto": eta2,
            "metrica": "eta2_h",
            "n": len(d),
        }
    )

    rows = []
    p_list = []
    pairs = list(combinations(order, 2))
    for c1, c2 in pairs:
        x = d.loc[d["candidato"] == c1, "polarizacion_consenso"]
        y = d.loc[d["candidato"] == c2, "polarizacion_consenso"]
        u = stats.mannwhitneyu(x, y, alternative="two-sided")
        p_list.append(u.pvalue)
        rows.append(
            {
                "candidato_1": c1,
                "candidato_2": c2,
                "n1": len(x),
                "n2": len(y),
                "media_1": x.mean(),
                "media_2": y.mean(),
                "u_stat": u.statistic,
                "p_value": u.pvalue,
                "cohen_d": cohen_d(x, y),
                "rank_biserial": rank_biserial_from_u(u.statistic, len(x), len(y)),
            }
        )
    adj = p_bonferroni(p_list)
    for row, p_adj in zip(rows, adj):
        row["p_bonferroni"] = p_adj
        summary_rows.append(
            {
                "bloque": "A1",
                "analisis": "Mann-Whitney posthoc candidato",
                "grupo_1": row["candidato_1"],
                "grupo_2": row["candidato_2"],
                "estadistico": row["u_stat"],
                "p_value": row["p_bonferroni"],
                "efecto": row["cohen_d"],
                "metrica": "cohen_d",
                "n": row["n1"] + row["n2"],
            }
        )
    save_df(pd.DataFrame(rows), "posthoc_polarizacion_candidatos.csv")


def block_a_frame_candidate(df_long: pd.DataFrame, summary_rows: list[dict]) -> None:
    print_header("[A2] POLARIZACION POR MARCO x CANDIDATO")
    d = df_long[df_long["polarizacion_consenso"].notna()].copy()
    d = ensure_columns(d, ["marco_final"])
    stats_frame = mean_ci_table(d, "marco_final", "polarizacion_consenso")
    save_df(stats_frame, "polarizacion_por_marco_resumen.csv")

    pivot = d.pivot_table(
        index="marco_final",
        columns="candidato",
        values="polarizacion_consenso",
        aggfunc="mean",
    )
    fig, ax = plt.subplots(figsize=(10, 7))
    sns.heatmap(pivot, cmap="magma", annot=True, fmt=".2f", linewidths=0.5, ax=ax)
    ax.set_title("Polarizacion media por marco y candidato", fontweight="bold")
    save_figure(fig, "heatmap_polarizacion_marco_candidato.png")

    fig, ax = plt.subplots(figsize=(10, 6))
    plot_df = stats_frame.sort_values("mean", ascending=False)
    ax.barh(plot_df["marco_final"], plot_df["mean"], xerr=plot_df["ci95"], color="#7D3C98", alpha=0.85)
    ax.invert_yaxis()
    ax.set_xlabel("Polarizacion media")
    ax.set_ylabel("Marco")
    ax.set_title("Polarizacion media por marco (IC 95%)", fontweight="bold")
    save_figure(fig, "polarizacion_por_marco_ic95.png")

    groups = [
        d.loc[d["marco_final"] == marco, "polarizacion_consenso"]
        for marco in sorted(d["marco_final"].dropna().unique())
    ]
    h_stat, p_val = stats.kruskal(*groups)
    eta2 = eta_squared_kruskal(h_stat, len(groups), len(d))
    summary_rows.append(
        {
            "bloque": "A2",
            "analisis": "Kruskal polarizacion por marco",
            "grupo_1": "todos",
            "grupo_2": "marco_final",
            "estadistico": h_stat,
            "p_value": p_val,
            "efecto": eta2,
            "metrica": "eta2_h",
            "n": len(d),
        }
    )


def block_a_emotions(df: pd.DataFrame, summary_rows: list[dict]) -> None:
    print_header("[A3] POLARIZACION POR EMOCION")
    d = df[df["polarizacion_consenso"].notna()].copy()
    d = ensure_columns(d, ["emocion_final"])
    stats_emo = mean_ci_table(d, "emocion_final", "polarizacion_consenso")
    stats_emo["grupo_emocional"] = stats_emo["emocion_final"].map(emotion_family)
    save_df(stats_emo, "polarizacion_por_emocion_resumen.csv")

    fig, ax = plt.subplots(figsize=(10, 6.5))
    colors = [COLORES_EMO.get(e, "#7F8C8D") for e in stats_emo["emocion_final"]]
    ax.barh(stats_emo["emocion_final"], stats_emo["mean"], xerr=stats_emo["ci95"], color=colors)
    ax.invert_yaxis()
    ax.set_xlabel("Polarizacion media")
    ax.set_ylabel("Emocion")
    ax.set_title("Polarizacion por emocion", fontweight="bold")
    save_figure(fig, "polarizacion_por_emocion.png")

    groups = [
        d.loc[d["emocion_final"] == emo, "polarizacion_consenso"]
        for emo in sorted(d["emocion_final"].dropna().unique())
    ]
    h_stat, p_val = stats.kruskal(*groups)
    eta2 = eta_squared_kruskal(h_stat, len(groups), len(d))
    summary_rows.append(
        {
            "bloque": "A3",
            "analisis": "Kruskal polarizacion por emocion",
            "grupo_1": "todos",
            "grupo_2": "emocion_final",
            "estadistico": h_stat,
            "p_value": p_val,
            "efecto": eta2,
            "metrica": "eta2_h",
            "n": len(d),
        }
    )

    host = d.loc[d["emocion_final"].isin(HOSTILES), "polarizacion_consenso"]
    mod = d.loc[d["emocion_final"].isin(MODERADAS), "polarizacion_consenso"]
    if len(host) and len(mod):
        u = stats.mannwhitneyu(host, mod, alternative="two-sided")
        summary_rows.append(
            {
                "bloque": "A3",
                "analisis": "Hostiles vs moderadas",
                "grupo_1": "hostiles",
                "grupo_2": "moderadas",
                "estadistico": u.statistic,
                "p_value": u.pvalue,
                "efecto": cohen_d(host, mod),
                "metrica": "cohen_d",
                "n": len(host) + len(mod),
            }
        )


def block_a_strategies(df: pd.DataFrame, summary_rows: list[dict]) -> None:
    print_header("[A4] POLARIZACION POR ESTRATEGIA ADVERSARIAL")
    d = df[df["polarizacion_consenso"].notna()].copy()
    d = ensure_columns(d, ["estrategia_final"])
    stats_est = mean_ci_table(d, "estrategia_final", "polarizacion_consenso")
    save_df(stats_est, "polarizacion_por_estrategia_resumen.csv")

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.barh(stats_est["estrategia_final"], stats_est["mean"], xerr=stats_est["se"], color="#AF601A", alpha=0.9)
    ax.invert_yaxis()
    ax.set_xlabel("Polarizacion media")
    ax.set_ylabel("Estrategia")
    ax.set_title("Polarizacion por estrategia adversarial (SE)", fontweight="bold")
    save_figure(fig, "polarizacion_por_estrategia.png")

    groups = [
        d.loc[d["estrategia_final"] == est, "polarizacion_consenso"]
        for est in sorted(d["estrategia_final"].dropna().unique())
    ]
    h_stat, p_val = stats.kruskal(*groups)
    eta2 = eta_squared_kruskal(h_stat, len(groups), len(d))
    summary_rows.append(
        {
            "bloque": "A4",
            "analisis": "Kruskal polarizacion por estrategia",
            "grupo_1": "todos",
            "grupo_2": "estrategia_final",
            "estadistico": h_stat,
            "p_value": p_val,
            "efecto": eta2,
            "metrica": "eta2_h",
            "n": len(d),
        }
    )

    x = d.loc[d["estrategia_final"] == "construccion_amenaza", "polarizacion_consenso"]
    y = d.loc[d["estrategia_final"] == "ridiculizacion", "polarizacion_consenso"]
    if len(x) and len(y):
        u = stats.mannwhitneyu(x, y, alternative="two-sided")
        summary_rows.append(
            {
                "bloque": "A4",
                "analisis": "Construccion amenaza vs ridiculizacion",
                "grupo_1": "construccion_amenaza",
                "grupo_2": "ridiculizacion",
                "estadistico": u.statistic,
                "p_value": u.pvalue,
                "efecto": cohen_d(x, y),
                "metrica": "cohen_d",
                "n": len(x) + len(y),
            }
        )


def block_a_polalta(df_long: pd.DataFrame, summary_rows: list[dict]) -> None:
    print_header("[A5] CLASIFICACION DE POLARIZACION ALTA")
    d = df_long[df_long["polarizacion_consenso"].notna()].copy()
    d["pol_alta"] = (d["polarizacion_consenso"] >= 0.6).astype(int)
    d = ensure_columns(d, CAT_DISCURSIVAS)
    d = d[(d["texto"].str.len() > 5)].copy()

    feature_cols = ["texto"] + CAT_DISCURSIVAS + NUM_COLS
    X_train, X_test, y_train, y_test = split_xy(d, "pol_alta", feature_cols, stratify=True)
    prep = make_preprocessor(text_col="texto", cat_cols=CAT_DISCURSIVAS, num_cols=NUM_COLS)

    models = {
        "logreg": LogisticRegression(max_iter=3000, class_weight="balanced"),
        "random_forest": RandomForestClassifier(
            n_estimators=300,
            random_state=RANDOM_STATE,
            class_weight="balanced_subsample",
            min_samples_leaf=2,
            n_jobs=-1,
        ),
        "gbm": GradientBoostingClassifier(random_state=RANDOM_STATE),
    }

    rows = []
    best_name = None
    best_f1 = -1.0
    best_pred = None
    for name, model in models.items():
        if name == "gbm":
            pipe = Pipeline(
                [
                    ("prep", prep),
                    ("svd", TruncatedSVD(n_components=300, random_state=RANDOM_STATE)),
                    ("model", model),
                ]
            )
        else:
            pipe = Pipeline([("prep", prep), ("model", model)])
        pipe.fit(X_train, y_train)
        pred = pipe.predict(X_test)
        row = {
            "modelo": name,
            "accuracy": accuracy_score(y_test, pred),
            "precision": precision_score(y_test, pred, zero_division=0),
            "recall": recall_score(y_test, pred, zero_division=0),
            "f1": f1_score(y_test, pred, zero_division=0),
        }
        rows.append(row)
        summary_rows.append(
            {
                "bloque": "A5",
                "analisis": f"Clasificacion polarizacion alta - {name}",
                "grupo_1": "pol_alta",
                "grupo_2": "test",
                "estadistico": row["accuracy"],
                "p_value": np.nan,
                "efecto": row["f1"],
                "metrica": "f1",
                "n": len(y_test),
            }
        )
        if row["f1"] > best_f1:
            best_f1 = row["f1"]
            best_name = name
            best_pred = pred
        print(f"\n{name}\n{classification_report(y_test, pred, digits=3)}")

    save_df(pd.DataFrame(rows).sort_values("f1", ascending=False), "resumen_clasificacion_polarizacion_alta.csv")
    save_cm(y_test, best_pred, [0, 1], f"Polarizacion alta >= 0.6 — {best_name}", "cm_polarizacion_alta.png")


def block_a_regression_compare(df_long: pd.DataFrame, summary_rows: list[dict]) -> None:
    print_header("[A6] REGRESION SOLO VARIABLES DISCURSIVAS VS CON TEXTO")
    d = df_long[df_long["polarizacion_consenso"].notna()].copy()
    d = ensure_columns(d, CAT_DISCURSIVAS)
    d = d[(d["texto"].str.len() > 5)].copy()

    X_train_cat, X_test_cat, y_train, y_test = split_xy(d, "polarizacion_consenso", CAT_DISCURSIVAS)
    X_train_full, X_test_full, _, _ = split_xy(d, "polarizacion_consenso", ["texto"] + CAT_DISCURSIVAS + NUM_COLS)

    rows = []
    configs = {
        "ridge_categoricas": (
            make_preprocessor(cat_cols=CAT_DISCURSIVAS),
            Ridge(alpha=1.0),
        ),
        "rf_categoricas": (
            make_preprocessor(cat_cols=CAT_DISCURSIVAS),
            RandomForestRegressor(n_estimators=300, random_state=RANDOM_STATE, n_jobs=-1),
        ),
        "ridge_texto_full": (
            make_preprocessor(text_col="texto", cat_cols=CAT_DISCURSIVAS, num_cols=NUM_COLS),
            Ridge(alpha=1.0),
        ),
        "rf_texto_full": (
            make_preprocessor(text_col="texto", cat_cols=CAT_DISCURSIVAS, num_cols=NUM_COLS),
            RandomForestRegressor(n_estimators=300, random_state=RANDOM_STATE, n_jobs=-1),
        ),
    }

    for name, (prep, model) in configs.items():
        if "texto_full" in name:
            X_tr, X_te = X_train_full, X_test_full
        else:
            X_tr, X_te = X_train_cat, X_test_cat
        pipe = Pipeline([("prep", prep), ("model", model)])
        pipe.fit(X_tr, y_train)
        pred = pipe.predict(X_te)
        row = {
            "modelo": name,
            "mae": mean_absolute_error(y_test, pred),
            "rmse": np.sqrt(mean_squared_error(y_test, pred)),
            "r2": r2_score(y_test, pred),
        }
        rows.append(row)
        summary_rows.append(
            {
                "bloque": "A6",
                "analisis": f"Regresion polarizacion - {name}",
                "grupo_1": name,
                "grupo_2": "test",
                "estadistico": row["mae"],
                "p_value": np.nan,
                "efecto": row["r2"],
                "metrica": "r2",
                "n": len(y_test),
            }
        )
    save_df(pd.DataFrame(rows).sort_values("r2", ascending=False), "comparacion_regresion_discursiva_vs_texto.csv")


def block_b_top_words_candidate(df_long: pd.DataFrame) -> None:
    print_header("[B1] TOP WORDS POR CANDIDATO")
    fig, axes = plt.subplots(2, 2, figsize=(15, 12))
    rows = []
    for ax, cand in zip(axes.flat, CANDIDATOS):
        sub = df_long[df_long["candidato"] == cand]
        top = top_terms_from_texts(sub["texto"], top_n=25, min_df=4)
        rows.append(top.assign(candidato=cand))
        if top.empty:
            ax.set_axis_off()
            continue
        ax.barh(top["term"][::-1], top["score"][::-1], color=COLORES_CAND.get(cand, "#566573"))
        ax.set_title(cand.capitalize(), fontweight="bold")
        ax.set_xlabel("TF-IDF medio")
    save_figure(fig, "top_words_por_candidato.png")
    save_df(pd.concat(rows, ignore_index=True), "top_words_por_candidato.csv")


def block_b_top_words_polar_level(df: pd.DataFrame) -> None:
    print_header("[B2] TOP WORDS POR NIVEL DE POLARIZACION")
    d = df[df["pol_grupo"].notna() & (df["texto"].str.len() > 0)].copy()
    rows = []
    fig, axes = plt.subplots(1, 3, figsize=(18, 7))
    levels = ["alta", "media", "baja"]
    for ax, level in zip(axes, levels):
        sub = d[d["pol_grupo"] == level]
        top = top_terms_from_texts(sub["texto"], top_n=20, min_df=4)
        rows.append(top.assign(pol_grupo=level))
        if top.empty:
            ax.set_axis_off()
            continue
        ax.barh(top["term"][::-1], top["score"][::-1], color=COLORES_POL[level])
        ax.set_title(level.capitalize(), fontweight="bold")
        ax.set_xlabel("TF-IDF medio")
    save_figure(fig, "top_words_por_nivel_polarizacion.png")
    save_df(pd.concat(rows, ignore_index=True), "top_words_por_nivel_polarizacion.csv")

    texts = d[d["pol_grupo"].isin(["alta", "baja"])]["texto"].fillna("").astype(str)
    vec = TfidfVectorizer(
        lowercase=True,
        stop_words=list(SPANISH_STOPWORDS),
        sublinear_tf=True,
        min_df=5,
        max_df=0.95,
    )
    X = vec.fit_transform(texts)
    terms = np.array(vec.get_feature_names_out())
    mask_high = d[d["pol_grupo"].isin(["alta", "baja"])]["pol_grupo"].eq("alta").to_numpy()
    high_mean = np.asarray(X[mask_high].mean(axis=0)).ravel()
    low_mean = np.asarray(X[~mask_high].mean(axis=0)).ravel()
    ratio = np.log2((high_mean + 1e-6) / (low_mean + 1e-6))
    top_high_idx = ratio.argsort()[::-1][:15]
    top_low_idx = ratio.argsort()[:15]
    ratio_df = pd.concat(
        [
            pd.DataFrame({"term": terms[top_high_idx], "ratio_score": ratio[top_high_idx], "grupo": "alta"}),
            pd.DataFrame({"term": terms[top_low_idx], "ratio_score": ratio[top_low_idx], "grupo": "baja"}),
        ],
        ignore_index=True,
    )
    save_df(ratio_df, "ratio_words_alta_vs_baja.csv")

    fig, ax = plt.subplots(figsize=(10, 8))
    plot_df = ratio_df.sort_values("ratio_score")
    colors = plot_df["grupo"].map({"alta": COLORES_POL["alta"], "baja": COLORES_POL["baja"]})
    ax.barh(plot_df["term"], plot_df["ratio_score"], color=colors)
    ax.axvline(0, color="black", linewidth=1)
    ax.set_xlabel("log2(Alta / Baja)")
    ax.set_title("Palabras diferenciales: polarizacion alta vs baja", fontweight="bold")
    save_figure(fig, "ratio_words_alta_vs_baja.png")


def block_b_top_words_emotion(df: pd.DataFrame) -> None:
    print_header("[B3] TOP WORDS POR EMOCION")
    d = df[df["emocion_final"].notna() & (df["texto"].str.len() > 0)].copy()
    emotions = [e for e in ["indignacion", "ira", "desprecio", "miedo", "esperanza", "alegria", "ironia", "ninguna"] if e in set(d["emocion_final"])]
    rows = []
    ncols = 2
    nrows = math.ceil(len(emotions) / ncols)
    fig, axes = plt.subplots(nrows, ncols, figsize=(16, 4.8 * nrows))
    axes = np.atleast_1d(axes).ravel()
    for ax, emo in zip(axes, emotions):
        sub = d[d["emocion_final"] == emo]
        top = top_terms_from_texts(sub["texto"], top_n=15, min_df=4)
        rows.append(top.assign(emocion=emo))
        if top.empty:
            ax.set_axis_off()
            continue
        ax.barh(top["term"][::-1], top["score"][::-1], color=COLORES_EMO.get(emo, "#7F8C8D"))
        ax.set_title(emo.capitalize(), fontweight="bold")
        ax.set_xlabel("TF-IDF medio")
    for ax in axes[len(emotions):]:
        ax.set_axis_off()
    save_figure(fig, "top_words_por_emocion.png")
    save_df(pd.concat(rows, ignore_index=True), "top_words_por_emocion.csv")


def centroid_map(df: pd.DataFrame, group_col: str, filename: str, title: str, palette: dict | None = None) -> None:
    d = df[df[group_col].notna() & (df["texto"].str.len() > 0)].copy()
    vec = TfidfVectorizer(
        lowercase=True,
        stop_words=list(SPANISH_STOPWORDS),
        sublinear_tf=True,
        min_df=5,
        max_df=0.95,
    )
    X = vec.fit_transform(d["texto"])
    groups = sorted(d[group_col].astype(str).unique())
    centroids = []
    labels = []
    for group in groups:
        mask = d[group_col].astype(str).eq(group).to_numpy()
        if mask.sum() < 5:
            continue
        centroids.append(np.asarray(X[mask].mean(axis=0)).ravel())
        labels.append(group)
    if len(centroids) < 2:
        return
    M = np.vstack(centroids)
    svd = TruncatedSVD(n_components=2, random_state=RANDOM_STATE)
    coords = svd.fit_transform(M)
    plot_df = pd.DataFrame({"label": labels, "x": coords[:, 0], "y": coords[:, 1]})
    fig, ax = plt.subplots(figsize=(9, 7))
    for _, row in plot_df.iterrows():
        color = palette.get(row["label"], "#2C3E50") if palette else "#2C3E50"
        ax.scatter(row["x"], row["y"], s=80, color=color)
        ax.text(row["x"] + 0.01, row["y"] + 0.01, row["label"], fontsize=11)
    ax.axhline(0, color="#D5D8DC", linewidth=1)
    ax.axvline(0, color="#D5D8DC", linewidth=1)
    ax.set_title(title, fontweight="bold")
    ax.set_xlabel("SVD 1")
    ax.set_ylabel("SVD 2")
    save_figure(fig, filename)


def block_b_maps(df: pd.DataFrame, df_long: pd.DataFrame) -> None:
    print_header("[B4] MAPAS CONCEPTUALES 2D")
    centroid_map(
        df_long,
        "candidato",
        "mapa_conceptual_candidatos.png",
        "Mapa conceptual 2D por candidato (centroides TF-IDF)",
        palette=COLORES_CAND,
    )
    theme_col = "tema" if "tema" in df.columns else "marco_final"
    centroid_map(
        df,
        theme_col,
        "mapa_conceptual_temas.png",
        f"Mapa conceptual 2D por {theme_col} (centroides TF-IDF)",
    )


def block_b_bigrams(df_long: pd.DataFrame) -> None:
    print_header("[B5] BIGRAMAS POR CANDIDATO")
    rows = []
    fig, axes = plt.subplots(2, 2, figsize=(15, 12))
    for ax, cand in zip(axes.flat, CANDIDATOS):
        sub = df_long[df_long["candidato"] == cand]
        top = count_top_bigrams(sub["texto"], top_n=20, min_df=3)
        rows.append(top.assign(candidato=cand))
        if top.empty:
            ax.set_axis_off()
            continue
        ax.barh(top["bigram"][::-1], top["count"][::-1], color=COLORES_CAND.get(cand, "#566573"))
        ax.set_title(cand.capitalize(), fontweight="bold")
        ax.set_xlabel("Frecuencia")
    save_figure(fig, "bigramas_por_candidato.png")
    save_df(pd.concat(rows, ignore_index=True), "bigramas_por_candidato.csv")


def block_c_time_series(df_long: pd.DataFrame) -> None:
    print_header("[C1] SERIE TEMPORAL DE POLARIZACION")
    d = df_long[df_long["polarizacion_consenso"].notna() & df_long["fecha"].notna()].copy()
    d["semana"] = d["fecha"].dt.to_period("W").apply(lambda r: r.start_time)
    weekly = (
        d.groupby(["candidato", "semana"])["polarizacion_consenso"]
        .agg(["mean", "std", "count"])
        .reset_index()
        .rename(columns={"count": "n"})
    )
    weekly = weekly[weekly["n"] >= 5].copy()
    weekly["se"] = weekly["std"] / np.sqrt(weekly["n"])
    weekly["ci95"] = 1.96 * weekly["se"].fillna(0)
    weekly = weekly.sort_values(["candidato", "semana"])
    weekly["media_movil_3"] = (
        weekly.groupby("candidato")["mean"]
        .transform(lambda s: s.rolling(3, min_periods=1).mean())
    )
    save_df(weekly, "serie_polarizacion_semanal.csv")

    fig, ax = plt.subplots(figsize=(12, 7))
    for cand in CANDIDATOS:
        sub = weekly[weekly["candidato"] == cand]
        if sub.empty:
            continue
        color = COLORES_CAND.get(cand, "#2C3E50")
        ax.plot(sub["semana"], sub["media_movil_3"], color=color, linewidth=2.5, label=cand.capitalize())
        ax.fill_between(
            sub["semana"],
            sub["mean"] - sub["ci95"],
            sub["mean"] + sub["ci95"],
            color=color,
            alpha=0.18,
        )
        ax.scatter(sub["semana"], sub["mean"], color=color, alpha=0.45, s=22)
    ax.axvline(FIRST_ROUND_DATE, linestyle="--", color="black", linewidth=1.5, label="Primera vuelta")
    ax.set_title("Polarizacion semanal por candidato", fontweight="bold")
    ax.set_xlabel("Semana")
    ax.set_ylabel("Polarizacion media")
    ax.legend()
    save_figure(fig, "serie_polarizacion_semanal_candidatos.png")


def block_c_phase_change(df_long: pd.DataFrame, summary_rows: list[dict]) -> None:
    print_header("[C2] CAMBIO ENTRE FASES")
    rows = []
    for cand in CANDIDATOS:
        sub = df_long[(df_long["candidato"] == cand) & df_long["polarizacion_consenso"].notna()].copy()
        x = sub.loc[sub["fase"] == "posicionamiento", "polarizacion_consenso"]
        y = sub.loc[sub["fase"] == "segunda_vuelta", "polarizacion_consenso"]
        if len(x) < 5 or len(y) < 5:
            continue
        u = stats.mannwhitneyu(x, y, alternative="two-sided")
        row = {
            "candidato": cand,
            "n_posicionamiento": len(x),
            "n_segunda_vuelta": len(y),
            "media_posicionamiento": x.mean(),
            "media_segunda_vuelta": y.mean(),
            "u_stat": u.statistic,
            "p_value": u.pvalue,
            "cohen_d": cohen_d(x, y),
            "rank_biserial": rank_biserial_from_u(u.statistic, len(x), len(y)),
        }
        rows.append(row)
        summary_rows.append(
            {
                "bloque": "C2",
                "analisis": "Cambio de polarizacion entre fases",
                "grupo_1": f"{cand}: posicionamiento",
                "grupo_2": f"{cand}: segunda_vuelta",
                "estadistico": row["u_stat"],
                "p_value": row["p_value"],
                "efecto": row["cohen_d"],
                "metrica": "cohen_d",
                "n": len(x) + len(y),
            }
        )
    if rows:
        save_df(pd.DataFrame(rows), "cambio_polarizacion_por_fase.csv")


def block_c_karma(df_long: pd.DataFrame) -> None:
    print_header("[C3] KARMA x POLARIZACION")
    d = df_long[df_long["polarizacion_consenso"].notna() & df_long["comment_score"].notna()].copy()
    karma_cut = d["comment_score"].median()
    pol_cut = 0.6
    d["cuadrante"] = np.select(
        [
            (d["comment_score"] >= karma_cut) & (d["polarizacion_consenso"] >= pol_cut),
            (d["comment_score"] < karma_cut) & (d["polarizacion_consenso"] >= pol_cut),
            (d["comment_score"] >= karma_cut) & (d["polarizacion_consenso"] < pol_cut),
        ],
        ["alto_karma_alta_pol", "bajo_karma_alta_pol", "alto_karma_baja_pol"],
        default="bajo_karma_baja_pol",
    )
    quad = d.groupby(["candidato", "cuadrante"]).size().reset_index(name="n")
    save_df(quad, "karma_polarizacion_cuadrantes.csv")

    fig, ax = plt.subplots(figsize=(11, 7))
    for cand in CANDIDATOS:
        sub = d[d["candidato"] == cand].sort_values("comment_score")
        if sub.empty:
            continue
        color = COLORES_CAND.get(cand, "#2C3E50")
        ax.scatter(
            sub["comment_score"],
            sub["polarizacion_consenso"],
            alpha=0.18,
            s=18,
            color=color,
            label=cand.capitalize(),
        )
        if LOWESS_OK and len(sub) > 20:
            sm = lowess(
                sub["polarizacion_consenso"].to_numpy(),
                sub["comment_score"].to_numpy(),
                frac=0.25,
                return_sorted=True,
            )
            ax.plot(sm[:, 0], sm[:, 1], color=color, linewidth=2.4)
        elif len(sub) > 20:
            smooth = (
                sub[["comment_score", "polarizacion_consenso"]]
                .rolling(35, min_periods=10)
                .mean()
                .dropna()
            )
            ax.plot(smooth["comment_score"], smooth["polarizacion_consenso"], color=color, linewidth=2.0)
    ax.axvline(karma_cut, linestyle="--", color="black", linewidth=1.2)
    ax.axhline(pol_cut, linestyle="--", color="black", linewidth=1.2)
    ax.set_title("Karma y polarizacion por candidato", fontweight="bold")
    ax.set_xlabel(f"Comment score (corte mediana = {karma_cut:.1f})")
    ax.set_ylabel("Polarizacion consenso")
    ax.legend()
    save_figure(fig, "karma_polarizacion_loess.png")


def save_summary(summary_rows: list[dict]) -> None:
    if not summary_rows:
        return
    df = pd.DataFrame(summary_rows)
    save_df(df, "resumen_estadisticos_tesis.csv")


def main() -> None:
    df, df_long = load_data()
    summary_rows: list[dict] = []

    block_a_candidate_distribution(df_long, summary_rows)
    block_a_frame_candidate(df_long, summary_rows)
    block_a_emotions(df, summary_rows)
    block_a_strategies(df, summary_rows)
    block_a_polalta(df_long, summary_rows)
    block_a_regression_compare(df_long, summary_rows)

    block_b_top_words_candidate(df_long)
    block_b_top_words_polar_level(df)
    block_b_top_words_emotion(df)
    block_b_maps(df, df_long)
    block_b_bigrams(df_long)

    block_c_time_series(df_long)
    block_c_phase_change(df_long, summary_rows)
    block_c_karma(df_long)

    save_summary(summary_rows)

    print_header("ANALISIS COMPLETADO")
    print(f"Outputs disponibles en: {OUT_DIR}")


if __name__ == "__main__":
    main()
