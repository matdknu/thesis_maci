# -*- coding: utf-8 -*-
"""
Google Trends (Chile) · Últimos 90 días para candidatos
Actualiza data/trends/series/trends_candidatos_daily.csv
sobrescribiendo las fechas solapadas con datos nuevos.
"""

from datetime import date, timedelta
from pathlib import Path
import time
import random

# NOTE: The following line is not valid Python code and will cause a syntax error.
# To install pytrends, run the following command in your terminal, not in your .py file:

# Para instalar pytrends, ejecuta en terminal (no en este archivo Python):
#    pip install pytrends


import pandas as pd
from pytrends.request import TrendReq
from pytrends.exceptions import TooManyRequestsError



# ----------------- Parámetros básicos -----------------
GEO    = "CL"
HL     = "es-CL"
TZ     = 360
CAT    = 0
GPROP  = ""              # "", "news", "images", "youtube", "froogle"
DAYS_BACK = 90           # últimos 90 días

# Controles suaves para evitar 429
MAX_RETRIES          = 3     # reintentos por llamada
BASE_SLEEP_SECONDS   = 5.0   # base para backoff exponencial
PAUSE_BETWEEN_CALLS  = 8.0   # pausa fija entre llamadas a pytrends

# -------- Candidatos y alias --------
CANDIDATES = {
    "Evelyn Matthei": [
        "Evelyn Matthei", "Matthei"
    ],
    "José Antonio Kast": [
        "José Antonio Kast", "Kast", "Jose Antonio Kast"
    ],
    "Johannes Kaiser": [
        "Johannes Kaiser", "Kaiser"
    ],
    "Franco Parisi": [
        "Franco Parisi", "Parisi"
    ],
    "Jeannette Jara": [
        "Jeannette Jara", "Janet Jara", "Ministra Jara", "Jara"
    ],
    "Harold Mayne-Nicholls": [
    "Harold Mayne Nicholls", "Mayne-Nicholls", "Mayne Nicholls" 
    ],

    "Marco Enríquez-Ominami": [
        "Marco Enríquez Ominami", "MEO",
        "Enríquez Ominami", "Enriquez Ominami"
    ],
    "Eduardo Artés": [
        "Eduardo Artés", "Profe Artés", "Artés"
    ],
}

# --- Estructura de carpetas para las series de tendencias ---
TRENDS_SERIES_DIR = Path("data") / "trends" / "series"
TRENDS_SERIES_DIR.mkdir(parents=True, exist_ok=True)
OUT_CSV_DAILY = TRENDS_SERIES_DIR / "trends_candidatos_daily.csv"
OUT_PARQUET_DAILY = TRENDS_SERIES_DIR / "trends_candidatos_daily.parquet"


# ----------------- pytrends -----------------
def make_pytrends():
    """
    pytrends básico.
    """
    return TrendReq(hl=HL, tz=TZ)


pytrends = make_pytrends()


# ----------------- Helpers para backoff -----------------
def backoff_sleep(attempt: int, cap: float = 90.0):
    """
    Pausa con backoff exponencial + jitter.
    attempt = 0,1,2,...
    """
    delay = min(BASE_SLEEP_SECONDS * (2 ** attempt) + random.uniform(0, 2.0), cap)
    print(f"  [backoff] Sleeping {delay:.1f}s (attempt {attempt+1})...")
    time.sleep(delay)


def safe_build_payload(kw_list, timeframe, cat=0, geo="CL", gprop=""):
    """
    Wrapper con pocos reintentos alrededor de build_payload.
    """
    for i in range(MAX_RETRIES):
        try:
            pytrends.build_payload(
                kw_list=kw_list,
                cat=cat,
                timeframe=timeframe,
                geo=geo,
                gprop=gprop,
            )
            time.sleep(PAUSE_BETWEEN_CALLS)
            return
        except TooManyRequestsError:
            print("  TooManyRequestsError en build_payload()")
            if i == MAX_RETRIES - 1:
                print("  Máximo de reintentos alcanzado en build_payload; abortando.")
                raise
            backoff_sleep(i)
        except Exception as e:
            print(f"  Error en build_payload(): {e}")
            if i == MAX_RETRIES - 1:
                raise
            backoff_sleep(i)


def safe_interest_over_time():
    """
    Wrapper con pocos reintentos alrededor de interest_over_time.
    """
    for i in range(MAX_RETRIES):
        try:
            df = pytrends.interest_over_time()
            time.sleep(PAUSE_BETWEEN_CALLS)
            return df
        except TooManyRequestsError:
            print("  TooManyRequestsError en interest_over_time()")
            if i == MAX_RETRIES - 1:
                print("  Máximo de reintentos alcanzado en interest_over_time; abortando.")
                raise
            backoff_sleep(i)
        except Exception as e:
            print(f"  Error en interest_over_time(): {e}")
            if i == MAX_RETRIES - 1:
                raise
            backoff_sleep(i)


# ----------------- Utilidades -----------------
def ensure_all_candidate_cols(df: pd.DataFrame) -> pd.DataFrame:
    """
    Asegura que el DF tenga todas las columnas de candidatos.
    """
    for c in CANDIDATES.keys():
        if c not in df.columns:
            df[c] = pd.NA
    return df


# ----------------- Descarga últimos 90 días -----------------
def fetch_last_90_days() -> pd.DataFrame:
    """
    Descarga últimos 90 días diarios para TODOS los candidatos,
    agregando alias con el máximo diario por candidato.
    """
    today = date.today()
    start = today - timedelta(days=DAYS_BACK)
    timeframe = f"{start} {today}"

    print(f"Descargando Google Trends para {len(CANDIDATES)} candidatos")
    print(f"Timeframe: {timeframe} (últimos {DAYS_BACK} días)\n")

    frames = []
    for cname, aliases in CANDIDATES.items():
        print(f"→ Candidato: {cname}")
        # Si hay más de 5 alias, trocear en batches de 5 (límite Trends)
        alias_batches = [aliases[i:i + 5] for i in range(0, len(aliases), 5)]

        alias_series = []
        for batch in alias_batches:
            print(f"   - Batch aliases: {batch}")
            safe_build_payload(
                kw_list=batch,
                timeframe=timeframe,
                cat=CAT,
                geo=GEO,
                gprop=GPROP,
            )
            df = safe_interest_over_time()
            if df is None or df.empty:
                print("     (sin datos en este batch)")
                continue

            # Quitar columna isPartial si viene
            df = df.drop(columns=[c for c in df.columns if c.lower() == "ispartial"],
                         errors="ignore")
            alias_series.append(df)

        if not alias_series:
            print(f"   (no se obtuvieron datos para {cname})")
            continue

        # Combinar alias: index por fecha, columnas = alias
        merged = pd.concat(alias_series, axis=1).fillna(0)

        # Crear columna única por candidato: máximo diario entre alias
        merged[cname] = merged.max(axis=1)

        # Guardar solo la serie del candidato
        frames.append(merged[[cname]])

    if not frames:
        print("No se obtuvieron datos para ningún candidato.")
        return pd.DataFrame()

    out = pd.concat(frames, axis=1).fillna(0)
    out.index.name = "date"
    out = out.reset_index()
    out["date"] = pd.to_datetime(out["date"]).dt.date

    # Ordenar columnas: date + candidatos en orden definido
    cols = ["date"] + list(CANDIDATES.keys())
    out = out.reindex(columns=cols)

    return out


# ----------------- Main: unir con CSV histórico -----------------
def main():
    # 1) Descarga últimos 90 días
    df90 = fetch_last_90_days()
    if df90.empty:
        print("No hay datos nuevos que unir.")
        return

    # 2) Si existe el histórico, unir y sobrescribir fechas solapadas
    if OUT_CSV_DAILY.exists():
        print(f"\nLeyendo histórico: {OUT_CSV_DAILY}")
        hist = pd.read_csv(OUT_CSV_DAILY, parse_dates=["date"])
        hist["date"] = hist["date"].dt.date
        hist = ensure_all_candidate_cols(hist)
        df90 = ensure_all_candidate_cols(df90)

        combo = pd.concat([hist, df90], ignore_index=True)
        # Ordenar y eliminar duplicados por fecha (dejando el último = datos nuevos)
        combo = combo.sort_values("date").drop_duplicates(subset=["date"], keep="last")
    else:
        print("\nNo existe histórico previo. Creando uno nuevo.")
        combo = ensure_all_candidate_cols(df90)

    # 3) Reordenar columnas: date + candidatos + cualquier extra
    cols = ["date"] + list(CANDIDATES.keys())
    extra = [c for c in combo.columns if c not in cols]
    combo = combo.reindex(columns=cols + extra)

    # 4) Guardar
    combo.to_csv(OUT_CSV_DAILY, index=False)
    combo.to_parquet(OUT_PARQUET_DAILY, index=False)
    print("\n---------------------------------")
    print(f"Actualizado CSV diario: {OUT_CSV_DAILY}")
    print(f"Actualizado Parquet diario: {OUT_PARQUET_DAILY}")
    print(f"Rango: {combo['date'].min()} → {combo['date'].max()} (n={len(combo)})")
    print("---------------------------------\n")
    print(combo.tail())


if __name__ == "__main__":
    main()
