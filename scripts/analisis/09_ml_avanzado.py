"""
09_ml_avanzado.py

Análisis ML avanzado para tesis (journal-style): OLS interpretable, importancia por
permutación, ROC comparativo, SHAP, clustering de perfiles, multinomial emociones y
validación cruzada. Sin BERT ni embeddings.

Inspirado en scripts/analisis/07_pipeline_completo.py (mismas categorías y preproceso).
"""

from __future__ import annotations

import importlib.util
import math
import os
import shutil
import subprocess
import sys
import warnings
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
import statsmodels.formula.api as smf
from matplotlib import image as mpl_image
from scipy import stats
from sklearn.cluster import KMeans
from sklearn.compose import ColumnTransformer
from sklearn.decomposition import TruncatedSVD
from sklearn.ensemble import (
    GradientBoostingClassifier,
    GradientBoostingRegressor,
    RandomForestClassifier,
    RandomForestRegressor,
)
from sklearn.impute import SimpleImputer
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.metrics import (
    auc,
    classification_report,
    confusion_matrix,
    r2_score,
    roc_curve,
    silhouette_score,
)
from sklearn.model_selection import (
    KFold,
    StratifiedKFold,
    cross_validate,
    train_test_split,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

warnings.filterwarnings("ignore")

RANDOM_STATE = 42
DPI = 300
FIG_MIN = (10, 7)

COLORES_CAND = {
    "kast": "#C0392B",
    "kaiser": "#E67E22",
    "matthei": "#2980B9",
    "jara": "#27AE60",
}

# --- Reutilizar preproceso del pipeline principal ---------------------------------
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
ensure_columns = P07.ensure_columns
add_text_features = P07.add_text_features
safe_stratify = P07.safe_stratify


def _one_hot_encoder():
    try:
        return OneHotEncoder(handle_unknown="ignore", sparse_output=False)
    except TypeError:
        return OneHotEncoder(handle_unknown="ignore", sparse=False)


def resolve_base_dir() -> Path:
    env = os.environ.get("THESIS_BASE")
    if env:
        p = Path(env).expanduser()
        if p.is_dir():
            return p
    here = Path(__file__).resolve().parent.parent.parent
    candidates = [
        here,
        Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_maci"),
        Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final"),
    ]
    for c in candidates:
        if (c / "outputs_ml" / "dataset_largo_enriquecido.csv").is_file():
            return c
    return here


BASE_DIR = resolve_base_dir()
OUT_DIR = BASE_DIR / "outputs_ml"
FIG_THESIS = BASE_DIR / "documents" / "tesis_book" / "fig_thesis"
DATA_LONG = OUT_DIR / "dataset_largo_enriquecido.csv"
DATA_BASE = BASE_DIR / "data" / "processed" / "analisis_API.csv"

plt.style.use("seaborn-v0_8-whitegrid")


def ensure_shap():
    try:
        import shap  # noqa: F401
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "shap", "-q"])
    import shap

    return shap


def polar_level(x: float) -> str:
    if pd.isna(x):
        return np.nan
    if x < 0.3:
        return "baja"
    if x <= 0.6:
        return "media"
    return "alta"


def load_dataset() -> pd.DataFrame:
    if not DATA_LONG.is_file():
        raise FileNotFoundError(
            f"No se encontró {DATA_LONG}. Ejecuta 07_pipeline_completo.py o copia el CSV."
        )
    df = pd.read_csv(DATA_LONG, on_bad_lines="skip", encoding="utf-8")
    df["polarizacion_consenso"] = pd.to_numeric(df["polarizacion_consenso"], errors="coerce")
    df["comment_score"] = pd.to_numeric(df.get("comment_score"), errors="coerce")
    if "texto" not in df.columns and "comentario_texto" in df.columns:
        df["texto"] = df["comentario_texto"].fillna("").astype(str)
    df = add_text_features(df, "texto")
    if "pol_grupo" not in df.columns:
        df["pol_grupo"] = df["polarizacion_consenso"].apply(polar_level)
    df = ensure_columns(df, CAT_COLS)
    return df


def safe_ref(series: pd.Series, ref: str, fallback: str = "otro") -> str:
    s = series.astype(str)
    if ref in set(s.unique()):
        return ref
    m = s.mode()
    return str(m.iloc[0]) if len(m) else fallback


# =============================================================================
# ML1 — OLS
# =============================================================================
def run_ml1_ols(df: pd.DataFrame) -> pd.DataFrame | None:
    print("\n[ML1] OLS polarización (statsmodels)...")
    d = df[df["polarizacion_consenso"].notna()].copy()
    d["comment_score"] = pd.to_numeric(d["comment_score"], errors="coerce").fillna(
        d["comment_score"].median()
    )
    d["comment_score_c"] = d["comment_score"] - d["comment_score"].mean()

    for col in [
        "marco_final",
        "emocion_final",
        "estrategia_final",
        "frontera_final",
        "candidato",
        "fase",
        "tipo_hilo",
    ]:
        d[col] = d[col].astype(str).replace({"nan": "desconocido", "None": "desconocido"})

    ref_marco = safe_ref(d["marco_final"], "otro")
    ref_emo = safe_ref(d["emocion_final"], "ninguna")
    ref_est = safe_ref(d["estrategia_final"], "ninguna")
    ref_fron = safe_ref(d["frontera_final"], "ninguna")
    ref_cand = safe_ref(d["candidato"], "matthei")
    ref_fase = safe_ref(d["fase"], "posicionamiento")
    ref_tipo = safe_ref(d["tipo_hilo"], "solo_izquierda")

    formula = (
        "polarizacion_consenso ~ "
        f"C(marco_final, Treatment('{ref_marco}')) + "
        f"C(emocion_final, Treatment('{ref_emo}')) + "
        f"C(estrategia_final, Treatment('{ref_est}')) + "
        f"C(frontera_final, Treatment('{ref_fron}')) + "
        f"C(candidato, Treatment('{ref_cand}')) + "
        f"C(fase, Treatment('{ref_fase}')) + "
        f"C(tipo_hilo, Treatment('{ref_tipo}')) + "
        "comment_score_c"
    )

    try:
        res = smf.ols(formula, data=d).fit()
    except Exception as e:
        print(f"  OLS falló: {e}")
        return None

    ci = res.conf_int(alpha=0.05)
    sig_mask = res.pvalues.values < 0.05
    out = pd.DataFrame(
        {
            "coeficiente": res.params.index.astype(str),
            "coef": res.params.values,
            "ci_low": ci[0].values,
            "ci_high": ci[1].values,
            "p_value": res.pvalues.values,
            # 0/1 para que read.csv en R no confunda con texto "True"/"False"
            "signif_05": sig_mask.astype(int),
        }
    )
    out["marca"] = np.where(sig_mask, "*", "")
    out["n_obs"] = int(res.nobs)
    out["r2_adj"] = res.rsquared_adj
    out["f_stat"] = float(res.fvalue) if res.fvalue is not None else np.nan
    out.to_csv(OUT_DIR / "tabla_ols_polarizacion.csv", index=False)

    plot_df = out[out["coeficiente"] != "Intercept"].copy()
    sub = plot_df[plot_df["p_value"] < 0.05].copy()
    if sub.empty:
        sub = plot_df.copy()
    sub = sub.assign(coef=sub["coef"].astype(float))
    sub = sub.sort_values("coef", key=abs, ascending=False)

    fig, ax = plt.subplots(figsize=(10, max(12, 0.35 * len(sub))))
    y = np.arange(len(sub))
    colors = np.where(sub["coef"].values >= 0, "#C0392B", "#2980B9")
    ax.hlines(y, sub["ci_low"].astype(float), sub["ci_high"].astype(float), color="#7F8C8D", linewidth=1.5)
    ax.scatter(sub["coef"], y, c=colors, s=55, zorder=3, edgecolors="white")
    ax.axvline(0, color="black", linewidth=0.8)
    ax.set_yticks(y)
    ax.set_yticklabels(sub["coeficiente"], fontsize=8)
    ax.set_xlabel("Coeficiente e IC 95%")
    ax.set_title("OLS: coeficientes significativos (p<0.05) — polarización consensuada", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "coefplot_ols_polarizacion.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    print(f"  R² adj={res.rsquared_adj:.4f}, n={int(res.nobs)}, F={res.fvalue:.2f}")
    return out


# =============================================================================
# ML2 — Permutation importance (RF sin texto, variables nombradas)
# =============================================================================
def build_discursive_matrix(df: pd.DataFrame):
    cat_feat = [
        "marco_final",
        "emocion_final",
        "estrategia_final",
        "frontera_final",
        "candidato",
        "fase",
        "tipo_hilo",
    ]
    num_feat = ["comment_score", "n_chars", "n_words"]
    d = df[df["polarizacion_consenso"].notna()].copy()
    d = ensure_columns(d, cat_feat + num_feat)
    for c in cat_feat:
        d[c] = d[c].astype(str)
    for c in num_feat:
        d[c] = pd.to_numeric(d[c], errors="coerce")
    X = d[cat_feat + num_feat]
    y = d["polarizacion_consenso"].astype(float)
    prep = ColumnTransformer(
        [
            ("cat", _one_hot_encoder(), cat_feat),
            (
                "num",
                Pipeline(
                    [
                        ("imp", SimpleImputer(strategy="median")),
                        ("sc", StandardScaler()),
                    ]
                ),
                num_feat,
            ),
        ],
        remainder="drop",
    )
    return X, y, prep, cat_feat, num_feat


def run_ml2_permutation(df: pd.DataFrame) -> tuple[RandomForestRegressor, Pipeline]:
    print("\n[ML2] Importancia por permutación (RandomForest)...")
    X, y, prep, cat_feat, num_feat = build_discursive_matrix(df)
    pipe = Pipeline(
        [
            ("prep", prep),
            (
                "model",
                RandomForestRegressor(
                    n_estimators=300,
                    random_state=RANDOM_STATE,
                    n_jobs=-1,
                    min_samples_leaf=2,
                ),
            ),
        ]
    )
    pipe.fit(X, y)
    r2_base = r2_score(y, pipe.predict(X))

    perm = permutation_importance(
        pipe,
        X,
        y,
        n_repeats=10,
        random_state=RANDOM_STATE,
        scoring="r2",
        n_jobs=-1,
    )
    # permutation_importance a nivel columnas de X (no one-hot expandido)
    names = list(X.columns)
    imp_df = pd.DataFrame(
        {
            "feature": names,
            "importance_mean": perm.importances_mean,
            "importance_std": perm.importances_std,
            "r2_drop_mean": -perm.importances_mean,
        }
    ).sort_values("importance_mean", ascending=False)

    imp_df["interpretacion"] = "Caída media en R² al permutar (mayor = más importante)"
    imp_df.to_csv(OUT_DIR / "permutation_importance_polarizacion.csv", index=False)

    fig, ax = plt.subplots(figsize=(10, max(7, 0.28 * len(imp_df))))
    order = imp_df.sort_values("importance_mean", ascending=True)
    ypos = np.arange(len(order))
    ax.barh(
        ypos,
        order["importance_mean"],
        xerr=order["importance_std"],
        color="#2980B9",
        capsize=2,
    )
    ax.set_yticks(ypos)
    ax.set_yticklabels(order["feature"], fontsize=8)
    ax.set_xlabel("Importancia (↓ R² al permutar)")
    ax.set_title(
        f"Permutation importance vs RandomForest (R² ref.≈{r2_base:.3f})",
        fontweight="bold",
    )
    fig.tight_layout()
    fig.savefig(OUT_DIR / "permutation_importance_polarizacion.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    return pipe.named_steps["model"], pipe


# =============================================================================
# ML3 — ROC comparativo
# =============================================================================
def run_ml3_roc(df: pd.DataFrame) -> None:
    print("\n[ML3] Curvas ROC (polarización alta)...")
    d = df[df["polarizacion_consenso"].notna()].copy()
    d["pol_alta"] = (d["polarizacion_consenso"] >= 0.6).astype(int)
    cat_feat = [
        "marco_final",
        "emocion_final",
        "estrategia_final",
        "frontera_final",
        "candidato",
        "fase",
        "tipo_hilo",
    ]
    num_feat = ["comment_score", "n_chars", "n_words", "polarizacion_consenso"]
    # Para clasificación no filtramos polarización del predictor: excluir leakage
    num_feat = ["comment_score", "n_chars", "n_words"]
    d = ensure_columns(d, cat_feat + num_feat)
    for c in cat_feat:
        d[c] = d[c].astype(str)
    X = d[cat_feat + num_feat]
    y = d["pol_alta"].values
    X_tr, X_te, y_tr, y_te = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=y
    )

    prep = ColumnTransformer(
        [
            ("cat", _one_hot_encoder(), cat_feat),
            (
                "num",
                Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler())]),
                num_feat,
            ),
        ]
    )

    models = {
        "LogReg": LogisticRegression(max_iter=3000, class_weight="balanced", random_state=RANDOM_STATE),
        "RandomForest": RandomForestClassifier(
            n_estimators=300,
            random_state=RANDOM_STATE,
            class_weight="balanced_subsample",
            n_jobs=-1,
        ),
        "GBM": GradientBoostingClassifier(random_state=RANDOM_STATE),
    }

    rows = []
    fig, ax = plt.subplots(figsize=(10, 7))
    colors = {"LogReg": "#8E44AD", "RandomForest": "#27AE60", "GBM": "#E67E22"}
    for name, est in models.items():
        pipe = Pipeline([("prep", prep), ("model", est)])
        pipe.fit(X_tr, y_tr)
        if hasattr(pipe.named_steps["model"], "predict_proba"):
            p = pipe.predict_proba(X_te)[:, 1]
        else:
            p = pipe.decision_function(X_te)
        fpr, tpr, _ = roc_curve(y_te, p)
        roc_auc = auc(fpr, tpr)
        rows.append({"modelo": name, "AUC": round(roc_auc, 4)})
        ax.plot(fpr, tpr, color=colors[name], lw=2, label=f"{name} (AUC={roc_auc:.3f})")

    ax.plot([0, 1], [0, 1], "k--", lw=1, alpha=0.5, label="Aleatorio")
    ax.set_xlabel("Tasa falsos positivos")
    ax.set_ylabel("Tasa verdaderos positivos")
    ax.set_title("ROC: clasificación polarización alta (≥ 0.6)", fontweight="bold")
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "roc_curves_polarizacion_alta.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    pd.DataFrame(rows).to_csv(OUT_DIR / "auc_comparacion_modelos.csv", index=False)


# =============================================================================
# ML4 — SHAP
# =============================================================================
def run_ml4_shap(df: pd.DataFrame, rf_pipe: Pipeline) -> None:
    print("\n[ML4] SHAP (TreeExplainer sobre RandomForest discursivo)...")
    shap = ensure_shap()
    X, y, _, _, _ = build_discursive_matrix(df)
    prep = rf_pipe.named_steps["prep"]
    rf: RandomForestRegressor = rf_pipe.named_steps["model"]
    X_t = prep.transform(X)
    feat_names = list(prep.get_feature_names_out())
    rng = np.random.RandomState(RANDOM_STATE)
    idx = rng.choice(len(X), size=min(1000, len(X)), replace=False)
    X_s = X_t[idx]
    if hasattr(X_s, "toarray"):
        X_s = X_s.toarray()

    explainer = shap.TreeExplainer(rf)
    sv = explainer.shap_values(X_s)

    shap.summary_plot(
        sv,
        X_s,
        feature_names=feat_names,
        show=False,
        plot_size=(10, 8),
    )
    plt.title("SHAP: impacto sobre polarización (muestra n≤1000)", fontweight="bold")
    plt.tight_layout()
    plt.savefig(OUT_DIR / "shap_summary_polarizacion.png", dpi=DPI, bbox_inches="tight")
    plt.close()

    mean_abs = np.abs(sv).mean(axis=0)
    std_abs = np.abs(sv).std(axis=0)
    order_feat = np.argsort(mean_abs)[::-1][:20]
    imp = pd.DataFrame(
        {
            "feature": [feat_names[i] for i in order_feat],
            "mean_abs_shap": mean_abs[order_feat],
            "std_abs_shap": std_abs[order_feat],
        }
    )
    imp.to_csv(OUT_DIR / "shap_values_resumen.csv", index=False)

    fig, ax = plt.subplots(figsize=(10, 7))
    ax.barh(imp["feature"][::-1], imp["mean_abs_shap"][::-1], color="#2980B9")
    ax.set_title("SHAP: importancia media (|SHAP|) — top 20", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "shap_importance_polarizacion.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    # Top 3 features "discursivas" (prefijos categóricos)
    disc = []
    for i, fn in enumerate(feat_names):
        if any(
            x in fn
            for x in (
                "marco_final",
                "emocion_final",
                "estrategia_final",
                "frontera_final",
            )
        ):
            disc.append((mean_abs[i], i, fn))
    disc.sort(reverse=True)
    top3 = disc[:3]
    if len(top3) < 3:
        for i in order_feat:
            if len(top3) >= 3:
                break
            if i not in [t[1] for t in top3]:
                top3.append((mean_abs[i], i, feat_names[i]))

    for _, j, fn in top3[:3]:
        shap.dependence_plot(
            j,
            sv,
            X_s,
            feature_names=feat_names,
            show=False,
        )
        plt.title(f"SHAP dependence: {fn}", fontweight="bold")
        safe = "".join(c if c.isalnum() or c in "_-" else "_" for c in fn)[:80]
        plt.tight_layout()
        plt.savefig(OUT_DIR / f"shap_dependence_{safe}.png", dpi=DPI, bbox_inches="tight")
        plt.close()


# =============================================================================
# ML5 — Clustering perfiles
# =============================================================================
def run_ml5_clustering(df: pd.DataFrame) -> None:
    print("\n[ML5] KMeans perfiles discursivos...")
    cols = [
        "marco_final",
        "emocion_final",
        "estrategia_final",
        "frontera_final",
        "candidato",
        "tipo_hilo",
        "pol_grupo",
    ]
    d = df.dropna(subset=["polarizacion_consenso"]).copy()
    d = ensure_columns(d, cols)
    for c in cols:
        d[c] = d[c].astype(str)
    enc = _one_hot_encoder()
    Xe = enc.fit_transform(d[cols])
    feat_labels = list(enc.get_feature_names_out(cols))

    best_k, best_sil = 3, -1.0
    for k in range(3, 9):
        km = KMeans(n_clusters=k, random_state=RANDOM_STATE, n_init=10)
        lab = km.fit_predict(Xe)
        if len(set(lab)) < 2:
            continue
        sil = float(
            silhouette_score(
                Xe, lab, sample_size=min(5000, len(Xe)), random_state=RANDOM_STATE
            )
        )
        if sil > best_sil:
            best_sil, best_k = sil, k

    km = KMeans(n_clusters=best_k, random_state=RANDOM_STATE, n_init=10)
    d["cluster"] = km.fit_predict(Xe)

    rows = []
    for cl in sorted(d["cluster"].unique()):
        sub = d[d["cluster"] == cl]
        row = {
            "cluster": cl,
            "n": len(sub),
            "polarizacion_media": sub["polarizacion_consenso"].mean(),
            "marco_dominante": sub["marco_final"].mode().iloc[0] if len(sub) else "",
            "emocion_dominante": sub["emocion_final"].mode().iloc[0] if len(sub) else "",
            "estrategia_dominante": sub["estrategia_final"].mode().iloc[0] if len(sub) else "",
            "candidato_moda": sub["candidato"].mode().iloc[0] if len(sub) else "",
        }
        rows.append(row)
    prof = pd.DataFrame(rows)
    prof.to_csv(OUT_DIR / "perfiles_discursivos_kmeans.csv", index=False)

    # Heatmap: proporciones por categoría (columnas = one-hot, filas = cluster)
    prop = []
    for cl in sorted(d["cluster"].unique()):
        sub = d[d["cluster"] == cl]
        idx = d["cluster"] == cl
        prop.append(Xe[idx].mean(axis=0))
    H = np.vstack(prop)
    # recortar columnas raras para legibilidad
    col_sum = H.sum(axis=0)
    keep = col_sum > 0.02
    H2 = H[:, keep]
    labs2 = [feat_labels[i] for i, k in enumerate(keep) if k]

    fig, ax = plt.subplots(figsize=(max(10, 0.12 * H2.shape[1]), max(7, 0.4 * best_k)))
    sns.heatmap(
        H2,
        ax=ax,
        cmap="YlOrRd",
        xticklabels=labs2,
        yticklabels=[f"C{i}" for i in sorted(d["cluster"].unique())],
        cbar_kws={"label": "Proporción"},
    )
    ax.set_title(f"Perfiles discursivos (K={best_k}, silhouette≈{best_sil:.3f})", fontweight="bold")
    plt.xticks(rotation=90, fontsize=6)
    fig.tight_layout()
    fig.savefig(OUT_DIR / "heatmap_perfiles_discursivos.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    # Radar: 5 ejes = concentración modal por dimensión
    dims = ["marco_final", "emocion_final", "estrategia_final", "frontera_final", "candidato"]
    angles = np.linspace(0, 2 * np.pi, len(dims), endpoint=False).tolist()
    angles += angles[:1]

    fig, ax = plt.subplots(figsize=(10, 10), subplot_kw=dict(polar=True))
    try:
        cmap = plt.colormaps["tab10"]
    except AttributeError:
        cmap = plt.get_cmap("tab10")
    for ci, cl in enumerate(sorted(d["cluster"].unique())):
        sub = d[d["cluster"] == cl]
        vals = []
        for dim in dims:
            vc = sub[dim].value_counts(normalize=True)
            vals.append(float(vc.max()) if len(vc) else 0.0)
        vals += vals[:1]
        col = cmap(ci % 10)
        ax.plot(angles, vals, "o-", label=f"Cluster {cl}", color=col)
        ax.fill(angles, vals, alpha=0.08, color=col)
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(dims)
    ax.set_ylim(0, 1)
    ax.set_title("Radar: concentración modal por dimensión (KMeans)", fontweight="bold", y=1.08)
    ax.legend(loc="upper right", bbox_to_anchor=(1.25, 1.0))
    fig.tight_layout()
    fig.savefig(OUT_DIR / "radar_perfiles_discursivos.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)


def run_radar_por_candidato(df: pd.DataFrame) -> None:
    """Radar mismo criterio que KMeans (max proporción modal por dimensión), una línea por candidato."""
    print("\n[ML5b] Radar concentración modal por candidato (cuatro líneas)...")
    CANDS = ["kast", "kaiser", "matthei", "jara"]
    # Sin eje «candidato» (constante dentro de cada submuestra); se incluye grupo de polarización.
    dims = ["marco_final", "emocion_final", "estrategia_final", "frontera_final", "pol_grupo"]
    dim_labels = ["Marco", "Emoción", "Estrategia", "Frontera", "Grupo pol."]
    d = df[df["polarizacion_consenso"].notna()].copy()
    d = ensure_columns(d, dims + ["candidato"])
    if "pol_grupo" not in d.columns:
        d["pol_grupo"] = d["polarizacion_consenso"].apply(polar_level)
    for c in dims + ["candidato"]:
        d[c] = d[c].astype(str).replace({"nan": "desconocido", "None": "desconocido"})
    d = d[d["candidato"].isin(CANDS)].copy()
    if len(d) < 80:
        print("  [WARN] Muy pocas filas para radar por candidato; se omite.")
        return

    rows = []
    angles = np.linspace(0, 2 * np.pi, len(dims), endpoint=False).tolist()
    angles_closed = angles + angles[:1]

    fig, ax = plt.subplots(figsize=(10, 10), subplot_kw=dict(polar=True))
    for cand in CANDS:
        sub = d[d["candidato"] == cand]
        if len(sub) < 5:
            continue
        vals = []
        for dim in dims:
            vc = sub[dim].value_counts(normalize=True)
            vals.append(float(vc.max()) if len(vc) else 0.0)
        vals_closed = vals + vals[:1]
        color = COLORES_CAND.get(cand, "#566573")
        lab = cand.capitalize()
        ax.plot(angles_closed, vals_closed, "o-", linewidth=2.2, label=lab, color=color)
        ax.fill(angles_closed, vals_closed, alpha=0.07, color=color)
        rows.append(
            {
                "candidato": cand,
                "n": len(sub),
                "polarizacion_media": float(sub["polarizacion_consenso"].mean()),
                **{dims[i]: vals[i] for i in range(len(dims))},
            }
        )

    ax.set_xticks(angles)
    ax.set_xticklabels(dim_labels, size=10)
    ax.set_ylim(0, 1)
    ax.set_title(
        "Radar: concentración modal por dimensión (por candidato target)",
        fontweight="bold",
        y=1.08,
    )
    ax.legend(loc="upper right", bbox_to_anchor=(1.28, 1.05), title="Candidato")
    fig.tight_layout()
    out_png = OUT_DIR / "radar_candidatos_cuatro.png"
    fig.savefig(out_png, dpi=DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  Figura guardada: {out_png.name}")
    if rows:
        pd.DataFrame(rows).to_csv(OUT_DIR / "radar_concentracion_modal_candidatos.csv", index=False)
        print("  CSV guardado: radar_concentracion_modal_candidatos.csv")
    try:
        FIG_THESIS.mkdir(parents=True, exist_ok=True)
        shutil.copy2(out_png, FIG_THESIS / out_png.name)
        if (OUT_DIR / "radar_concentracion_modal_candidatos.csv").is_file():
            shutil.copy2(
                OUT_DIR / "radar_concentracion_modal_candidatos.csv",
                FIG_THESIS / "radar_concentracion_modal_candidatos.csv",
            )
        print(f"  Copiado a fig_thesis: {out_png.name}")
    except Exception as e:
        print(f"  [WARN] Copia a fig_thesis: {e}")


# =============================================================================
# ML6 — Multinomial emoción
# =============================================================================
def run_ml6_multinomial(df: pd.DataFrame) -> None:
    print("\n[ML6] Regresión logística multinomial (emoción)...")
    d = df.copy()
    d["emocion_final"] = d["emocion_final"].astype(str)
    d = d[~d["emocion_final"].isin(["ninguna", "ERROR", "nan"])].copy()
    d = d[d["emocion_final"].notna()]
    cols_cat = ["marco_final", "estrategia_final", "candidato", "fase"]
    for c in cols_cat:
        d[c] = d[c].astype(str)
    d["polarizacion_consenso"] = pd.to_numeric(d["polarizacion_consenso"], errors="coerce")
    d = d.dropna(subset=["polarizacion_consenso"])
    X = d[cols_cat + ["polarizacion_consenso"]]
    y = d["emocion_final"].astype(str)

    X_tr, X_te, y_tr, y_te = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=safe_stratify(y)
    )

    prep = ColumnTransformer(
        [
            ("cat", _one_hot_encoder(), cols_cat),
            (
                "num",
                Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler())]),
                ["polarizacion_consenso"],
            ),
        ]
    )
    # sklearn ≥1.7 eliminó multi_class; lbfgs + >2 clases ⇒ pérdida multinomial
    try:
        lr = LogisticRegression(
            multi_class="multinomial",
            max_iter=3000,
            C=1.0,
            random_state=RANDOM_STATE,
            solver="lbfgs",
        )
    except TypeError:
        lr = LogisticRegression(
            max_iter=3000,
            C=1.0,
            random_state=RANDOM_STATE,
            solver="lbfgs",
        )
    pipe = Pipeline([("prep", prep), ("model", lr)])
    pipe.fit(X_tr, y_tr)
    pred = pipe.predict(X_te)
    report = classification_report(y_te, pred, output_dict=True)
    pd.DataFrame(report).T.to_csv(OUT_DIR / "resultados_multinomial_emocion.csv")

    labels = sorted(y.unique())
    cm = confusion_matrix(y_te, pred, labels=labels)
    cm_n = cm.astype(float) / cm.sum(axis=1, keepdims=True).clip(min=1e-9)

    fig, ax = plt.subplots(figsize=(10, 8))
    sns.heatmap(
        cm_n,
        annot=True,
        fmt=".2f",
        cmap="Blues",
        xticklabels=labels,
        yticklabels=labels,
        ax=ax,
    )
    ax.set_xlabel("Predicho")
    ax.set_ylabel("Observado")
    ax.set_title("Matriz de confusión normalizada — emoción (multinomial)", fontweight="bold")
    fig.tight_layout()
    fig.savefig(OUT_DIR / "cm_emocion_multinomial.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)


# =============================================================================
# ML7 — Validación cruzada
# =============================================================================
def run_ml7_cv(df: pd.DataFrame) -> pd.DataFrame:
    print("\n[ML7] Validación cruzada (5-fold)...")
    d = df[df["polarizacion_consenso"].notna() & (df["texto"].str.len() > 5)].copy()
    d = ensure_columns(d, CAT_COLS)
    X = d[[TEXT_COL] + CAT_COLS + NUM_COLS]
    y = d["polarizacion_consenso"].astype(float)

    cv = KFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE)
    reg_models = {
        "Ridge": Ridge(alpha=1.0),
        "RandomForest": RandomForestRegressor(n_estimators=300, random_state=RANDOM_STATE, n_jobs=-1),
        "GBM": GradientBoostingRegressor(
            n_estimators=200,
            max_depth=5,
            learning_rate=0.05,
            random_state=RANDOM_STATE,
        ),
    }

    fold_rows = []
    for name, model in reg_models.items():
        steps = [("prep", make_preprocessor(CAT_COLS, NUM_COLS, TEXT_COL))]
        if name == "GBM":
            steps.append(("svd", TruncatedSVD(n_components=300, random_state=RANDOM_STATE)))
        steps.append(("model", model))
        pipe = Pipeline(steps)
        scores = cross_validate(
            pipe,
            X,
            y,
            cv=cv,
            scoring={"mae": "neg_mean_absolute_error", "r2": "r2"},
            n_jobs=-1,
        )
        mae = -scores["test_mae"]
        r2s = scores["test_r2"]
        fold_rows.append(
            {
                "modelo": name,
                "tarea": "regresión polarización",
                "metrica": "MAE",
                "mean": mae.mean(),
                "std": mae.std(),
            }
        )
        fold_rows.append(
            {
                "modelo": name,
                "tarea": "regresión polarización",
                "metrica": "R2",
                "mean": r2s.mean(),
                "std": r2s.std(),
            }
        )

    # Clasificación polarización alta — RF
    d2 = df[df["polarizacion_consenso"].notna()].copy()
    d2["pol_alta"] = (d2["polarizacion_consenso"] >= 0.6).astype(int)
    cat_feat = [
        "marco_final",
        "emocion_final",
        "estrategia_final",
        "frontera_final",
        "candidato",
        "fase",
        "tipo_hilo",
    ]
    num_feat = ["comment_score", "n_chars", "n_words"]
    d2 = ensure_columns(d2, cat_feat + num_feat)
    for c in cat_feat:
        d2[c] = d2[c].astype(str)
    Xc = d2[cat_feat + num_feat]
    yc = d2["pol_alta"].values
    prep_c = ColumnTransformer(
        [
            ("cat", _one_hot_encoder(), cat_feat),
            (
                "num",
                Pipeline([("imp", SimpleImputer(strategy="median")), ("sc", StandardScaler())]),
                num_feat,
            ),
        ]
    )
    clf_pipe = Pipeline(
        [
            ("prep", prep_c),
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
    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE)
    cv_clf = cross_validate(
        clf_pipe,
        Xc,
        yc,
        cv=skf,
        scoring={"f1_macro": "f1_macro", "roc_auc": "roc_auc"},
        n_jobs=-1,
    )
    for metric in ["f1_macro", "roc_auc"]:
        v = cv_clf[f"test_{metric}"]
        fold_rows.append(
            {
                "modelo": "RandomForest",
                "tarea": "clasificación pol. alta",
                "metrica": metric,
                "mean": v.mean(),
                "std": v.std(),
            }
        )

    cv_df = pd.DataFrame(fold_rows)
    cv_df.to_csv(OUT_DIR / "validacion_cruzada_resumen.csv", index=False)

    # Boxplot métricas por modelo (folds = puntos)
    reg_scores = {name: {"mae": [], "r2": []} for name in reg_models}
    for name in reg_models:
        steps = [("prep", make_preprocessor(CAT_COLS, NUM_COLS, TEXT_COL))]
        if name == "GBM":
            steps.append(("svd", TruncatedSVD(n_components=300, random_state=RANDOM_STATE)))
        steps.append(("model", reg_models[name]))
        pipe = Pipeline(steps)
        scores = cross_validate(
            pipe,
            X,
            y,
            cv=cv,
            scoring={"mae": "neg_mean_absolute_error", "r2": "r2"},
            n_jobs=-1,
        )
        reg_scores[name]["mae"] = -scores["test_mae"]
        reg_scores[name]["r2"] = scores["test_r2"]

    fig, axes = plt.subplots(2, 2, figsize=(12, 10))
    ax = axes[0, 0]
    ax.boxplot([reg_scores[m]["mae"] for m in reg_models], labels=list(reg_models.keys()))
    ax.set_title("MAE por fold — regresión", fontweight="bold")
    ax = axes[0, 1]
    ax.boxplot([reg_scores[m]["r2"] for m in reg_models], labels=list(reg_models.keys()))
    ax.set_title("R² por fold — regresión", fontweight="bold")
    f1v = cv_clf["test_f1_macro"]
    aucv = cv_clf["test_roc_auc"]
    ax = axes[1, 0]
    ax.boxplot([f1v], labels=["RF pol_alta"])
    ax.set_title("F1-macro por fold — clasificación", fontweight="bold")
    ax = axes[1, 1]
    ax.boxplot([aucv], labels=["RF pol_alta"])
    ax.set_title("AUC por fold — clasificación", fontweight="bold")
    fig.suptitle("Validación cruzada 5-fold", fontweight="bold", fontsize=14)
    fig.tight_layout()
    fig.savefig(OUT_DIR / "boxplot_cv_modelos.png", dpi=DPI, bbox_inches="tight")
    plt.close(fig)

    return cv_df


# =============================================================================
# Resumen tesis + panel apilado
# =============================================================================
def build_tabla_resumen(cv_df: pd.DataFrame) -> None:
    rows = []
    for _, r in cv_df.iterrows():
        interp = (
            "Estabilidad predictiva de polarización en regresión"
            if r["tarea"] == "regresión polarización"
            else "Robustez del detector de polarización alta"
        )
        rows.append(
            {
                "Modelo": r["modelo"],
                "Tarea": r["tarea"],
                "Variables_usadas": "TF-IDF + categóricas + numéricas (reg.) o solo discursivas (clf.)",
                "Metrica_principal": r["metrica"],
                "Valor_mean_std": f"{r['mean']:.4f} ± {r['std']:.4f}",
                "Interpretacion": interp,
            }
        )
    pd.DataFrame(rows).to_csv(OUT_DIR / "tabla_resumen_ml_tesis.csv", index=False)


def stack_figures(paths: list[Path], out_name: str = "panel_ml_avanzado_apilado.png") -> None:
    existing = [p for p in paths if p.is_file()]
    if len(existing) < 2:
        return
    imgs = [mpl_image.imread(p) for p in existing]
    h = sum(im.shape[0] for im in imgs)
    w = max(im.shape[1] for im in imgs)
    fig, axes = plt.subplots(len(imgs), 1, figsize=(10, min(48, 3.5 * len(imgs))))
    if len(imgs) == 1:
        axes = [axes]
    for ax, im, p in zip(axes, imgs, existing):
        ax.imshow(im)
        ax.axis("off")
        ax.set_title(p.name, fontsize=9)
    fig.tight_layout()
    fig.savefig(OUT_DIR / out_name, dpi=150, bbox_inches="tight")
    plt.close(fig)


def print_checklist(expected: list[str]) -> None:
    print("\n--- Checklist salidas ---")
    for name in expected:
        p = OUT_DIR / name
        ok = "✅" if p.is_file() else "⬜"
        print(f"  {ok} {name}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"BASE_DIR={BASE_DIR}")
    print(f"OUT_DIR={OUT_DIR}")

    df = load_dataset()
    print(f"Filas dataset: {len(df):,}")

    run_ml1_ols(df)
    _, rf_pipe = run_ml2_permutation(df)
    run_ml3_roc(df)
    run_ml4_shap(df, rf_pipe)
    run_ml5_clustering(df)
    run_radar_por_candidato(df)
    run_ml6_multinomial(df)
    cv_df = run_ml7_cv(df)
    build_tabla_resumen(cv_df)

    panel_paths = [
        OUT_DIR / "coefplot_ols_polarizacion.png",
        OUT_DIR / "permutation_importance_polarizacion.png",
        OUT_DIR / "roc_curves_polarizacion_alta.png",
        OUT_DIR / "shap_importance_polarizacion.png",
        OUT_DIR / "heatmap_perfiles_discursivos.png",
        OUT_DIR / "boxplot_cv_modelos.png",
    ]
    stack_figures(panel_paths)

    expected = [
        "tabla_ols_polarizacion.csv",
        "coefplot_ols_polarizacion.png",
        "permutation_importance_polarizacion.csv",
        "permutation_importance_polarizacion.png",
        "roc_curves_polarizacion_alta.png",
        "auc_comparacion_modelos.csv",
        "shap_summary_polarizacion.png",
        "shap_importance_polarizacion.png",
        "shap_values_resumen.csv",
        "perfiles_discursivos_kmeans.csv",
        "heatmap_perfiles_discursivos.png",
        "radar_perfiles_discursivos.png",
        "radar_candidatos_cuatro.png",
        "radar_concentracion_modal_candidatos.csv",
        "cm_emocion_multinomial.png",
        "resultados_multinomial_emocion.csv",
        "validacion_cruzada_resumen.csv",
        "boxplot_cv_modelos.png",
        "tabla_resumen_ml_tesis.csv",
        "panel_ml_avanzado_apilado.png",
    ]
    # shap_dependence_* dinámicos
    for p in OUT_DIR.glob("shap_dependence_*.png"):
        if p.name not in expected:
            expected.append(p.name)

    print_checklist(sorted(set(expected)))


if __name__ == "__main__":
    main()
