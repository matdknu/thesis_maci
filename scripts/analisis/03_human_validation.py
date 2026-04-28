# ==============================================================================
# CREAR DATASET DE VALIDACIÓN HUMANA — 250 CASOS
# Usa como input el archivo YA clasificado por APIs: analisis_API.csv
# No llama APIs. Solo prepara la muestra para anotación humana.
# ==============================================================================

from pathlib import Path
import random
import numpy as np
import pandas as pd

# ==============================================================================
# CONFIG
# ==============================================================================
try:
    BASE_DIR = Path(__file__).parent.parent.parent
except NameError:
    BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_maci")

INPUT_PATH  = BASE_DIR / "data" / "processed" / "analisis_API.csv"
OUTPUT_PATH = BASE_DIR / "data" / "processed" / "validacion_humana_250.csv"

N_MUESTRA = 250
SEED = 42

CANDIDATOS = ["kast", "kaiser", "matthei", "jara"]

# ==============================================================================
# HELPERS
# ==============================================================================
def contar_desacuerdos_sentimiento(df: pd.DataFrame) -> pd.Series:
    score = pd.Series(0, index=df.index, dtype="int64")
    for c in CANDIDATOS:
        col_oa = f"oa_sent_{c}"
        col_ds = f"ds_sent_{c}"
        if col_oa in df.columns and col_ds in df.columns:
            mask = df[col_oa].notna() & df[col_ds].notna()
            score += ((df[col_oa] != df[col_ds]) & mask).astype(int)
    return score


def muestreo_estratificado(df: pd.DataFrame, n_total: int, seed: int) -> pd.DataFrame:
    rng = random.Random(seed)

    strata_cols = []
    if "n_candidatos" in df.columns:
        strata_cols.append("n_candidatos")
    if "tipo_hilo" in df.columns:
        strata_cols.append("tipo_hilo")

    if not strata_cols:
        return df.sample(min(n_total, len(df)), random_state=seed).copy()

    grupos = list(df.groupby(strata_cols, dropna=False))
    total_rows = len(df)

    partes = []
    for _, sub in grupos:
        cuota = round(n_total * len(sub) / total_rows)
        cuota = min(cuota, len(sub))
        if cuota > 0:
            partes.append(sub.sample(cuota, random_state=rng.randint(0, 10**9)))

    out = pd.concat(partes, ignore_index=False).drop_duplicates()

    faltan = n_total - len(out)
    if faltan > 0:
        restantes = df.drop(index=out.index, errors="ignore")
        if len(restantes) > 0:
            extra = restantes.sample(min(faltan, len(restantes)), random_state=seed + 1)
            out = pd.concat([out, extra], ignore_index=False)

    if len(out) > n_total:
        out = out.sample(n_total, random_state=seed + 2)

    return out.copy()

# ==============================================================================
# MAIN
# ==============================================================================
def main():
    if not INPUT_PATH.exists():
        raise FileNotFoundError(f"No existe el archivo de entrada: {INPUT_PATH}")

    df = pd.read_csv(INPUT_PATH, on_bad_lines="skip")
    df = df[df["post_id"].astype(str) != "post_id"].copy()

    if "comentario_texto" in df.columns:
        df["comentario_texto"] = df["comentario_texto"].fillna("").astype(str)
        df = df[df["comentario_texto"].str.strip() != ""].copy()

    # ── Scores de desacuerdo entre modelos ────────────────────────────────────
    df["desacuerdo_marco"] = (
        (df["oa_marco"] != df["ds_marco"]).astype(int)
        if {"oa_marco", "ds_marco"}.issubset(df.columns) else 0
    )
    df["desacuerdo_emocion"] = (
        (df["oa_emocion"] != df["ds_emocion"]).astype(int)
        if {"oa_emocion", "ds_emocion"}.issubset(df.columns) else 0
    )
    df["desacuerdo_estrategia"] = (
        (df["oa_estrategia"] != df["ds_estrategia"]).astype(int)
        if {"oa_estrategia", "ds_estrategia"}.issubset(df.columns) else 0
    )
    df["desacuerdo_frontera"] = (
        (df["oa_frontera"] != df["ds_frontera"]).astype(int)
        if {"oa_frontera", "ds_frontera"}.issubset(df.columns) else 0
    )
    df["desacuerdo_sentimiento"] = contar_desacuerdos_sentimiento(df)

    # Mayor peso a sentimiento en la dificultad
    df["score_dificultad"] = (
        df["desacuerdo_sentimiento"] * 2
        + df["desacuerdo_marco"]
        + df["desacuerdo_emocion"]
        + df["desacuerdo_estrategia"]
        + df["desacuerdo_frontera"]
    )

    # ── 1) mitad difíciles ────────────────────────────────────────────────────
    n_dificiles = N_MUESTRA // 2
    df_dificiles = df.sort_values(
        by=["score_dificultad", "n_candidatos", "comment_score"],
        ascending=[False, False, False]
    ).head(min(n_dificiles, len(df))).copy()

    # ── 2) resto estratificado ────────────────────────────────────────────────
    df_restante = df.drop(index=df_dificiles.index, errors="ignore").copy()
    n_restante = N_MUESTRA - len(df_dificiles)
    df_estrato = muestreo_estratificado(df_restante, n_restante, SEED)

    df_val = pd.concat([df_dificiles, df_estrato], ignore_index=False).drop_duplicates()

    faltan = N_MUESTRA - len(df_val)
    if faltan > 0:
        extra_pool = df.drop(index=df_val.index, errors="ignore")
        if len(extra_pool) > 0:
            extra = extra_pool.sample(min(faltan, len(extra_pool)), random_state=SEED + 99)
            df_val = pd.concat([df_val, extra], ignore_index=False).drop_duplicates()

    if len(df_val) > N_MUESTRA:
        df_val = df_val.sample(N_MUESTRA, random_state=SEED + 123)

    df_val = df_val.sample(frac=1, random_state=SEED).reset_index(drop=True)

    # ── Columnas humanas vacías ───────────────────────────────────────────────
    df_val["hum_polarizacion"] = np.nan
    df_val["hum_marco"] = ""
    df_val["hum_emocion"] = ""
    df_val["hum_estrategia"] = ""
    df_val["hum_frontera"] = ""

    for c in CANDIDATOS:
        df_val[f"hum_sent_{c}"] = ""

    df_val["hum_revisado"] = ""
    df_val["hum_comentarios"] = ""

    # ── Orden de columnas ─────────────────────────────────────────────────────
    columnas_preferidas = [
        "post_id", "comment_author", "comment_score", "fecha",
        "candidatos", "n_candidatos", "tipo_hilo",
        "contexto_hilo", "comentario_texto",

        "oa_polarizacion", "ds_polarizacion", "polarizacion_consenso",
        "oa_marco", "ds_marco", "marco_final",
        "oa_emocion", "ds_emocion", "emocion_final",
        "oa_estrategia", "ds_estrategia", "estrategia_final",
        "oa_frontera", "ds_frontera", "frontera_final",

        "oa_sent_kast", "ds_sent_kast", "sent_final_kast",
        "oa_sent_kaiser", "ds_sent_kaiser", "sent_final_kaiser",
        "oa_sent_matthei", "ds_sent_matthei", "sent_final_matthei",
        "oa_sent_jara", "ds_sent_jara", "sent_final_jara",

        "score_dificultad",
        "desacuerdo_sentimiento", "desacuerdo_marco", "desacuerdo_emocion",
        "desacuerdo_estrategia", "desacuerdo_frontera",

        "hum_polarizacion",
        "hum_marco", "hum_emocion", "hum_estrategia", "hum_frontera",
        "hum_sent_kast", "hum_sent_kaiser", "hum_sent_matthei", "hum_sent_jara",
        "hum_revisado", "hum_comentarios",
    ]

    columnas_finales = [c for c in columnas_preferidas if c in df_val.columns] + [
        c for c in df_val.columns if c not in columnas_preferidas
    ]

    df_val = df_val[columnas_finales].copy()

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    df_val.to_csv(OUTPUT_PATH, index=False, encoding="utf-8")

    print("=" * 70)
    print("✅ DATASET DE VALIDACIÓN HUMANA CREADO")
    print("=" * 70)
    print(f"Archivo: {OUTPUT_PATH}")
    print(f"Casos:   {len(df_val):,}")
    print("\nColumnas humanas creadas:")
    print("  - hum_polarizacion")
    print("  - hum_marco")
    print("  - hum_emocion")
    print("  - hum_estrategia")
    print("  - hum_frontera")
    print("  - hum_sent_kast")
    print("  - hum_sent_kaiser")
    print("  - hum_sent_matthei")
    print("  - hum_sent_jara")
    print("  - hum_revisado")
    print("  - hum_comentarios")


if __name__ == "__main__":
    main()