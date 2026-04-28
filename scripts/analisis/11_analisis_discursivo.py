"""
11_analisis_discursivo.py

Bloque dedicado al análisis sustantivo de marcos, emociones, estrategias y
fronteras políticas. Este script responde directamente a las preguntas
teóricas del capítulo de resultados y usa como insumo principal el dataset
largo ya enriquecido por el pipeline base.
"""

from __future__ import annotations

import math
import warnings
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from scipy import stats

warnings.filterwarnings("ignore")


# ============================================================================
# ## CONFIGURACIÓN
# ============================================================================
try:
    BASE_DIR = Path(__file__).resolve().parent.parent.parent
except NameError:
    BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_maci")
OUT_DIR = BASE_DIR / "outputs_ml"
CSV = OUT_DIR / "dataset_largo_enriquecido.csv"
RANDOM_STATE = 42

COLORES_CAND = {
    "kast": "#C0392B",
    "kaiser": "#E67E22",
    "matthei": "#2980B9",
    "jara": "#27AE60",
}
FIRST_ROUND = pd.Timestamp("2025-11-14")
SECOND_ROUND = pd.Timestamp("2025-11-15")
ELECTION_DAY = pd.Timestamp("2025-12-16")
HOSTILES = {"ira", "desprecio", "indignacion"}
MODERADAS = {"esperanza", "alegria", "ninguna"}
STRATEGY_ORDER = [
    "deslegitimacion",
    "ridiculizacion",
    "construccion_amenaza",
    "esencializacion",
    "atribucion_oculta",
    "ninguna",
]
STRATEGY_COLORS = {
    "deslegitimacion": "#2980B9",
    "ridiculizacion": "#C0392B",
    "construccion_amenaza": "#E67E22",
    "esencializacion": "#8E44AD",
    "atribucion_oculta": "#27AE60",
    "ninguna": "#BDC3C7",
}

plt.style.use("seaborn-v0_8-whitegrid")
sns.set_theme(style="whitegrid")


# ============================================================================
# ## HELPERS
# ============================================================================
def load_dataset() -> pd.DataFrame:
    if not CSV.is_file():
        raise FileNotFoundError(CSV)
    df = pd.read_csv(CSV, on_bad_lines="skip", encoding="utf-8")
    df["fecha"] = pd.to_datetime(df["fecha"], errors="coerce")
    df["polarizacion_consenso"] = pd.to_numeric(df["polarizacion_consenso"], errors="coerce")
    for c in ["marco_final", "emocion_final", "estrategia_final", "frontera_final", "candidato", "fase"]:
        if c not in df.columns:
            df[c] = "desconocido"
        df[c] = df[c].fillna("desconocido").astype(str)
    return df


def cramers_v_from_table(tab: pd.DataFrame) -> tuple[float, float, float]:
    chi2, p, _, _ = stats.chi2_contingency(tab)
    n = tab.to_numpy().sum()
    if n == 0:
        return np.nan, np.nan, np.nan
    r, k = tab.shape
    v = math.sqrt(chi2 / (n * max(min(r - 1, k - 1), 1)))
    return chi2, p, v


def save_fig(fig: plt.Figure, filename: str) -> None:
    fig.tight_layout()
    fig.savefig(OUT_DIR / filename, dpi=300, bbox_inches="tight")
    plt.close(fig)


def add_summary_row(rows: list[dict], variable: str, tab: pd.DataFrame) -> None:
    chi2, p, v = cramers_v_from_table(tab)
    rows.append(
        {
            "variable": variable,
            "n_total": int(tab.to_numpy().sum()),
            "n_filas": int(tab.shape[0]),
            "n_columnas": int(tab.shape[1]),
            "chi2": float(chi2),
            "p_value": float(p),
            "cramers_v": float(v),
        }
    )


def normalize_rows(tab: pd.DataFrame) -> pd.DataFrame:
    return tab.div(tab.sum(axis=1).replace(0, np.nan), axis=0)


def order_candidates(df: pd.DataFrame) -> list[str]:
    preferred = ["kast", "kaiser", "matthei", "jara"]
    present = [c for c in preferred if c in set(df["candidato"].astype(str).unique())]
    rest = sorted(set(df["candidato"].astype(str).unique()) - set(present))
    return present + rest


# ============================================================================
# #-- D1 — DISTRIBUCIÓN DE MARCOS POR CANDIDATO
# ============================================================================
def d1_marcos_candidato(df: pd.DataFrame, summary_rows: list[dict]) -> None:
    d = df[df["marco_final"].astype(str) != "ERROR"].copy()
    tab = pd.crosstab(d["candidato"], d["marco_final"])
    prop = normalize_rows(tab)
    prop.to_csv(OUT_DIR / "distribucion_marcos_candidato.csv")
    add_summary_row(summary_rows, "marco_x_candidato", tab)

    fig, ax = plt.subplots(figsize=(12, 8))
    sns.heatmap(prop.reindex(order_candidates(d)), cmap="YlGnBu", annot=True, fmt=".2f", ax=ax)
    ax.set_title("Distribución de marcos por candidato", fontweight="bold")
    ax.set_xlabel("Marco")
    ax.set_ylabel("Candidato")
    save_fig(fig, "distribucion_marcos_candidato.png")


# ============================================================================
# #-- D2 — DISTRIBUCIÓN DE EMOCIONES POR CANDIDATO
# ============================================================================
def d2_emociones_candidato(df: pd.DataFrame, summary_rows: list[dict]) -> None:
    d = df[df["emocion_final"].astype(str) != "ERROR"].copy()
    d["emocion_grupo"] = np.where(
        d["emocion_final"].isin(HOSTILES),
        "hostil",
        np.where(d["emocion_final"].isin(MODERADAS), "moderada", "intermedia"),
    )
    tab = pd.crosstab(d["candidato"], d["emocion_final"])
    prop = normalize_rows(tab)
    prop.to_csv(OUT_DIR / "distribucion_emociones_candidato.csv")
    add_summary_row(summary_rows, "emocion_x_candidato", tab)

    stack = normalize_rows(pd.crosstab(d["candidato"], d["emocion_grupo"])).reindex(order_candidates(d))
    fig, ax = plt.subplots(figsize=(12, 8))
    bottom = np.zeros(len(stack))
    colors = {"hostil": "#C0392B", "intermedia": "#7F8C8D", "moderada": "#27AE60"}
    for col in stack.columns:
        ax.bar(stack.index, stack[col].values, bottom=bottom, label=col, color=colors.get(col, "#95A5A6"))
        bottom += stack[col].values
    ax.set_ylim(0, 1)
    ax.set_ylabel("Proporción")
    ax.set_title("Emociones por candidato (100% apilado)", fontweight="bold")
    ax.legend(title="Grupo emocional")
    save_fig(fig, "distribucion_emociones_candidato.png")


# ============================================================================
# #-- D3 — DISTRIBUCIÓN DE ESTRATEGIAS POR CANDIDATO
# ============================================================================
def d3_estrategias_candidato(df: pd.DataFrame, summary_rows: list[dict]) -> None:
    d = df[df["estrategia_final"].astype(str) != "ERROR"].copy()
    tab = pd.crosstab(d["candidato"], d["estrategia_final"])
    prop = normalize_rows(tab)
    prop.to_csv(OUT_DIR / "distribucion_estrategias_candidato.csv")
    add_summary_row(summary_rows, "estrategia_x_candidato", tab)

    fig, ax = plt.subplots(figsize=(12, 8))
    sns.heatmap(prop.reindex(order_candidates(d)), cmap="OrRd", annot=True, fmt=".2f", ax=ax)
    ax.set_title("Distribución de estrategias por candidato", fontweight="bold")
    ax.set_xlabel("Estrategia")
    ax.set_ylabel("Candidato")
    save_fig(fig, "distribucion_estrategias_candidato.png")


# ============================================================================
# #-- D4-D6 — SERIES SEMANALES
# ============================================================================
def _weekly_share_plot(
    df: pd.DataFrame,
    value_col: str,
    csv_name: str,
    png_name: str,
    title: str,
) -> None:
    d = df[df["fecha"].notna()].copy()
    d["semana"] = d["fecha"].dt.to_period("W").dt.start_time
    tab = pd.crosstab(d["semana"], d[value_col])
    prop = normalize_rows(tab).fillna(0)
    prop.to_csv(OUT_DIR / csv_name)

    fig, ax = plt.subplots(figsize=(12, 8))
    ax.stackplot(prop.index, prop.T.values, labels=prop.columns, alpha=0.85)
    ax.axvline(FIRST_ROUND, linestyle="--", color="black", linewidth=1.1)
    ax.axvline(SECOND_ROUND, linestyle=":", color="#34495E", linewidth=1.1)
    ax.set_ylim(0, 1)
    ax.set_ylabel("Proporción semanal")
    ax.set_title(title, fontweight="bold")
    ax.legend(loc="upper left", bbox_to_anchor=(1.01, 1))
    save_fig(fig, png_name)


def _weekly_strategy_table(df: pd.DataFrame, min_n: int = 20) -> pd.DataFrame:
    d = df[df["fecha"].notna()].copy()
    d["semana"] = d["fecha"].dt.to_period("W").dt.start_time

    counts = d.groupby("semana").size().rename("n_comentarios")
    valid_weeks = counts[counts >= min_n].index
    d = d[d["semana"].isin(valid_weeks)].copy()

    tab = pd.crosstab(d["semana"], d["estrategia_final"])
    tab = tab.reindex(columns=STRATEGY_ORDER, fill_value=0)
    prop = normalize_rows(tab).fillna(0)
    prop.insert(0, "n_comentarios", counts.loc[prop.index].astype(int))
    prop.to_csv(OUT_DIR / "serie_estrategias_semanal.csv")
    return prop


def d6_estrategias_temporal_mejorada(df: pd.DataFrame) -> None:
    d = df[df["estrategia_final"].astype(str) != "ERROR"].copy()
    prop = _weekly_strategy_table(d, min_n=20)

    fig, ax = plt.subplots(figsize=(12, 8))
    x = prop.index.to_pydatetime()
    y = [prop[col].to_numpy() for col in STRATEGY_ORDER]
    colors = [STRATEGY_COLORS[col] for col in STRATEGY_ORDER]
    labels = [col.replace("_", " ").capitalize() for col in STRATEGY_ORDER]
    stack_handles = ax.stackplot(x, y, labels=labels, colors=colors, alpha=0.9)

    line_handles = [
        ax.axvline(
            FIRST_ROUND,
            color="black",
            linestyle="--",
            linewidth=1.5,
            label="Primera vuelta",
        ),
        ax.axvline(
            SECOND_ROUND,
            color="#C0392B",
            linestyle=":",
            linewidth=1.5,
            label="Inicio segunda vuelta",
        ),
        ax.axvline(
            ELECTION_DAY,
            color="#7F8C8D",
            linestyle="--",
            linewidth=1.2,
            label="Elección",
        ),
    ]

    ax.set_ylim(0, 1)
    ax.set_ylabel("Proporción normalizada por semana")
    ax.set_title("Evolución semanal de estrategias discursivas", fontweight="bold", pad=18)
    ax.text(
        0.5,
        1.01,
        "Proporción normalizada por semana. Líneas verticales = hitos electorales.",
        transform=ax.transAxes,
        ha="center",
        va="bottom",
        fontsize=9,
        color="#555555",
    )
    ax.legend(
        list(stack_handles) + line_handles,
        labels + ["Primera vuelta", "Inicio segunda vuelta", "Elección"],
        loc="upper left",
        bbox_to_anchor=(1.01, 1),
        borderaxespad=0.0,
    )
    save_fig(fig, "serie_estrategias_semanal_mejorada.png")


def d4_d5_d6_temporal(df: pd.DataFrame) -> None:
    _weekly_share_plot(
        df[df["marco_final"].astype(str) != "ERROR"],
        "marco_final",
        "serie_marcos_semanal.csv",
        "serie_marcos_semanal.png",
        "Cambio temporal de marcos discursivos (semanal)",
    )
    _weekly_share_plot(
        df[df["emocion_final"].astype(str) != "ERROR"],
        "emocion_final",
        "serie_emociones_semanal.csv",
        "serie_emociones_semanal.png",
        "Cambio temporal de emociones (semanal)",
    )
    d6_estrategias_temporal_mejorada(df)


# ============================================================================
# #-- D7 — COMBINACIONES MARCO × EMOCIÓN
# ============================================================================
def d7_marco_emocion(df: pd.DataFrame, summary_rows: list[dict]) -> None:
    d = df[
        (df["marco_final"].astype(str) != "ERROR") & (df["emocion_final"].astype(str) != "ERROR")
    ].copy()
    tab = pd.crosstab(d["marco_final"], d["emocion_final"])
    add_summary_row(summary_rows, "marco_x_emocion", tab)

    combo = (
        d.groupby(["marco_final", "emocion_final"])
        .agg(
            n=("post_id", "size"),
            polarizacion_media=("polarizacion_consenso", "mean"),
        )
        .reset_index()
        .sort_values("n", ascending=False)
    )
    combo["proporcion"] = combo["n"] / combo["n"].sum()
    combo.to_csv(OUT_DIR / "combinaciones_marco_emocion.csv", index=False)

    fig, ax = plt.subplots(figsize=(12, 8))
    sns.heatmap(normalize_rows(tab), cmap="PuRd", annot=tab, fmt=".0f", ax=ax)
    ax.set_title("Combinaciones marco × emoción (color=proporción, texto=n)", fontweight="bold")
    save_fig(fig, "combinaciones_marco_emocion.png")


# ============================================================================
# #-- D8 — ESTRATEGIA × FRONTERA
# ============================================================================
def d8_estrategia_frontera(df: pd.DataFrame, summary_rows: list[dict]) -> None:
    d = df[
        (df["estrategia_final"].astype(str) != "ERROR") & (df["frontera_final"].astype(str) != "ERROR")
    ].copy()
    tab = pd.crosstab(d["estrategia_final"], d["frontera_final"])
    prop = normalize_rows(tab)
    prop.to_csv(OUT_DIR / "estrategia_por_frontera.csv")
    add_summary_row(summary_rows, "estrategia_x_frontera", tab)

    fig, ax = plt.subplots(figsize=(12, 8))
    sns.heatmap(prop, cmap="magma", annot=True, fmt=".2f", ax=ax)
    ax.set_title("Estrategias por frontera política", fontweight="bold")
    ax.set_xlabel("Frontera")
    ax.set_ylabel("Estrategia")
    save_fig(fig, "estrategia_por_frontera.png")


# ============================================================================
# #-- D9 — MARCOS POR FASE Y CANDIDATO
# ============================================================================
def d9_marcos_fase_candidato(df: pd.DataFrame, summary_rows: list[dict]) -> None:
    d = df[
        (df["marco_final"].astype(str) != "ERROR") & (df["fase"].astype(str) != "desconocido")
    ].copy()
    rows = []
    heat_rows = []
    for cand in order_candidates(d):
        sub = d[d["candidato"] == cand].copy()
        if sub.empty:
            continue
        tab = pd.crosstab(sub["fase"], sub["marco_final"])
        chi2, p, v = cramers_v_from_table(tab)
        rows.append(
            {
                "candidato": cand,
                "chi2": chi2,
                "p_value": p,
                "cramers_v": v,
                "n_total": int(tab.to_numpy().sum()),
            }
        )
        prop = normalize_rows(tab).reset_index().melt(id_vars="fase", var_name="marco_final", value_name="proporcion")
        prop["candidato"] = cand
        heat_rows.append(prop)
    out = pd.DataFrame(rows)
    out.to_csv(OUT_DIR / "marcos_por_fase_candidato.csv", index=False)
    add_summary_row(summary_rows, "marco_x_fase_global", pd.crosstab(d["fase"], d["marco_final"]))

    if heat_rows:
        heat = pd.concat(heat_rows, ignore_index=True)
        heat["fila"] = heat["candidato"] + " | " + heat["fase"].astype(str)
        mat = heat.pivot(index="fila", columns="marco_final", values="proporcion").fillna(0)
        fig, ax = plt.subplots(figsize=(12, max(8, 0.35 * len(mat))))
        sns.heatmap(mat, cmap="crest", annot=True, fmt=".2f", ax=ax)
        ax.set_title("Marcos por fase electoral y candidato", fontweight="bold")
        save_fig(fig, "marcos_por_fase_candidato.png")


# ============================================================================
# #-- D10 — TABLA RESUMEN
# ============================================================================
def d10_resumen(summary_rows: list[dict], df: pd.DataFrame) -> None:
    # Añadir una fila global simple de frontera
    tab_front = pd.crosstab(df["candidato"], df["frontera_final"])
    add_summary_row(summary_rows, "frontera_x_candidato", tab_front)
    out = pd.DataFrame(summary_rows)
    out.to_csv(OUT_DIR / "tabla_resumen_discursivo.csv", index=False)


# ============================================================================
# ## MAIN
# ============================================================================
def print_checklist(files: list[str]) -> None:
    print("\n--- Checklist salidas (11_analisis_discursivo) ---")
    for name in files:
        print(f"  {'✅' if (OUT_DIR / name).is_file() else '⬜'} {name}")


def main() -> None:
    print("=" * 80)
    print("11 — ANALISIS DISCURSIVO (MARCOS, EMOCIONES, ESTRATEGIAS, FRONTERAS)")
    print("=" * 80)
    df = load_dataset()
    summary_rows: list[dict] = []

    d1_marcos_candidato(df, summary_rows)
    d2_emociones_candidato(df, summary_rows)
    # Panel emociones × semana × candidato: generado en R — scripts/analisis/viz_r_tesis.R
    d3_estrategias_candidato(df, summary_rows)
    d4_d5_d6_temporal(df)
    d7_marco_emocion(df, summary_rows)
    d8_estrategia_frontera(df, summary_rows)
    d9_marcos_fase_candidato(df, summary_rows)
    d10_resumen(summary_rows, df)

    expected = [
        "distribucion_marcos_candidato.csv",
        "distribucion_marcos_candidato.png",
        "distribucion_emociones_candidato.csv",
        "distribucion_emociones_candidato.png",
        "distribucion_estrategias_candidato.csv",
        "distribucion_estrategias_candidato.png",
        "serie_marcos_semanal.csv",
        "serie_marcos_semanal.png",
        "serie_emociones_semanal.csv",
        "serie_emociones_semanal.png",
        "serie_estrategias_semanal.csv",
        "serie_estrategias_semanal_mejorada.png",
        "combinaciones_marco_emocion.csv",
        "combinaciones_marco_emocion.png",
        "estrategia_por_frontera.csv",
        "estrategia_por_frontera.png",
        "marcos_por_fase_candidato.csv",
        "marcos_por_fase_candidato.png",
        "tabla_resumen_discursivo.csv",
    ]
    print_checklist(expected)


if __name__ == "__main__":
    main()
