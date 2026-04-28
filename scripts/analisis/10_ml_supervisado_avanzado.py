"""
# ============================================================================
# 10_ml_supervisado_avanzado.py
# ============================================================================
# Tesis máster — comunicación política Reddit Chile 2025.
# Stack: Python únicamente. Sin R, BERT ni embeddings de terceros.
# Nivel: publicable (APSR / Political Communication).
#
# Carga: outputs_ml/dataset_largo_enriquecido.csv + data/processed/analisis_API.csv
# Salida: outputs_ml/ (véase checklist al final).
# ============================================================================
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import shutil
import warnings
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy import stats
from sklearn.calibration import CalibratedClassifierCV, calibration_curve
from sklearn.compose import ColumnTransformer
from sklearn.decomposition import TruncatedSVD
from sklearn.ensemble import (
    GradientBoostingClassifier,
    GradientBoostingRegressor,
    RandomForestClassifier,
    RandomForestRegressor,
    StackingClassifier,
    StackingRegressor,
)
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.metrics import (
    accuracy_score,
    brier_score_loss,
    classification_report,
    confusion_matrix,
    f1_score,
    log_loss,
    mean_absolute_error,
    r2_score,
    roc_auc_score,
)
from sklearn.model_selection import (
    KFold,
    StratifiedKFold,
    cross_val_score,
    cross_validate,
    train_test_split,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

warnings.filterwarnings("ignore")

# --- Config global -------------------------------------------------------------
RANDOM_STATE = 42
DPI = 300
FIG_MIN = (11, 7)

COLORES_CAND = {
    "kast": "#C0392B",
    "kaiser": "#E67E22",
    "matthei": "#2980B9",
    "jara": "#27AE60",
    "empate": "#8E44AD",
    "otro": "#95A5A6",
}

# Orden fijo de leyenda en scatter actividad–polarización
CAND_LEGEND_ORDER = ("kast", "kaiser", "matthei", "jara", "empate", "otro")

HOSTILES_EM = {"ira", "desprecio", "indignacion"}


def _load_pipeline_module():
    path = Path(__file__).resolve().parent / "07_pipeline_completo.py"
    spec = importlib.util.spec_from_file_location("pipeline_completo", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


P07 = _load_pipeline_module()
make_preprocessor = P07.make_preprocessor
CAT_COLS = P07.CAT_COLS
NUM_COLS = P07.NUM_COLS
TEXT_COL = P07.TEXT_COL
SPANISH_STOPWORDS = P07.SPANISH_STOPWORDS
ensure_columns = P07.ensure_columns
add_text_features = P07.add_text_features
safe_stratify = P07.safe_stratify


def resolve_base_dir() -> Path:
    env = os.environ.get("THESIS_BASE")
    if env:
        p = Path(env).expanduser()
        if p.is_dir():
            return p
    here = Path(__file__).resolve().parent.parent.parent
    for c in (
        here,
        Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_maci"),
        Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final"),
    ):
        if (c / "outputs_ml" / "dataset_largo_enriquecido.csv").is_file():
            return c
    return here


BASE_DIR = resolve_base_dir()
OUT_DIR = BASE_DIR / "outputs_ml"
FIG_THESIS = BASE_DIR / "documents" / "tesis_book" / "fig_thesis"
DATA_LONG = OUT_DIR / "dataset_largo_enriquecido.csv"
DATA_API = BASE_DIR / "data" / "processed" / "analisis_API.csv"

plt.style.use("seaborn-v0_8-whitegrid")


def _one_hot_encoder():
    try:
        return OneHotEncoder(handle_unknown="ignore", sparse_output=False)
    except TypeError:
        return OneHotEncoder(handle_unknown="ignore", sparse=False)


def safe_ref(series: pd.Series, ref: str, fallback: str = "otro") -> str:
    s = series.astype(str)
    if ref in set(s.unique()):
        return ref
    m = s.mode()
    return str(m.iloc[0]) if len(m) else fallback


def hash_author(name: str) -> str:
    h = hashlib.sha256(str(name).encode("utf-8")).hexdigest()
    return f"u_{h[:16]}"


def logistic_regression(**kwargs):
    try:
        return LogisticRegression(multi_class="multinomial", **kwargs)
    except TypeError:
        kwargs.pop("multi_class", None)
        return LogisticRegression(**kwargs)


# ##############################################################################
# ## CARGA DE DATOS
# ##############################################################################


def load_datasets() -> tuple[pd.DataFrame, pd.DataFrame]:
    if not DATA_LONG.is_file():
        raise FileNotFoundError(DATA_LONG)
    long_df = pd.read_csv(DATA_LONG, on_bad_lines="skip", encoding="utf-8")
    long_df["polarizacion_consenso"] = pd.to_numeric(long_df["polarizacion_consenso"], errors="coerce")
    long_df["comment_score"] = pd.to_numeric(long_df.get("comment_score"), errors="coerce")
    if "texto" not in long_df.columns and "comentario_texto" in long_df.columns:
        long_df["texto"] = long_df["comentario_texto"].fillna("").astype(str)
    long_df = add_text_features(long_df, "texto")
    long_df = ensure_columns(long_df, CAT_COLS)

    api_df = None
    if DATA_API.is_file():
        api_df = pd.read_csv(DATA_API, on_bad_lines="skip", encoding="utf-8")
        api_df["polarizacion_consenso"] = pd.to_numeric(api_df.get("polarizacion_consenso"), errors="coerce")
        api_df["comment_score"] = pd.to_numeric(api_df.get("comment_score"), errors="coerce")
        if "comentario_texto" in api_df.columns:
            api_df["texto"] = api_df["comentario_texto"].fillna("").astype(str)
    else:
        print(f"  [WARN] No se encontró {DATA_API}; análisis 9 limitado.")
        api_df = long_df.copy()
    return long_df, api_df


# ##############################################################################
# #-- ANÁLISIS 1 — OLS: MODERADOR CANDIDATO × EMOCIÓN
# ##############################################################################
# ## Modelos: OLS con/sin interacción (statsmodels)
# ##############################################################################


def analisis1_moderador_candidato_emocion(df: pd.DataFrame) -> None:
    print("\n# [A1] Moderador candidato × emoción (OLS)...")
    d = df[df["polarizacion_consenso"].notna()].copy()
    d["comment_score"] = pd.to_numeric(d["comment_score"], errors="coerce").fillna(
        d["comment_score"].median()
    )
    d["comment_score_c"] = d["comment_score"] - d["comment_score"].mean()
    for col in [
        "marco_final",
        "emocion_final",
        "estrategia_final",
        "candidato",
        "fase",
        "tipo_hilo",
    ]:
        d[col] = d[col].astype(str).replace({"nan": "desconocido"})

    rm = safe_ref(d["marco_final"], "otro")
    re = safe_ref(d["emocion_final"], "ninguna")
    rs = safe_ref(d["estrategia_final"], "ninguna")
    rc = safe_ref(d["candidato"], "matthei")
    rf = safe_ref(d["fase"], "posicionamiento")
    rt = safe_ref(d["tipo_hilo"], "solo_izquierda")

    base_f = (
        f"polarizacion_consenso ~ C(candidato, Treatment('{rc}')) + "
        f"C(emocion_final, Treatment('{re}')) + "
        f"C(estrategia_final, Treatment('{rs}')) + "
        f"C(marco_final, Treatment('{rm}')) + "
        f"C(fase, Treatment('{rf}')) + "
        f"C(tipo_hilo, Treatment('{rt}')) + comment_score_c"
    )
    full_f = (
        f"polarizacion_consenso ~ C(candidato, Treatment('{rc}')) * C(emocion_final, Treatment('{re}')) + "
        f"C(estrategia_final, Treatment('{rs}')) + "
        f"C(marco_final, Treatment('{rm}')) + "
        f"C(fase, Treatment('{rf}')) + "
        f"C(tipo_hilo, Treatment('{rt}')) + comment_score_c"
    )

    try:
        m0 = smf.ols(base_f, data=d).fit()
        m1 = smf.ols(full_f, data=d).fit()
    except Exception as e:
        print(f"  [WARN] OLS A1 falló: {e}")
        return

    print(f"  R² adj sin interacción: {m0.rsquared_adj:.4f}")
    print(f"  R² adj con interacción: {m1.rsquared_adj:.4f}")

    inter_idx = [x for x in m1.params.index.astype(str) if ":" in x or "*" in x]
    rows = []
    ci = m1.conf_int()
    for name in m1.params.index:
        if ":" not in str(name):
            continue
        p = float(m1.pvalues[name])
        if p >= 0.05:
            continue
        rows.append(
            {
                "termino": str(name),
                "coef": float(m1.params[name]),
                "ci_low": float(ci.loc[name, 0]),
                "ci_high": float(ci.loc[name, 1]),
                "p_value": p,
            }
        )

    tab = pd.DataFrame(rows)
    if tab.empty:
        tab = pd.DataFrame(
            {
                "termino": m1.params.index.astype(str),
                "coef": m1.params.values,
                "ci_low": ci[0].values,
                "ci_high": ci[1].values,
                "p_value": m1.pvalues.values,
            }
        )
        tab = tab[tab["termino"].str.contains(":")]
    tab.to_csv(OUT_DIR / "interacciones_candidato_emocion.csv", index=False)

    # Heatmap coef: parse candidato × emoción desde nombres patsy
    cand_levels = sorted(d["candidato"].astype(str).unique())
    emo_levels = sorted(d["emocion_final"].astype(str).unique())
    mat = pd.DataFrame(index=cand_levels, columns=emo_levels, dtype=float)
    pmat = pd.DataFrame(index=cand_levels, columns=emo_levels, dtype=float)
    for name in m1.params.index:
        s = str(name)
        if "C(candidato)" not in s or "C(emocion_final)" not in s or ":" not in s:
            continue
        # formato aproximado: C(candidato)[T.x]:C(emocion_final)[T.y]
        try:
            parts = s.split(":")
            p0, p1 = parts[0], parts[1]
            c_lab = p0.split("[T.")[-1].rstrip("]")
            e_lab = p1.split("[T.")[-1].rstrip("]")
            if c_lab in mat.index and e_lab in mat.columns:
                mat.loc[c_lab, e_lab] = float(m1.params[name])
                pmat.loc[c_lab, e_lab] = float(m1.pvalues[name])
        except Exception:
            continue

    fig, ax = plt.subplots(figsize=(max(11, 0.4 * len(emo_levels)), max(7, 0.35 * len(cand_levels))))
    mask = pmat.isna() | (pmat >= 0.05)
    sns.heatmap(
        mat.astype(float),
        annot=True,
        fmt=".3f",
        cmap="RdBu_r",
        center=0,
        ax=ax,
        mask=mask,
    )
    ax.set_title(
        "Interacción candidato × emoción — coeficientes OLS (celdas p≥0.05 en gris/mask)",
        fontweight="bold",
    )
    fig.savefig(OUT_DIR / "heatmap_interaccion_candidato_emocion.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    # Interaction plot: emociones hostiles, líneas por emoción, x=candidato, y=pol media
    sub = d[d["emocion_final"].astype(str).isin(HOSTILES_EM)]
    if sub.empty:
        print("  [WARN] Sin emociones hostiles para interaction plot.")
        return
    g = (
        sub.groupby(["candidato", "emocion_final"], as_index=False)["polarizacion_consenso"]
        .mean()
        .sort_values(["emocion_final", "candidato"])
    )
    fig, ax = plt.subplots(figsize=FIG_MIN)
    order_c = ["kast", "kaiser", "matthei", "jara"]
    for emo in sorted(g["emocion_final"].unique()):
        gg = g[g["emocion_final"] == emo].set_index("candidato").reindex(order_c).reset_index()
        col = "#333333"
        ax.plot(
            range(len(order_c)),
            gg["polarizacion_consenso"].values,
            "o-",
            label=emo,
            linewidth=2,
            markersize=8,
        )
    ax.set_xticks(range(len(order_c)))
    ax.set_xticklabels([c.capitalize() for c in order_c])
    ax.set_ylabel("Polarización media (consenso)")
    ax.set_title(
        "Interaction plot: polarización media por candidato\n(emociones hostiles: ira, desprecio, indignación)",
        fontweight="bold",
    )
    ax.legend(title="Emoción")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "interaction_plot_emocion_candidato.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)


# ##############################################################################
# #-- ANÁLISIS 2 — CLASIFICACIÓN MULTICLASE: ESTRATEGIA DISCURSIVA
# ##############################################################################
# ## Modelos: LogReg · RandomForest · GradientBoosting
# ##############################################################################


def analisis2_estrategia_multiclase(df: pd.DataFrame) -> None:
    print("\n# [A2] Clasificación multiclase — estrategia_final...")
    d = df.copy()
    d["estrategia_final"] = d["estrategia_final"].astype(str)
    d = d[~d["estrategia_final"].isin(["ninguna", "ERROR", "nan"])].copy()
    d = d[d["texto"].astype(str).str.len() > 3]
    vc = d["estrategia_final"].value_counts()
    if (vc < 30).any():
        print("  [WARN] Alguna clase estrategia n<30; se continúa con advertencia.")
    cat_f = ["candidato", "marco_final", "fase"]
    num_f = ["comment_score", "n_chars", "n_words"]
    d = ensure_columns(d, cat_f + num_f)
    for c in cat_f:
        d[c] = d[c].astype(str)
    for c in num_f:
        d[c] = pd.to_numeric(d[c], errors="coerce")

    X = d[[TEXT_COL] + cat_f + num_f]
    y = d["estrategia_final"].astype(str)

    try:
        X_tr, X_te, y_tr, y_te = train_test_split(
            X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=safe_stratify(y)
        )
    except Exception:
        X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2, random_state=RANDOM_STATE)

    prep = ColumnTransformer(
        [
            (
                "text",
                TfidfVectorizer(
                    lowercase=True,
                    ngram_range=(1, 2),
                    min_df=3,
                    max_df=0.95,
                    sublinear_tf=True,
                    max_features=15000,
                    stop_words=list(SPANISH_STOPWORDS),
                ),
                TEXT_COL,
            ),
            ("cat", _one_hot_encoder(), cat_f),
            (
                "num",
                Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler())]),
                num_f,
            ),
        ]
    )

    models = {
        "LogReg": logistic_regression(max_iter=3000, class_weight="balanced", solver="lbfgs"),
        "RandomForest": RandomForestClassifier(
            n_estimators=300,
            class_weight="balanced_subsample",
            random_state=RANDOM_STATE,
            n_jobs=-1,
        ),
        "GBM": GradientBoostingClassifier(n_estimators=200, random_state=RANDOM_STATE),
    }

    rows = []
    best_name, best_f1, best_pipe = None, -1.0, None
    for name, est in models.items():
        pipe = Pipeline([("prep", prep), ("model", est)])
        pipe.fit(X_tr, y_tr)
        pred = pipe.predict(X_te)
        acc = accuracy_score(y_te, pred)
        f1m = f1_score(y_te, pred, average="macro")
        rep = classification_report(y_te, pred, output_dict=True)
        rows.append({"modelo": name, "accuracy": acc, "f1_macro": f1m, "clase": "", "precision": np.nan, "recall": np.nan, "f1_clase": np.nan, "support": np.nan})
        for k, v in rep.items():
            if k == "accuracy":
                continue
            if isinstance(v, dict) and "f1-score" in v:
                rows.append(
                    {
                        "modelo": name,
                        "accuracy": np.nan,
                        "f1_macro": np.nan,
                        "clase": k,
                        "precision": v.get("precision"),
                        "recall": v.get("recall"),
                        "f1_clase": v.get("f1-score"),
                        "support": v.get("support"),
                    }
                )
        if f1m > best_f1:
            best_f1, best_name, best_pipe = f1m, name, pipe

    pd.DataFrame(rows).to_csv(OUT_DIR / "resultados_clasificacion_estrategia.csv", index=False)

    if best_pipe is None:
        return

    pred = best_pipe.predict(X_te)
    labels = sorted(y.unique())
    cm = confusion_matrix(y_te, pred, labels=labels)
    cm_n = cm / cm.sum(axis=1, keepdims=True).clip(min=1e-9)
    fig, ax = plt.subplots(figsize=(11, 9))
    sns.heatmap(cm_n, annot=True, fmt=".2f", cmap="Blues", xticklabels=labels, yticklabels=labels, ax=ax)
    ax.set_title(f"Matriz de confusión normalizada — estrategia (mejor: {best_name})", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "cm_estrategia_multiclase.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    # Top palabras por clase: siempre desde LogReg reentrenada sobre el mismo split.
    # Aunque RF sea el mejor clasificador, la lectura teórica de "huella léxica"
    # exige coeficientes interpretables por clase.
    logreg_pipe = Pipeline(
        [
            ("prep", prep),
            ("model", logistic_regression(max_iter=3000, class_weight="balanced", solver="lbfgs")),
        ]
    )
    logreg_pipe.fit(X_tr, y_tr)
    m = logreg_pipe.named_steps["model"]
    prep_f = logreg_pipe.named_steps["prep"]
    feat = prep_f.get_feature_names_out()
    coef = m.coef_
    classes = m.classes_
    tw_rows = []
    for i, cl in enumerate(classes):
        text_mask = np.array([str(f).startswith("text__") for f in feat])
        text_idx = np.where(text_mask)[0]
        if len(text_idx) == 0:
            continue
        w_text = coef[i][text_idx]
        feat_text = np.array([str(feat[j]).replace("text__", "") for j in text_idx])
        top_local = np.argsort(w_text)[-15:][::-1]
        for rank, j in enumerate(top_local, 1):
            tw_rows.append(
                {
                    "estrategia": cl,
                    "rank": rank,
                    "term": feat_text[j],
                    "coef": float(w_text[j]),
                }
            )
    pd.DataFrame(tw_rows).to_csv(OUT_DIR / "top_words_por_estrategia.csv", index=False)

    # Barplot facet por estrategia (coef top si LogReg)
    tw = pd.read_csv(OUT_DIR / "top_words_por_estrategia.csv")
    if "estrategia" in tw.columns and "term" in tw.columns and not tw.empty:
        n_e = tw["estrategia"].nunique()
        fig, axes = plt.subplots(n_e, 1, figsize=(11, max(7, 2.4 * n_e)), squeeze=False)
        for ax, (est, sub) in zip(axes.flatten(), tw.groupby("estrategia")):
            sub = sub.head(15).sort_values("coef")
            ax.barh(sub["term"], sub["coef"], color="#2980B9")
            ax.set_title(est, fontweight="bold")
            ax.set_xlabel("Coeficiente LogReg")
        fig.suptitle(
            "Top términos predictivos por estrategia discursiva (LogReg interpretable)",
            fontweight="bold",
            y=1.01,
        )
        fig.tight_layout()
        fig.savefig(OUT_DIR / "top_words_por_estrategia.png", dpi=DPI, bbox_inches="tight")
        plt.close(fig)


# ##############################################################################
# #-- ANÁLISIS 3 — R²: TEXTO (TF-IDF) vs LLM vs COMBINADO
# ##############################################################################
# ## Modelo: RandomForest regresión · CV 5-fold
# ##############################################################################


def analisis3_comparacion_r2_configs(df: pd.DataFrame) -> None:
    print("\n# [A3] Comparación R² TF-IDF vs LLM vs combinado (RF)...")
    d = df[df["polarizacion_consenso"].notna() & (df["texto"].str.len() > 5)].copy()
    d = ensure_columns(d, CAT_COLS)
    y = d["polarizacion_consenso"].astype(float)

    cat_llm = ["marco_final", "emocion_final", "estrategia_final", "frontera_final", "candidato", "fase", "tipo_hilo"]
    d = ensure_columns(d, cat_llm)

    cv = KFold(5, shuffle=True, random_state=RANDOM_STATE)
    rf = RandomForestRegressor(n_estimators=200, random_state=RANDOM_STATE, n_jobs=-1)

    def eval_pipe(pipe, X):
        sc = cross_validate(
            pipe,
            X,
            y,
            cv=cv,
            scoring={"mae": "neg_mean_absolute_error", "r2": "r2"},
            n_jobs=-1,
        )
        mae_k = "test_mae" if "test_mae" in sc else "test_neg_mean_absolute_error"
        mae = -np.asarray(sc[mae_k]).mean()
        mae_sd = np.asarray(sc[mae_k]).std()
        r2m = np.asarray(sc["test_r2"]).mean()
        r2sd = np.asarray(sc["test_r2"]).std()
        return mae, mae_sd, r2m, r2sd

    # Config A: solo texto
    Xa = d[[TEXT_COL]]
    pipe_a = Pipeline(
        [
            (
                "prep",
                ColumnTransformer(
                    [
                        (
                            "text",
                            TfidfVectorizer(
                                min_df=3,
                                max_df=0.95,
                                sublinear_tf=True,
                                max_features=20000,
                                stop_words=list(SPANISH_STOPWORDS),
                            ),
                            TEXT_COL,
                        )
                    ]
                ),
            ),
            ("model", rf),
        ]
    )
    # Config B: solo LLM + num
    Xb = d[cat_llm + NUM_COLS]
    prep_b = ColumnTransformer(
        [
            ("cat", _one_hot_encoder(), cat_llm),
            (
                "num",
                Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler(with_mean=False))]),
                NUM_COLS,
            ),
        ]
    )
    pipe_b = Pipeline([("prep", prep_b), ("model", rf)])
    # Config C: completo
    Xc = d[[TEXT_COL] + CAT_COLS + NUM_COLS]
    pipe_c = Pipeline([("prep", make_preprocessor(CAT_COLS, NUM_COLS, TEXT_COL)), ("model", rf)])

    rows = []
    for label, pipe, X in [("A_TF-IDF", pipe_a, Xa), ("B_LLM", pipe_b, Xb), ("C_combinado", pipe_c, Xc)]:
        mae, mae_sd, r2m, r2sd = eval_pipe(pipe, X)
        rows.append(
            {
                "config": label,
                "MAE_mean": mae,
                "MAE_sd": mae_sd,
                "R2_mean": r2m,
                "R2_sd": r2sd,
            }
        )
        print(f"  {label}: MAE={mae:.4f}±{mae_sd:.4f}, R²={r2m:.4f}±{r2sd:.4f}")

    comp = pd.DataFrame(rows)
    comp.to_csv(OUT_DIR / "comparacion_configuraciones_features.csv", index=False)

    r2_text = float(comp.loc[comp["config"] == "A_TF-IDF", "R2_mean"].iloc[0])
    r2_full = float(comp.loc[comp["config"] == "C_combinado", "R2_mean"].iloc[0])
    delta = r2_full - r2_text
    print(f"  Valor añadido LLM (delta R² combinado - solo texto): {delta:.4f}")

    fig, ax = plt.subplots(figsize=FIG_MIN)
    colors = {"A_TF-IDF": "#2980B9", "B_LLM": "#27AE60", "C_combinado": "#C0392B"}
    x = np.arange(len(comp))
    ax.bar(x, comp["R2_mean"], yerr=comp["R2_sd"], capsize=4, color=[colors[c] for c in comp["config"]])
    ax.set_xticks(x)
    ax.set_xticklabels(["Solo TF-IDF", "Solo LLM + num", "Combinado"])
    ax.set_ylabel("R² (CV 5-fold)")
    ax.set_title("Comparación R² por configuración de features (RandomForest)", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "comparacion_r2_texto_llm_combinado.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)


# ##############################################################################
# #-- ANÁLISIS 4 — CALIBRACIÓN DE PROBABILIDADES (pol. alta)
# ##############################################################################
# ## Modelos: RF · GBM · LogReg + CalibratedClassifierCV isotónico
# ##############################################################################


def analisis4_calibracion(df: pd.DataFrame) -> None:
    print("\n# [A4] Calibración de probabilidades (pol_alta)...")
    d = df[df["polarizacion_consenso"].notna()].copy()
    d["pol_alta"] = (d["polarizacion_consenso"] >= 0.6).astype(int)
    cat_f = ["marco_final", "emocion_final", "estrategia_final", "frontera_final", "candidato", "fase", "tipo_hilo"]
    num_f = ["comment_score", "n_chars", "n_words"]
    d = ensure_columns(d, cat_f + num_f)
    for c in cat_f:
        d[c] = d[c].astype(str)
    X = d[cat_f + num_f]
    y = d["pol_alta"].values
    X_tr, X_te, y_tr, y_te = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=safe_stratify(pd.Series(y))
    )

    prep = ColumnTransformer(
        [
            ("cat", _one_hot_encoder(), cat_f),
            (
                "num",
                Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler())]),
                num_f,
            ),
        ]
    )

    def build(name: str):
        if name == "RF":
            return RandomForestClassifier(
                n_estimators=300,
                random_state=RANDOM_STATE,
                class_weight="balanced_subsample",
                n_jobs=-1,
            )
        if name == "GBM":
            return GradientBoostingClassifier(n_estimators=200, random_state=RANDOM_STATE)
        return logistic_regression(max_iter=3000, class_weight="balanced", solver="lbfgs")

    metrics_rows = []
    fig, ax = plt.subplots(figsize=FIG_MIN)
    for short, label in [("RF", "RandomForest"), ("GBM", "GBM"), ("LogReg", "LogReg")]:
        base = Pipeline([("prep", prep), ("model", build(short))])
        base.fit(X_tr, y_tr)
        p0 = base.predict_proba(X_te)[:, 1]
        b0 = brier_score_loss(y_te, p0)
        ll0 = log_loss(y_te, np.vstack([1 - p0, p0]).T)

        cal = CalibratedClassifierCV(base, method="isotonic", cv=5)
        cal.fit(X_tr, y_tr)
        p1 = cal.predict_proba(X_te)[:, 1]
        b1 = brier_score_loss(y_te, p1)
        ll1 = log_loss(y_te, np.vstack([1 - p1, p1]).T)

        metrics_rows.append(
            {
                "modelo": label,
                "brier_antes": b0,
                "brier_despues": b1,
                "logloss_antes": ll0,
                "logloss_despues": ll1,
            }
        )

        if short in {"RF", "GBM"}:
            frac_pred, frac_obs = calibration_curve(y_te, p0, n_bins=10)
            ax.plot(frac_pred, frac_obs, "s--", label=f"{label} sin calibrar")
            frac_pred2, frac_obs2 = calibration_curve(y_te, p1, n_bins=10)
            ax.plot(frac_pred2, frac_obs2, "o-", label=f"{label} calibrado")

    ax.plot([0, 1], [0, 1], "k:", label="Perfecta")
    ax.set_xlabel("Prob. predicha media")
    ax.set_ylabel("Fracción positivos observados")
    ax.set_title("Reliability diagram — polarización alta (calibración isotónica)", fontweight="bold")
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "reliability_diagram_calibracion.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    pd.DataFrame(metrics_rows).to_csv(OUT_DIR / "metricas_calibracion.csv", index=False)


# ##############################################################################
# #-- ANÁLISIS 5 — ERRORES SISTEMÁTICOS (RF pol_alta)
# ##############################################################################
# ## Modelo: RandomForest clasificación
# ##############################################################################


def analisis5_errores_sistematicos(df: pd.DataFrame) -> None:
    print("\n# [A5] Análisis de errores — RF polarización alta...")
    d = df[df["polarizacion_consenso"].notna()].copy()
    d["comment_score"] = pd.to_numeric(d["comment_score"], errors="coerce")
    d["pol_alta"] = (d["polarizacion_consenso"] >= 0.6).astype(int)
    cat_f = ["marco_final", "emocion_final", "estrategia_final", "frontera_final", "candidato", "fase", "tipo_hilo"]
    num_f = ["comment_score", "n_chars", "n_words"]
    d = ensure_columns(d, cat_f + num_f)
    for c in cat_f:
        d[c] = d[c].astype(str)
    X = d[cat_f + num_f]
    y = d["pol_alta"].values
    X_tr, X_te, y_tr, y_te = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=safe_stratify(pd.Series(y))
    )
    idx_te = X_te.index
    prep = ColumnTransformer(
        [
            ("cat", _one_hot_encoder(), cat_f),
            (
                "num",
                Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler())]),
                num_f,
            ),
        ]
    )
    pipe = Pipeline(
        [
            ("prep", prep),
            (
                "model",
                RandomForestClassifier(
                    n_estimators=300,
                    random_state=RANDOM_STATE,
                    class_weight="balanced_subsample",
                    n_jobs=-1,
                ),
            ),
        ]
    )
    pipe.fit(X_tr, y_tr)
    pred = pipe.predict(X_te)
    te = d.loc[idx_te].copy()
    te["pred"] = pred
    te["y"] = y_te

    fn = te[(te["y"] == 1) & (te["pred"] == 0)]
    fp = te[(te["y"] == 0) & (te["pred"] == 1)]
    tp = te[(te["y"] == 1) & (te["pred"] == 1)]

    def stats_block(name, sub):
        if sub.empty:
            return {"grupo": name, "n": 0, "pol_real_media": np.nan, "n_chars_media": np.nan, "karma_media": np.nan}
        cs = pd.to_numeric(sub["comment_score"], errors="coerce")
        return {
            "grupo": name,
            "n": len(sub),
            "pol_real_media": sub["polarizacion_consenso"].mean(),
            "n_chars_media": sub["texto"].astype(str).str.len().mean() if "texto" in sub else np.nan,
            "karma_media": cs.mean(),
        }

    summ = pd.DataFrame([stats_block("FN", fn), stats_block("FP", fp), stats_block("TP", tp)])
    summ.to_csv(OUT_DIR / "errores_sistematicos_resumen.csv", index=False)

    fig, axes = plt.subplots(2, 3, figsize=(14, 10))
    ax = axes[0, 0]
    ax.bar(summ["grupo"], summ["pol_real_media"], color=["#E74C3C", "#F39C12", "#27AE60"])
    ax.set_title("Polarización real media")
    ax = axes[0, 1]
    for lab, sub, col in [("FN", fn, "#E74C3C"), ("FP", fp, "#F39C12"), ("TP", tp, "#27AE60")]:
        vc = sub["emocion_final"].astype(str).value_counts(normalize=True).reindex(
            d["emocion_final"].astype(str).value_counts().index[:8], fill_value=0
        )
        ax.bar(vc.index, vc.values, alpha=0.35, label=lab)
    ax.set_title("Emociones (mezcla)")
    ax.tick_params(axis="x", rotation=90)
    ax = axes[0, 2]
    for lab, sub in [("FN", fn), ("FP", fp), ("TP", tp)]:
        vc = sub["estrategia_final"].astype(str).value_counts(normalize=True).head(8)
        ax.plot(range(len(vc)), vc.values, marker="o", label=lab)
    ax.set_xticks(range(8))
    ax.set_title("Estrategia (top)")
    ax.legend()
    ax = axes[1, 0]
    ax.bar(["FN", "FP", "TP"], [fn["texto"].astype(str).str.len().mean(), fp["texto"].astype(str).str.len().mean(), tp["texto"].astype(str).str.len().mean()])
    ax.set_title("Longitud texto media")
    ax = axes[1, 1]
    ax.bar(
        ["FN", "FP", "TP"],
        [
            pd.to_numeric(fn["comment_score"], errors="coerce").mean(),
            pd.to_numeric(fp["comment_score"], errors="coerce").mean(),
            pd.to_numeric(tp["comment_score"], errors="coerce").mean(),
        ],
    )
    ax.set_title("Karma medio")
    ax = axes[1, 2]
    for lab, sub in [("FN", fn), ("FP", fp), ("TP", tp)]:
        vc = sub["candidato"].value_counts(normalize=True)
        ax.bar(vc.index.astype(str), vc.values, alpha=0.4, label=lab)
    ax.set_title("Candidato")
    ax.tick_params(axis="x", rotation=45)
    fig.suptitle("Errores sistemáticos vs aciertos (test set)", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "analisis_errores_sistematicos.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    if "texto" in te.columns:
        ex_fn = fn.nlargest(5, "polarizacion_consenso")[["texto", "polarizacion_consenso"]].copy()
        ex_fn["texto"] = ex_fn["texto"].astype(str).str.slice(0, 500)
        ex_fn.to_csv(OUT_DIR / "ejemplos_falsos_negativos.csv", index=False)
        ex_fp = fp.nlargest(5, "polarizacion_consenso")[["texto", "polarizacion_consenso"]].copy()
        ex_fp["texto"] = ex_fp["texto"].astype(str).str.slice(0, 500)
        ex_fp.to_csv(OUT_DIR / "ejemplos_falsos_positivos.csv", index=False)


# ##############################################################################
# #-- ANÁLISIS 6 — CLASIFICACIÓN: FRONTERA POLÍTICA
# ##############################################################################
# ## Modelos: LogReg · RandomForest (3 clases)
# ##############################################################################


def analisis6_frontera(df: pd.DataFrame) -> None:
    print("\n# [A6] Clasificación frontera_final...")
    d = df.copy()
    d["frontera_final"] = d["frontera_final"].astype(str)
    d = d[d["frontera_final"] != "ERROR"]
    d = d[d["frontera_final"].isin(["inter_bloque", "intra_bloque", "ninguna"])]
    d = d[d["texto"].str.len() > 5]
    cat_f = ["candidato", "tipo_hilo", "fase"]
    d = ensure_columns(d, cat_f)
    for c in cat_f:
        d[c] = d[c].astype(str)
    X = d[[TEXT_COL] + cat_f]
    y = d["frontera_final"].astype(str)
    if y.nunique() < 2 or len(d) < 50:
        print("  [WARN] Frontera: datos insuficientes.")
        return
    X_tr, X_te, y_tr, y_te = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=safe_stratify(y)
    )

    prep = ColumnTransformer(
        [
            (
                "text",
                TfidfVectorizer(
                    min_df=3,
                    max_df=0.95,
                    max_features=12000,
                    stop_words=list(SPANISH_STOPWORDS),
                ),
                TEXT_COL,
            ),
            ("cat", _one_hot_encoder(), cat_f),
        ]
    )

    rows = []
    for name, est in [
        ("LogReg", logistic_regression(max_iter=3000, class_weight="balanced", solver="lbfgs")),
        (
            "RandomForest",
            RandomForestClassifier(
                n_estimators=300,
                class_weight="balanced_subsample",
                random_state=RANDOM_STATE,
                n_jobs=-1,
            ),
        ),
    ]:
        pipe = Pipeline([("prep", prep), ("model", est)])
        pipe.fit(X_tr, y_tr)
        pred = pipe.predict(X_te)
        f1m = f1_score(y_te, pred, average="macro")
        acc = accuracy_score(y_te, pred)
        rows.append({"modelo": name, "accuracy": acc, "f1_macro": f1m})
        rep = classification_report(y_te, pred, output_dict=True)
        for k, v in rep.items():
            if isinstance(v, dict) and "f1-score" in v:
                rows.append({"modelo": name, "clase": k, "f1": v["f1-score"]})

    pd.DataFrame(rows).to_csv(OUT_DIR / "resultados_clasificacion_frontera.csv", index=False)

    pipe = Pipeline(
        [
            ("prep", prep),
            (
                "model",
                RandomForestClassifier(
                    n_estimators=300,
                    class_weight="balanced_subsample",
                    random_state=RANDOM_STATE,
                    n_jobs=-1,
                ),
            ),
        ]
    )
    pipe.fit(X_tr, y_tr)
    pred = pipe.predict(X_te)
    labels = sorted(y.unique())
    cm = confusion_matrix(y_te, pred, labels=labels)
    cm_n = cm / cm.sum(axis=1, keepdims=True).clip(min=1e-9)
    fig, ax = plt.subplots(figsize=(8, 7))
    sns.heatmap(cm_n, annot=True, fmt=".2f", xticklabels=labels, yticklabels=labels, cmap="Greens", ax=ax)
    ax.set_title("Frontera política — CM normalizada (RandomForest)", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "cm_frontera_politica.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    f1m = f1_score(y_te, pred, average="macro")
    if f1m > 0.60:
        msg = "Frontera recuperable desde texto (F1-macro>0.60)."
    elif f1m < 0.40:
        msg = "Frontera ambigua; señal débil en texto (F1-macro<0.40)."
    else:
        msg = "Frontera parcialmente recuperable (F1-macro intermedio)."
    print(f"  Interpretación: {msg}")


# ##############################################################################
# #-- ANÁLISIS 7 — STACKING (REGRESIÓN + CLASIFICACIÓN)
# ##############################################################################
# ## Meta-modelos: Ridge · LogisticRegression
# ##############################################################################


def analisis7_stacking(df: pd.DataFrame) -> None:
    print("\n# [A7] Stacking ensemble...")
    d = df[df["polarizacion_consenso"].notna() & (df["texto"].str.len() > 5)].copy()
    d = ensure_columns(d, CAT_COLS)
    X = d[[TEXT_COL] + CAT_COLS + NUM_COLS]
    y = d["polarizacion_consenso"].astype(float)

    base_reg = [
        ("ridge", Pipeline([("prep", make_preprocessor(CAT_COLS, NUM_COLS, TEXT_COL)), ("m", Ridge(alpha=1.0))])),
        (
            "rf",
            Pipeline(
                [
                    ("prep", make_preprocessor(CAT_COLS, NUM_COLS, TEXT_COL)),
                    ("m", RandomForestRegressor(n_estimators=200, random_state=RANDOM_STATE, n_jobs=-1)),
                ]
            ),
        ),
        (
            "gbm",
            Pipeline(
                [
                    ("prep", make_preprocessor(CAT_COLS, NUM_COLS, TEXT_COL)),
                    ("svd", TruncatedSVD(n_components=300, random_state=RANDOM_STATE)),
                    ("m", GradientBoostingRegressor(n_estimators=150, max_depth=5, random_state=RANDOM_STATE)),
                ]
            ),
        ),
    ]
    stack_r = StackingRegressor(estimators=base_reg, final_estimator=Ridge(alpha=0.1), cv=5, n_jobs=-1)
    X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2, random_state=RANDOM_STATE)
    stack_r.fit(X_tr, y_tr)
    r2_stack = r2_score(y_te, stack_r.predict(X_te))
    indiv = {}
    for name, est in base_reg:
        est.fit(X_tr, y_tr)
        indiv[name] = r2_score(y_te, est.predict(X_te))
    best_ind = max(indiv.values())

    d2 = df[df["polarizacion_consenso"].notna()].copy()
    d2["pol_alta"] = (d2["polarizacion_consenso"] >= 0.6).astype(int)
    cat_f = ["marco_final", "emocion_final", "estrategia_final", "frontera_final", "candidato", "fase", "tipo_hilo"]
    num_f = ["comment_score", "n_chars", "n_words"]
    d2 = ensure_columns(d2, cat_f + num_f)
    for c in cat_f:
        d2[c] = d2[c].astype(str)
    X2 = d2[cat_f + num_f]
    y2 = d2["pol_alta"].values
    prep2 = ColumnTransformer(
        [
            ("cat", _one_hot_encoder(), cat_f),
            (
                "num",
                Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler())]),
                num_f,
            ),
        ]
    )
    base_clf = [
        ("lr", Pipeline([("p", prep2), ("m", logistic_regression(max_iter=3000, class_weight="balanced", solver="lbfgs"))])),
        (
            "rf",
            Pipeline(
                [
                    ("p", prep2),
                    (
                        "m",
                        RandomForestClassifier(
                            n_estimators=200,
                            class_weight="balanced_subsample",
                            random_state=RANDOM_STATE,
                            n_jobs=-1,
                        ),
                    ),
                ]
            ),
        ),
        ("gbm", Pipeline([("p", prep2), ("m", GradientBoostingClassifier(n_estimators=150, random_state=RANDOM_STATE))])),
    ]
    stack_c = StackingClassifier(
        estimators=base_clf,
        final_estimator=logistic_regression(max_iter=2000, solver="lbfgs"),
        cv=5,
        n_jobs=-1,
    )
    X2_tr, X2_te, y2_tr, y2_te = train_test_split(
        X2, y2, test_size=0.2, random_state=RANDOM_STATE, stratify=safe_stratify(pd.Series(y2))
    )
    stack_c.fit(X2_tr, y2_tr)
    auc_stack = roc_auc_score(y2_te, stack_c.predict_proba(X2_te)[:, 1])
    indiv_auc = {}
    for name, est in base_clf:
        est.fit(X2_tr, y2_tr)
        indiv_auc[name] = roc_auc_score(y2_te, est.predict_proba(X2_te)[:, 1])
    best_auc = max(indiv_auc.values())

    res = pd.DataFrame(
        [
            {"tarea": "regresión", "modelo": "Stacking", "metrica": "R2", "valor": r2_stack, "mejora_vs_mejor_ind": r2_stack - best_ind},
            {"tarea": "clasificación pol_alta", "modelo": "Stacking", "metrica": "AUC", "valor": auc_stack, "mejora_vs_mejor_ind": auc_stack - best_auc},
        ]
    )
    for k, v in indiv.items():
        res = pd.concat([res, pd.DataFrame([{"tarea": "regresión", "modelo": k, "metrica": "R2", "valor": v, "mejora_vs_mejor_ind": np.nan}])], ignore_index=True)
    for k, v in indiv_auc.items():
        res = pd.concat([res, pd.DataFrame([{"tarea": "clasificación pol_alta", "modelo": k, "metrica": "AUC", "valor": v, "mejora_vs_mejor_ind": np.nan}])], ignore_index=True)
    res.to_csv(OUT_DIR / "resultados_stacking.csv", index=False)

    fig, ax = plt.subplots(figsize=FIG_MIN)
    reg_names = ["ridge", "rf", "gbm", "Stacking"]
    reg_vals = [indiv["ridge"], indiv["rf"], indiv["gbm"], r2_stack]
    ax.bar(reg_names, reg_vals, color=["#95A5A6", "#95A5A6", "#95A5A6", "#C0392B"])
    ax.set_ylabel("R² (holdout)")
    ax.set_title("Stacking vs modelos base — regresión polarización", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "comparacion_stacking_vs_individuales.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)


# ##############################################################################
# #-- ANÁLISIS 8 — OLS: ESTRATEGIA × FASE
# ##############################################################################
# ## Modelo: OLS con interacción · plot marginal
# ##############################################################################


def analisis8_estrategia_fase(df: pd.DataFrame) -> None:
    print("\n# [A8] Interacción estrategia × fase...")
    d = df[df["polarizacion_consenso"].notna()].copy()
    d["comment_score"] = pd.to_numeric(d["comment_score"], errors="coerce").fillna(d["comment_score"].median())
    d["comment_score_c"] = d["comment_score"] - d["comment_score"].mean()
    for col in ["estrategia_final", "fase", "emocion_final", "candidato", "tipo_hilo"]:
        d[col] = d[col].astype(str)
    rs = safe_ref(d["estrategia_final"], "ninguna")
    rf = safe_ref(d["fase"], "posicionamiento")
    re = safe_ref(d["emocion_final"], "ninguna")
    rc = safe_ref(d["candidato"], "matthei")
    rt = safe_ref(d["tipo_hilo"], "solo_izquierda")

    formula = (
        f"polarizacion_consenso ~ C(estrategia_final, Treatment('{rs}')) * C(fase, Treatment('{rf}')) + "
        f"C(emocion_final, Treatment('{re}')) + C(candidato, Treatment('{rc}')) + "
        f"C(tipo_hilo, Treatment('{rt}')) + comment_score_c"
    )
    try:
        m = smf.ols(formula, data=d).fit()
    except Exception as e:
        print(f"  [WARN] OLS A8: {e}")
        return

    inter = []
    for nm in m.params.index:
        if ":" in str(nm) and "estrategia" in str(nm) and "fase" in str(nm):
            if float(m.pvalues[nm]) < 0.05:
                inter.append(str(nm))
    pd.DataFrame({"termino_interaccion_sig": inter}).to_csv(OUT_DIR / "interacciones_estrategia_fase.csv", index=False)

    g = (
        d.groupby(["estrategia_final", "fase"], as_index=False)["polarizacion_consenso"]
        .agg(["mean", "std", "count"])
        .reset_index()
    )
    g["se"] = g["std"] / np.sqrt(g["count"].clip(lower=1))
    g["ci"] = 1.96 * g["se"]

    fig, ax = plt.subplots(figsize=(max(11, 0.25 * g["estrategia_final"].nunique()), 7))
    estrategias = sorted(d["estrategia_final"].unique())
    x = np.arange(len(estrategias))
    w = 0.35
    for i, fase in enumerate(sorted(d["fase"].unique())):
        sub = g[g["fase"] == fase].set_index("estrategia_final").reindex(estrategias).reset_index()
        ax.bar(
            x + (i - 0.5) * w,
            sub["mean"],
            width=w,
            yerr=sub["ci"],
            capsize=3,
            label=str(fase),
        )
    ax.set_xticks(x)
    ax.set_xticklabels(estrategias, rotation=45, ha="right")
    ax.set_ylabel("Polarización media ± IC 95%")
    ax.set_title("Interacción estrategia × fase (medias descriptivas)", fontweight="bold")
    ax.legend(title="Fase")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "interaction_plot_estrategia_fase.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)


# ##############################################################################
# #-- ANÁLISIS 9 — AUTORES RECURRENTES
# ##############################################################################
# ## Estadísticos: Kruskal-Wallis · perfiles por actividad
# ##############################################################################


def analisis9_autores(api_df: pd.DataFrame) -> None:
    print("\n# [A9] Autores recurrentes vs polarización...")
    if api_df is None or "comment_author" not in api_df.columns:
        print("  [WARN] Sin comment_author.")
        return
    d = api_df[api_df["polarizacion_consenso"].notna()].copy()
    d["comment_author"] = d["comment_author"].astype(str)
    sent_cols = [c for c in d.columns if c.startswith("sent_final_")]
    if sent_cols:

        def row_neg(row):
            return int(any(str(row[c]).upper() == "NEGATIVO" for c in sent_cols if c in row.index))

        d["_neg"] = d.apply(row_neg, axis=1)
    else:
        d["_neg"] = 0

    g = d.groupby("comment_author", as_index=False).agg(
        n_comentarios=("post_id", "count"),
        polarizacion_media=("polarizacion_consenso", "mean"),
        pct_negativo=("_neg", "mean"),
    )
    g["author_hash"] = g["comment_author"].map(hash_author)
    emo_mode = d.groupby("comment_author")["emocion_final"].agg(lambda s: s.mode().iloc[0] if len(s.mode()) else "")
    cand_col = "candidato" if "candidato" in d.columns else ("candidatos" if "candidatos" in d.columns else None)
    if cand_col:
        cand_mode = d.groupby("comment_author")[cand_col].agg(
            lambda s: s.mode().iloc[0] if len(s.mode()) else ""
        )
    else:
        cand_mode = None
    g = g.merge(emo_mode.rename("emocion_dominante"), left_on="comment_author", right_index=True, how="left")
    if cand_mode is not None:
        g = g.merge(cand_mode.rename("candidato_mas_frecuente"), left_on="comment_author", right_index=True, how="left")
    else:
        g["candidato_mas_frecuente"] = ""

    # Candidato "principal" por conteo de menciones en comentarios (evita gris por moda de cadenas "kast, jara")
    _known_cand = frozenset({"kast", "jara", "kaiser", "matthei"})

    def _candidato_principal_por_autor(s: pd.Series) -> str:
        from collections import Counter

        c = Counter()
        for val in s:
            if pd.isna(val):
                continue
            for part in str(val).lower().split(","):
                p = part.strip()
                if p in _known_cand:
                    c[p] += 1
        if not c:
            return "otro"
        mx = max(c.values())
        tops = [k for k, v in c.items() if v == mx]
        return "empate" if len(tops) > 1 else tops[0]

    if "candidatos" in d.columns:
        cand_primary = d.groupby("comment_author")["candidatos"].apply(_candidato_principal_por_autor)
        g = g.merge(cand_primary.rename("candidato_principal"), left_on="comment_author", right_index=True, how="left")
        g["candidato_principal"] = g["candidato_principal"].fillna("otro")
    else:
        g["candidato_principal"] = "otro"

    def tipo(n):
        if n == 1:
            return "esporadico"
        if 2 <= n <= 5:
            return "recurrente"
        if 6 <= n <= 20:
            return "activo"
        return "hiperactivo"

    g["tipo_autor"] = g["n_comentarios"].map(tipo)

    groups = [g.loc[g["tipo_autor"] == t, "polarizacion_media"].values for t in ["esporadico", "recurrente", "activo", "hiperactivo"] if (g["tipo_autor"] == t).any()]
    if len(groups) >= 2:
        h_stat, p_kw = stats.kruskal(*groups)
        print(f"  Kruskal-Wallis polarización media por tipo autor: H={h_stat:.3f}, p={p_kw:.4f}")

    g.drop(columns=["comment_author"]).to_csv(OUT_DIR / "perfil_autores_por_actividad.csv", index=False)

    top = g.nlargest(20, "n_comentarios")[
        ["author_hash", "n_comentarios", "polarizacion_media", "pct_negativo", "tipo_autor"]
    ]
    top.to_csv(OUT_DIR / "top_autores_activos.csv", index=False)

    fig, ax = plt.subplots(figsize=FIG_MIN)
    order = ["esporadico", "recurrente", "activo", "hiperactivo"]
    sub = [g.loc[g["tipo_autor"] == t, "polarizacion_media"].dropna() for t in order if (g["tipo_autor"] == t).any()]
    lab = [t for t in order if (g["tipo_autor"] == t).any()]
    ax.violinplot(sub, showmeans=True)
    ax.set_xticks(np.arange(1, len(lab) + 1))
    ax.set_xticklabels(lab)
    ax.set_ylabel("Polarización media por autor")
    ax.set_title("Distribución de polarización media según actividad del autor", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "polarizacion_por_tipo_autor.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    gg = g[g["n_comentarios"] >= 3].copy()
    if len(gg) > 5 and "candidato_principal" in gg.columns:
        fig, ax = plt.subplots(figsize=FIG_MIN)
        rng = np.random.default_rng(RANDOM_STATE)
        for cand in CAND_LEGEND_ORDER:
            sub = gg.loc[gg["candidato_principal"] == cand]
            if sub.empty:
                continue
            # Ligero jitter horizontal (solo visual) para separar solapamientos en n entero
            x_plot = sub["n_comentarios"].to_numpy(dtype=float) + rng.uniform(-0.42, 0.42, size=len(sub))
            ax.scatter(
                x_plot,
                sub["polarizacion_media"],
                label=cand,
                alpha=0.52,
                s=36,
                color=COLORES_CAND.get(cand, "#7F8C8D"),
                edgecolors="white",
                linewidths=0.45,
                rasterized=True,
                zorder=2,
            )
        try:
            from statsmodels.nonparametric.smoothers_lowess import lowess

            z = lowess(gg["polarizacion_media"], gg["n_comentarios"], frac=0.3)
            ax.plot(z[:, 0], z[:, 1], "k-", linewidth=2, label="LOESS", zorder=10)
        except Exception:
            pass
        ax.set_xlabel("Número de comentarios (autor)")
        ax.set_ylabel("Polarización media")
        ax.set_title("Actividad vs polarización (autores con n≥3)", fontweight="bold")
        ax.margins(x=0.02, y=0.03)
        ax.text(
            0.02,
            0.02,
            "Color: candidato con más menciones en los comentarios del autor\n"
            "(violeta = empate; gris = sin candidato reconocible). "
            "Puntos con leve desplazamiento horizontal solo para ver solapamientos; LOESS usa n real.",
            transform=ax.transAxes,
            fontsize=8,
            verticalalignment="bottom",
            linespacing=1.15,
        )
        ax.legend(loc="upper right", fontsize=8, framealpha=0.92)
        fig.tight_layout()
        out_scatter = OUT_DIR / "scatter_actividad_polarizacion_autores.png"
        fig.savefig(out_scatter, dpi=DPI, bbox_inches="tight")
        plt.close(fig)
        if FIG_THESIS.parent.is_dir():
            FIG_THESIS.mkdir(parents=True, exist_ok=True)
            shutil.copy2(out_scatter, FIG_THESIS / out_scatter.name)


# ##############################################################################
# #-- TABLA RESUMEN AMPLIADA (scripts 09 + 10)
# ##############################################################################


def build_tabla_completa(long_df: pd.DataFrame, api_df: pd.DataFrame) -> None:
    rows = []

    def add_row(script: str, analisis: str, modelo: str, tarea: str, metrica: str, valor, n_obs, interpretacion: str) -> None:
        rows.append(
            {
                "script": script,
                "analisis": analisis,
                "modelo": modelo,
                "tarea": tarea,
                "metrica_principal": metrica,
                "valor": valor,
                "n_obs": n_obs,
                "interpretacion_teorica": interpretacion,
            }
        )

    def read_csv_safe(name: str) -> pd.DataFrame:
        path = OUT_DIR / name
        return pd.read_csv(path) if path.is_file() else pd.DataFrame()

    n_long = int(len(long_df))
    n_api = int(len(api_df)) if api_df is not None else np.nan

    # Script 09
    ols = read_csv_safe("tabla_ols_polarizacion.csv")
    if not ols.empty:
        add_row(
            "09",
            "ML1 OLS polarización",
            "OLS",
            "regresión",
            "R2_ajustado",
            f"{float(ols['r2_adj'].dropna().iloc[0]):.4f}",
            int(ols["n_obs"].dropna().iloc[0]),
            "Modelo interpretable base para efectos discursivos sobre polarización.",
        )

    auc = read_csv_safe("auc_comparacion_modelos.csv")
    for _, r in auc.iterrows():
        add_row(
            "09",
            "ML3 ROC polarización alta",
            str(r["modelo"]),
            "clasificación",
            "AUC",
            f"{float(r['AUC']):.4f}",
            n_long,
            "Comparación de capacidad discriminativa para polarización alta.",
        )

    cv = read_csv_safe("validacion_cruzada_resumen.csv")
    for _, r in cv.iterrows():
        add_row(
            "09",
            "ML7 validación cruzada",
            str(r["modelo"]),
            str(r["tarea"]),
            str(r["metrica"]),
            f"{float(r['mean']):.4f} ± {float(r['std']):.4f}",
            n_long,
            "Estabilidad fuera de muestra del rendimiento del modelo.",
        )

    per = read_csv_safe("perfiles_discursivos_kmeans.csv")
    if not per.empty:
        add_row(
            "09",
            "ML5 clustering perfiles",
            "KMeans",
            "clustering",
            "n_clusters",
            str(len(per)),
            n_long,
            "Perfiles discursivos recurrentes de hostilidad y conflicto.",
        )

    multi = read_csv_safe("resultados_multinomial_emocion.csv")
    if not multi.empty and "f1-score" in multi.columns and "macro avg" in multi.iloc[:, 0].astype(str).values:
        macro = multi[multi.iloc[:, 0].astype(str) == "macro avg"]
        if not macro.empty:
            add_row(
                "09",
                "ML6 emoción multinomial",
                "LogisticRegression",
                "multiclase",
                "F1_macro",
                f"{float(macro['f1-score'].iloc[0]):.4f}",
                n_long,
                "Predicción multiclase de emoción desde marco, estrategia y candidato.",
            )

    # Script 10
    inter = read_csv_safe("interacciones_candidato_emocion.csv")
    if not inter.empty:
        add_row(
            "10",
            "A1 moderador candidato×emoción",
            "OLS",
            "regresión",
            "min_p_interacción",
            f"{float(inter['p_value'].min()):.4f}",
            n_long,
            "Evalúa si una misma emoción cambia de intensidad según el target político.",
        )

    est = read_csv_safe("resultados_clasificacion_estrategia.csv")
    if not est.empty:
        est_main = est[est["clase"].fillna("") == ""]
        for _, r in est_main.iterrows():
            add_row(
                "10",
                "A2 estrategia discursiva",
                str(r["modelo"]),
                "multiclase",
                "F1_macro",
                f"{float(r['f1_macro']):.4f}",
                int(len(long_df[~long_df["estrategia_final"].astype(str).isin(['ninguna', 'ERROR', 'nan'])])),
                "Huella léxica de estrategias adversariales.",
            )

    cfg = read_csv_safe("comparacion_configuraciones_features.csv")
    for _, r in cfg.iterrows():
        add_row(
            "10",
            "A3 texto vs LLM vs combinado",
            "RandomForest",
            "regresión",
            f"R2_{r['config']}",
            f"{float(r['R2_mean']):.4f} ± {float(r['R2_sd']):.4f}",
            n_long,
            "Compara el valor predictivo del texto, variables LLM y su combinación.",
        )

    cal = read_csv_safe("metricas_calibracion.csv")
    for _, r in cal.iterrows():
        add_row(
            "10",
            "A4 calibración",
            str(r["modelo"]),
            "clasificación",
            "Brier_despues",
            f"{float(r['brier_despues']):.4f}",
            n_long,
            "Confiabilidad probabilística del clasificador de polarización alta.",
        )

    front = read_csv_safe("resultados_clasificacion_frontera.csv")
    if not front.empty:
        front_main = front[front["clase"].fillna("") == ""]
        for _, r in front_main.iterrows():
            add_row(
                "10",
                "A6 frontera política",
                str(r["modelo"]),
                "multiclase",
                "F1_macro",
                f"{float(r['f1_macro']):.4f}",
                int(len(long_df[long_df["frontera_final"].astype(str) != "ERROR"])),
                "Capacidad de recuperar frontera política desde el texto.",
            )

    stack = read_csv_safe("resultados_stacking.csv")
    for _, r in stack.iterrows():
        add_row(
            "10",
            "A7 stacking",
            str(r["modelo"]),
            str(r["tarea"]),
            str(r["metrica"]),
            f"{float(r['valor']):.4f}" if pd.notna(r["valor"]) else "",
            n_long,
            "Ceiling performance al combinar modelos base.",
        )

    inter2 = read_csv_safe("interacciones_estrategia_fase.csv")
    if not inter2.empty:
        add_row(
            "10",
            "A8 estrategia×fase",
            "OLS",
            "regresión",
            "n_interacciones_sig",
            str(len(inter2)),
            n_long,
            "Cambio de efecto estratégico entre fases electorales.",
        )

    autores = read_csv_safe("perfil_autores_por_actividad.csv")
    if not autores.empty:
        add_row(
            "10",
            "A9 autores recurrentes",
            "Kruskal-Wallis + descriptivos",
            "comparación grupos",
            "n_autores",
            str(len(autores)),
            n_api,
            "Concentración o difusión de la hostilidad según actividad de usuarios.",
        )

    pd.DataFrame(rows).to_csv(OUT_DIR / "tabla_ml_completa_tesis.csv", index=False)


# ##############################################################################
# ## MAIN
# ##############################################################################


def print_checklist(expected: list[str]) -> None:
    print("\n--- Checklist salidas (10_ml_supervisado_avanzado) ---")
    for name in sorted(expected):
        p = OUT_DIR / name
        print(f"  {'✅' if p.is_file() else '⬜'} {name}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"BASE_DIR={BASE_DIR}\nOUT_DIR={OUT_DIR}")

    long_df, api_df = load_datasets()

    analisis1_moderador_candidato_emocion(long_df)
    analisis2_estrategia_multiclase(long_df)
    analisis3_comparacion_r2_configs(long_df)
    analisis4_calibracion(long_df)
    analisis5_errores_sistematicos(long_df)
    analisis6_frontera(long_df)
    analisis7_stacking(long_df)
    analisis8_estrategia_fase(long_df)
    analisis9_autores(api_df)

    build_tabla_completa(long_df, api_df)

    expected = [
        "interacciones_candidato_emocion.csv",
        "heatmap_interaccion_candidato_emocion.png",
        "interaction_plot_emocion_candidato.png",
        "resultados_clasificacion_estrategia.csv",
        "cm_estrategia_multiclase.png",
        "top_words_por_estrategia.csv",
        "top_words_por_estrategia.png",
        "comparacion_configuraciones_features.csv",
        "comparacion_r2_texto_llm_combinado.png",
        "metricas_calibracion.csv",
        "reliability_diagram_calibracion.png",
        "errores_sistematicos_resumen.csv",
        "analisis_errores_sistematicos.png",
        "ejemplos_falsos_negativos.csv",
        "ejemplos_falsos_positivos.csv",
        "resultados_clasificacion_frontera.csv",
        "cm_frontera_politica.png",
        "resultados_stacking.csv",
        "comparacion_stacking_vs_individuales.png",
        "interacciones_estrategia_fase.csv",
        "interaction_plot_estrategia_fase.png",
        "perfil_autores_por_actividad.csv",
        "top_autores_activos.csv",
        "polarizacion_por_tipo_autor.png",
        "scatter_actividad_polarizacion_autores.png",
        "tabla_ml_completa_tesis.csv",
    ]
    print_checklist(expected)


if __name__ == "__main__":
    main()
