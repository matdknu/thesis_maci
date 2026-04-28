"""
04_ajuste_polarizacion_lexica.py

Paso intermedio entre 03_aplicacion_api.py y el modelado.

Lee `analisis_API.csv`, busca terminos hostiles definidos en
`data/processed/lexico_polarizacion_hostil.csv` y aumenta en 60% la
polarizacion cuando el comentario contiene uno o mas de esos terminos.

Salida:
- data/processed/analisis_API_ajustado.csv
"""

from __future__ import annotations

import re
import unicodedata
from pathlib import Path

import pandas as pd

try:
    BASE_DIR = Path(__file__).parent.parent.parent
except NameError:
    BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_maci")

DATA_DIR = BASE_DIR / "data" / "processed"
INPUT_PATH = DATA_DIR / "analisis_API.csv"
LEXICON_PATH = DATA_DIR / "lexico_polarizacion_hostil.csv"
OUTPUT_PATH = DATA_DIR / "analisis_API_ajustado.csv"

DEFAULT_BOOST_FACTOR = 1.6
POLAR_COLS = ["oa_polarizacion", "ds_polarizacion", "polarizacion_consenso"]


def normalize_text(text: str) -> str:
    text = "" if pd.isna(text) else str(text)
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return text.lower()


def pattern_to_regex(pattern: str) -> re.Pattern[str]:
    norm = normalize_text(pattern).strip()
    if not norm:
        raise ValueError("Patron vacio en lexico hostil.")
    escaped = re.escape(norm).replace(r"\*", r"\w*")
    escaped = escaped.replace(r"\ ", r"\s+")
    return re.compile(rf"(?<!\w){escaped}(?!\w)", flags=re.IGNORECASE)


def load_lexicon(path: Path) -> list[dict]:
    lex = pd.read_csv(path)
    if "pattern" not in lex.columns:
        raise ValueError("El archivo de lexico debe tener una columna 'pattern'.")

    items: list[dict] = []
    seen: set[str] = set()
    for _, row in lex.iterrows():
        raw = str(row.get("pattern", "")).strip()
        key = normalize_text(raw).strip()
        if not key or key in seen:
            continue
        seen.add(key)
        try:
            multiplier = float(row.get("multiplier", DEFAULT_BOOST_FACTOR))
        except (TypeError, ValueError):
            multiplier = DEFAULT_BOOST_FACTOR
        category = str(row.get("categoria", "sin_categoria")).strip() or "sin_categoria"
        items.append(
            {
                "pattern": raw,
                "regex": pattern_to_regex(raw),
                "multiplier": multiplier,
                "categoria": category,
            }
        )
    return items


def detect_hostile_terms(text: str, lexicon: list[dict]) -> list[dict]:
    norm_text = normalize_text(text)
    hits = []
    for item in lexicon:
        if item["regex"].search(norm_text):
            hits.append(
                {
                    "pattern": item["pattern"],
                    "multiplier": item["multiplier"],
                    "categoria": item["categoria"],
                }
            )
    dedup = {}
    for hit in hits:
        dedup[normalize_text(hit["pattern"])] = hit
    return sorted(dedup.values(), key=lambda x: x["pattern"])


def boost_score(value: object, factor: float) -> float | None:
    if pd.isna(value):
        return None
    try:
        score = float(value)
    except (TypeError, ValueError):
        return None
    score = max(0.0, min(score, 1.0))
    return round(min(score * factor, 1.0), 4)


def main() -> None:
    if not INPUT_PATH.exists():
        raise SystemExit(f"No existe el input esperado: {INPUT_PATH}")
    if not LEXICON_PATH.exists():
        raise SystemExit(f"No existe el lexico esperado: {LEXICON_PATH}")

    df = pd.read_csv(INPUT_PATH, on_bad_lines="skip", encoding="utf-8")
    df = df[df["post_id"].astype(str) != "post_id"].copy()

    text_col = "comentario_texto" if "comentario_texto" in df.columns else "texto"
    if text_col not in df.columns:
        raise SystemExit("No se encontro la columna de texto para aplicar el ajuste.")

    lexicon = load_lexicon(LEXICON_PATH)

    for col in POLAR_COLS:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
            df[f"{col}_original"] = df[col]

    hits = df[text_col].fillna("").apply(lambda txt: detect_hostile_terms(txt, lexicon))
    df["ajuste_lexico_hostil"] = hits.apply(lambda x: int(len(x) > 0))
    df["ajuste_lexico_terminos"] = hits.apply(lambda x: " | ".join(hit["pattern"] for hit in x))
    df["ajuste_lexico_categorias"] = hits.apply(lambda x: " | ".join(sorted({hit["categoria"] for hit in x})))
    df["ajuste_lexico_factor"] = hits.apply(lambda x: max([hit["multiplier"] for hit in x], default=1.0))

    mask = df["ajuste_lexico_hostil"].eq(1)
    for col in POLAR_COLS:
        if col in df.columns:
            df.loc[mask, col] = df.loc[mask, [col, "ajuste_lexico_factor"]].apply(
                lambda row: boost_score(row[col], row["ajuste_lexico_factor"]), axis=1
            )

    df.to_csv(OUTPUT_PATH, index=False)

    print("=" * 72)
    print("AJUSTE LEXICO DE POLARIZACION COMPLETADO")
    print("=" * 72)
    print(f"Input:  {INPUT_PATH}")
    print(f"Lexico: {LEXICON_PATH}")
    print(f"Output: {OUTPUT_PATH}")
    print(f"Filas:   {len(df):,}")
    print(f"Ajustes: {int(mask.sum()):,}")
    if mask.any():
        top_terms = (
            df.loc[mask, "ajuste_lexico_terminos"]
            .str.split(r"\s+\|\s+")
            .explode()
            .dropna()
            .value_counts()
            .head(15)
        )
        print("\nTerminos mas activados:")
        print(top_terms.to_string())
        top_categories = (
            df.loc[mask, "ajuste_lexico_categorias"]
            .str.split(r"\s+\|\s+")
            .explode()
            .dropna()
            .value_counts()
            .head(10)
        )
        print("\nCategorias mas activadas:")
        print(top_categories.to_string())


if __name__ == "__main__":
    main()
