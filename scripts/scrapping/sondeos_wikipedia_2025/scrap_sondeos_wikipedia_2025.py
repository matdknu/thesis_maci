#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Scraping de tablas de sondeos (Wikipedia, elección presidencial Chile 2025).

Extrae tablas bajo secciones de:
- Primera vuelta
- Segunda vuelta

Guarda:
- CSV por tabla (raw)
- CSV consolidado por vuelta
- Parquet consolidado por vuelta (si pyarrow está disponible)
- Resumen de extracción en JSON
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from io import StringIO
from pathlib import Path
from typing import List, Optional

import pandas as pd
import requests
try:
    from bs4 import BeautifulSoup, Tag
except ModuleNotFoundError as exc:
    raise SystemExit(
        "Falta dependencia 'beautifulsoup4'. Instala en tu venv con:\n"
        "  python -m pip install beautifulsoup4 lxml"
    ) from exc


URL = (
    "https://es.wikipedia.org/wiki/"
    "Anexo:Sondeos_de_intenci%C3%B3n_de_voto_para_la_elecci%C3%B3n_"
    "presidencial_de_Chile_de_2025"
)

REPO_ROOT = Path(__file__).resolve().parents[3]
OUT_DIR = REPO_ROOT / "data" / "raw" / "sondeos_wikipedia_2025"
OUT_RAW = OUT_DIR / "tablas_raw"
OUT_CONSOLIDADO = OUT_DIR / "consolidado"

HEADERS_HTTP = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "es-CL,es;q=0.9,en;q=0.8",
}

HEADERS_OBJETIVO = {"h2", "h3", "h4"}


@dataclass
class TablaExtraida:
    tipo_vuelta: str
    heading: str
    index_en_seccion: int
    df: pd.DataFrame


def slug(texto: str) -> str:
    texto = texto.strip().lower()
    texto = re.sub(r"\s+", "_", texto)
    texto = re.sub(r"[^a-z0-9_]+", "", texto)
    return texto[:80] or "sin_titulo"


def normalizar_columnas(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    if isinstance(df.columns, pd.MultiIndex):
        nuevas = []
        for col in df.columns:
            partes = [str(x).strip() for x in col if str(x).strip() and str(x) != "nan"]
            nuevas.append(" | ".join(partes))
        df.columns = nuevas
    else:
        df.columns = [str(c).strip() for c in df.columns]

    df.columns = [re.sub(r"\s+", " ", c) for c in df.columns]
    return df


def clasificar_vuelta(heading: str) -> Optional[str]:
    h = heading.lower()
    if "primera vuelta" in h:
        return "primera_vuelta"
    if "segunda vuelta" in h:
        return "segunda_vuelta"
    return None


def obtener_heading_de_tabla(tabla: Tag) -> str:
    actual = tabla
    while actual is not None:
        actual = actual.find_previous()
        if actual is None:
            return "sin_heading"
        if actual.name in HEADERS_OBJETIVO:
            return actual.get_text(" ", strip=True)
    return "sin_heading"


def extraer_tablas() -> List[TablaExtraida]:
    print(f"Descargando pagina: {URL}")
    resp = requests.get(URL, headers=HEADERS_HTTP, timeout=30)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    tablas = soup.select("table.wikitable")
    if not tablas:
        raise RuntimeError("No se encontraron tablas con selector 'table.wikitable'.")

    resultados: List[TablaExtraida] = []
    contador_por_heading = {}

    for tabla in tablas:
        heading = obtener_heading_de_tabla(tabla)
        tipo = clasificar_vuelta(heading)
        if tipo is None:
            continue

        html = str(tabla)
        dfs = pd.read_html(StringIO(html))
        if not dfs:
            continue

        df = normalizar_columnas(dfs[0])
        idx = contador_por_heading.get(heading, 0) + 1
        contador_por_heading[heading] = idx
        resultados.append(TablaExtraida(tipo, heading, idx, df))

    return resultados


def guardar_resultados(tablas: List[TablaExtraida]) -> None:
    OUT_RAW.mkdir(parents=True, exist_ok=True)
    OUT_CONSOLIDADO.mkdir(parents=True, exist_ok=True)

    resumen = {
        "url": URL,
        "tablas_total_filtradas": len(tablas),
        "primera_vuelta_tablas": 0,
        "segunda_vuelta_tablas": 0,
        "archivos_raw": [],
    }

    por_tipo = {"primera_vuelta": [], "segunda_vuelta": []}

    for t in tablas:
        nombre = f"{t.tipo_vuelta}__{slug(t.heading)}__t{t.index_en_seccion:02d}.csv"
        ruta = OUT_RAW / nombre
        t.df.to_csv(ruta, index=False, encoding="utf-8")
        por_tipo[t.tipo_vuelta].append(t.df.assign(_heading=t.heading))
        resumen["archivos_raw"].append(str(ruta))
        if t.tipo_vuelta == "primera_vuelta":
            resumen["primera_vuelta_tablas"] += 1
        else:
            resumen["segunda_vuelta_tablas"] += 1

    for tipo, lista_df in por_tipo.items():
        if not lista_df:
            continue
        consolidado = pd.concat(lista_df, ignore_index=True)
        csv_path = OUT_CONSOLIDADO / f"{tipo}.csv"
        consolidado.to_csv(csv_path, index=False, encoding="utf-8")
        try:
            parquet_path = OUT_CONSOLIDADO / f"{tipo}.parquet"
            consolidado.to_parquet(parquet_path, index=False)
        except Exception as exc:
            print(f"No se pudo guardar Parquet para {tipo}: {exc}")

    resumen_path = OUT_DIR / "resumen_extraccion.json"
    resumen_path.write_text(json.dumps(resumen, ensure_ascii=False, indent=2), encoding="utf-8")

    print("\nExtraccion completada")
    print(f"- Tablas primera vuelta: {resumen['primera_vuelta_tablas']}")
    print(f"- Tablas segunda vuelta: {resumen['segunda_vuelta_tablas']}")
    print(f"- Salida: {OUT_DIR.resolve()}")


def main() -> None:
    tablas = extraer_tablas()
    if not tablas:
        raise RuntimeError(
            "No se extrajeron tablas de primera/segunda vuelta. "
            "Revisar estructura de la pagina."
        )
    guardar_resultados(tablas)


if __name__ == "__main__":
    main()
