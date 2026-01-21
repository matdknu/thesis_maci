# -*- coding: utf-8 -*-
"""
Google Trends (Chile) · Últimos 90 días para candidatos
Actualiza data/trends/series/trends_candidatos_daily.csv (.parquet incluido)
sobrescribiendo las fechas solapadas con datos nuevos.

Mejoras de manejo de errores:
- Manejo robusto de errores de conexión y timeouts
- Validación de datos antes de guardar
- Guardado de progreso parcial
- Detección de bloqueos de IP
- Manejo de archivos corruptos
- Validación de formato de fechas
- Sistema de logging completo
- Backups automáticos
"""

from datetime import date, timedelta, datetime
from pathlib import Path
from typing import Tuple
import time
import random
import sys
import traceback
import logging
import os
import shutil

# NOTE: The following line is not valid Python code and will cause a syntax error.
# To install pytrends, run the following command in your terminal, not in your .py file:

# Para instalar pytrends, ejecuta en terminal (no en este archivo Python):
#    pip install pytrends


import pandas as pd
from pytrends.request import TrendReq
from pytrends.exceptions import TooManyRequestsError
import requests
from requests.exceptions import ConnectionError, Timeout, RequestException



# ----------------- Parámetros básicos -----------------
GEO    = "CL"
HL     = "es-CL"
TZ     = 360
CAT    = 0
GPROP  = ""              # "", "news", "images", "youtube", "froogle"
DAYS_BACK = 90           # últimos 90 días

# Controles suaves para evitar 429
MAX_RETRIES          = 5     # reintentos por llamada (aumentado)
BASE_SLEEP_SECONDS   = 30.0  # base para backoff exponencial (aumentado significativamente)
PAUSE_BETWEEN_CALLS  = 20.0  # pausa fija entre llamadas a pytrends (aumentado)
PAUSE_BETWEEN_CANDIDATES = 60.0  # pausa entre candidatos (aumentado a 1 minuto)
MAX_BACKOFF_CAP      = 600.0  # máximo tiempo de espera (10 minutos)
INITIAL_DELAY        = 30.0  # pausa inicial antes de comenzar
BLOCKED_WAIT_TIME    = 3600.0  # tiempo de espera cuando se detecta bloqueo (1 hora)
CONNECTION_TIMEOUT   = 60.0  # timeout para conexiones (segundos)
REQUEST_TIMEOUT      = 120.0  # timeout para requests completos (segundos)

# Configuración de logging
LOG_DIR = Path("data") / "trends" / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / f"trends_scraping_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# -------- Candidatos y alias --------
# Focus on 4 main candidates: Jara, Kast, Matthei, Kaiser
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
    "Jeannette Jara": [
        "Jeannette Jara", "Janet Jara", "Ministra Jara", "Jara"
    ],
}

# --- Estructura de carpetas para las series de tendencias ---
TRENDS_SERIES_DIR = Path("data") / "trends" / "series"
TRENDS_SERIES_DIR.mkdir(parents=True, exist_ok=True)
OUT_CSV_DAILY = TRENDS_SERIES_DIR / "trends_candidatos_daily.csv"
OUT_PARQUET_DAILY = TRENDS_SERIES_DIR / "trends_candidatos_daily.parquet"
BACKUP_DIR = TRENDS_SERIES_DIR / "backups"
BACKUP_DIR.mkdir(parents=True, exist_ok=True)
PARTIAL_SAVE_FILE = TRENDS_SERIES_DIR / "trends_candidatos_partial.csv"


# ----------------- Utilidades de validación -----------------
def check_disk_space(path: Path, min_mb: float = 10.0) -> bool:
    """Verifica que haya espacio suficiente en disco."""
    try:
        stat = shutil.disk_usage(path)
        free_mb = stat.free / (1024 * 1024)
        if free_mb < min_mb:
            logger.warning(f"Espacio en disco bajo: {free_mb:.1f} MB disponibles (mínimo: {min_mb} MB)")
            return False
        return True
    except Exception as e:
        logger.warning(f"No se pudo verificar espacio en disco: {e}")
        return True  # Continuar si no se puede verificar


def validate_dataframe(df: pd.DataFrame) -> Tuple[bool, str]:
    """
    Valida que el DataFrame tenga el formato correcto.
    Retorna (es_válido, mensaje_error)
    """
    if df is None:
        return False, "DataFrame es None"
    
    if df.empty:
        return False, "DataFrame está vacío"
    
    if 'date' not in df.columns:
        return False, "Falta columna 'date'"
    
    # Validar que las fechas sean válidas
    try:
        dates = pd.to_datetime(df['date'], errors='coerce')
        if dates.isna().any():
            return False, f"Hay {dates.isna().sum()} fechas inválidas"
    except Exception as e:
        return False, f"Error validando fechas: {e}"
    
    # Validar que los valores numéricos sean razonables (0-100 para Google Trends)
    numeric_cols = df.select_dtypes(include=['number']).columns
    for col in numeric_cols:
        if col != 'date':
            if df[col].min() < 0 or df[col].max() > 1000:  # Permitir un poco más que 100 por seguridad
                logger.warning(f"Columna {col} tiene valores fuera del rango esperado (0-100): min={df[col].min()}, max={df[col].max()}")
    
    return True, "OK"


def backup_existing_file(file_path: Path) -> bool:
    """Crea un backup del archivo existente antes de sobrescribirlo."""
    try:
        if file_path.exists():
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            backup_path = BACKUP_DIR / f"{file_path.stem}_{timestamp}{file_path.suffix}"
            shutil.copy2(file_path, backup_path)
            logger.info(f"Backup creado: {backup_path}")
            return True
    except Exception as e:
        logger.error(f"Error creando backup: {e}")
        return False
    return False


def safe_save_dataframe(df: pd.DataFrame, csv_path: Path, parquet_path: Path = None) -> bool:
    """
    Guarda el DataFrame de forma segura con validación y backup.
    Si parquet_path es None, solo guarda CSV.
    """
    try:
        # Validar datos
        is_valid, error_msg = validate_dataframe(df)
        if not is_valid:
            logger.error(f"Error de validación: {error_msg}")
            return False
        
        # Verificar espacio en disco
        if not check_disk_space(csv_path.parent):
            logger.error("No hay suficiente espacio en disco")
            return False
        
        # Crear backup de archivos existentes
        backup_existing_file(csv_path)
        if parquet_path is not None:
            backup_existing_file(parquet_path)
        
        # Guardar CSV con encoding UTF-8
        try:
            df.to_csv(csv_path, index=False, encoding='utf-8')
            logger.info(f"CSV guardado: {csv_path}")
        except Exception as e:
            logger.error(f"Error guardando CSV: {e}")
            return False
        
        # Guardar Parquet solo si se especifica
        if parquet_path is not None:
            try:
                df.to_parquet(parquet_path, index=False, engine='pyarrow')
                logger.info(f"Parquet guardado: {parquet_path}")
            except Exception as e:
                logger.error(f"Error guardando Parquet: {e}")
                # No fallar si solo falla el parquet
                logger.warning("Continuando sin guardar Parquet")
        
        return True
        
    except Exception as e:
        logger.error(f"Error en safe_save_dataframe: {e}")
        traceback.print_exc()
        return False


# ----------------- pytrends -----------------
def make_pytrends():
    """
    Crea una instancia de pytrends con manejo de errores.
    """
    try:
        return TrendReq(hl=HL, tz=TZ, timeout=(CONNECTION_TIMEOUT, REQUEST_TIMEOUT))
    except Exception as e:
        logger.error(f"Error creando TrendReq: {e}")
        raise


pytrends = make_pytrends()

# Contador global de errores 429 consecutivos
consecutive_429_count = 0


# ----------------- Helpers para backoff -----------------
def backoff_sleep(attempt: int, cap: float = None):
    """
    Pausa con backoff exponencial + jitter.
    attempt = 0,1,2,...
    """
    if cap is None:
        cap = MAX_BACKOFF_CAP
    delay = min(BASE_SLEEP_SECONDS * (2 ** attempt) + random.uniform(0, 10.0), cap)
    print(f"  [backoff] Sleeping {delay:.1f}s (attempt {attempt+1})...")
    time.sleep(delay)


def wait_if_blocked(consecutive_429s: int = 0):
    """
    Si hay muchos 429 consecutivos, espera un tiempo largo.
    """
    if consecutive_429s >= 3:
        wait_minutes = BLOCKED_WAIT_TIME / 60
        wait_hours = wait_minutes / 60
        print(f"\n  {'='*50}")
        print(f"  ⚠⚠⚠ BLOQUEO DETECTADO ⚠⚠⚠")
        print(f"  {'='*50}")
        print(f"  Se han recibido {consecutive_429s} errores 429 consecutivos.")
        print(f"  Google Trends está limitando las solicitudes desde esta IP.")
        print(f"  Esperando {wait_hours:.1f} horas ({wait_minutes:.0f} minutos, {BLOCKED_WAIT_TIME:.0f}s)")
        print(f"  antes de continuar...")
        print(f"  ")
        print(f"  Esto es normal cuando se hacen muchas solicitudes.")
        print(f"  Puedes cancelar con Ctrl+C si prefieres intentar más tarde.")
        print(f"  {'='*50}\n")
        time.sleep(BLOCKED_WAIT_TIME)
        print(f"  ✓ Espera completada. Reintentando...\n")


def safe_build_payload(kw_list, timeframe, cat=0, geo="CL", gprop=""):
    """
    Wrapper con reintentos alrededor de build_payload.
    Maneja errores de conexión, timeout y rate limiting.
    """
    global pytrends, consecutive_429_count
    
    for i in range(MAX_RETRIES):
        try:
            # Recrear pytrends si es necesario (puede ayudar con rate limits)
            if i > 0:
                logger.info(f"Recreando TrendReq (intento {i+1})")
                pytrends = make_pytrends()
                time.sleep(10)  # Pausa adicional al recrear
            
            pytrends.build_payload(
                kw_list=kw_list,
                cat=cat,
                timeframe=timeframe,
                geo=geo,
                gprop=gprop,
            )
            # Si llegamos aquí, la solicitud fue exitosa
            consecutive_429_count = 0
            time.sleep(PAUSE_BETWEEN_CALLS)
            return
        except TooManyRequestsError as e:
            consecutive_429_count += 1
            logger.warning(f"TooManyRequestsError en build_payload() (intento {i+1}/{MAX_RETRIES})")
            print(f"  TooManyRequestsError en build_payload() (intento {i+1}/{MAX_RETRIES})")
            
            # Si hay muchos 429 consecutivos, esperar mucho tiempo
            if consecutive_429_count >= 3:
                wait_if_blocked(consecutive_429_count)
                consecutive_429_count = 0  # Reset después de esperar
            
            if i == MAX_RETRIES - 1:
                logger.error("Máximo de reintentos alcanzado en build_payload")
                print("  Máximo de reintentos alcanzado en build_payload.")
                # En lugar de abortar inmediatamente, esperar y reintentar una vez más
                if consecutive_429_count < 3:
                    print("  Esperando tiempo adicional antes de fallar definitivamente...")
                    wait_if_blocked(consecutive_429_count)
                    # Último intento
                    try:
                        pytrends = make_pytrends()
                        time.sleep(10)
                        pytrends.build_payload(
                            kw_list=kw_list,
                            cat=cat,
                            timeframe=timeframe,
                            geo=geo,
                            gprop=gprop,
                        )
                        consecutive_429_count = 0
                        time.sleep(PAUSE_BETWEEN_CALLS)
                        return
                    except Exception as e:
                        logger.error(f"Último intento falló: {e}")
                        print(f"  Último intento falló: {e}")
                        raise
                raise
            backoff_sleep(i)
        except (ConnectionError, Timeout, RequestException) as e:
            # Errores de conexión/red
            consecutive_429_count = 0
            logger.warning(f"Error de conexión/red en build_payload(): {e} (intento {i+1}/{MAX_RETRIES})")
            print(f"  Error de conexión en build_payload(): {e} (intento {i+1}/{MAX_RETRIES})")
            if i == MAX_RETRIES - 1:
                logger.error("Máximo de reintentos alcanzado por error de conexión")
                raise
            # Esperar más tiempo para errores de conexión
            time.sleep(BASE_SLEEP_SECONDS * 2)
            backoff_sleep(i)
        except Exception as e:
            # Reset contador si es otro tipo de error
            consecutive_429_count = 0
            logger.warning(f"Error en build_payload(): {e} (intento {i+1}/{MAX_RETRIES})")
            print(f"  Error en build_payload(): {e} (intento {i+1}/{MAX_RETRIES})")
            if i == MAX_RETRIES - 1:
                logger.error(f"Error no recuperable en build_payload: {e}")
                raise
            backoff_sleep(i)


def safe_interest_over_time():
    """
    Wrapper con reintentos alrededor de interest_over_time.
    Maneja errores de conexión, timeout y rate limiting.
    Retorna DataFrame con columna 'date' (resetea índice si viene como índice).
    """
    global pytrends, consecutive_429_count
    
    for i in range(MAX_RETRIES):
        try:
            df = pytrends.interest_over_time()
            
            # Validar que el DataFrame tenga datos
            if df is None:
                logger.warning("interest_over_time() retornó None")
                if i == MAX_RETRIES - 1:
                    return pd.DataFrame()  # Retornar DataFrame vacío en lugar de fallar
                backoff_sleep(i)
                continue
            
            # pytrends retorna el DataFrame con fechas como índice (DatetimeIndex), no como columna
            # Resetear índice para convertir las fechas en una columna llamada 'date'
            if isinstance(df.index, pd.DatetimeIndex):
                df = df.reset_index()
                # El índice reseteado generalmente se convierte en la primera columna
                # Renombrar la primera columna a 'date' si no se llama así ya
                if len(df.columns) > 0 and df.columns[0] != 'date':
                    # Verificar si la primera columna es de tipo fecha
                    if pd.api.types.is_datetime64_any_dtype(df[df.columns[0]]):
                        df = df.rename(columns={df.columns[0]: 'date'})
                    else:
                        # Si no es fecha, puede que el índice no se haya reseteado correctamente
                        # Intentar crear columna 'date' desde el índice original
                        logger.warning(f"Primera columna después de reset_index no es fecha: {df.columns[0]}")
            
            # Eliminar columna 'isPartial' si existe (pytrends la incluye)
            if 'isPartial' in df.columns:
                df = df.drop(columns=['isPartial'])
            if 'isPartial' in df.index.names:
                df = df.reset_index(drop=True)
            
            # Si llegamos aquí, la solicitud fue exitosa
            consecutive_429_count = 0
            time.sleep(PAUSE_BETWEEN_CALLS)
            return df
        except TooManyRequestsError as e:
            consecutive_429_count += 1
            logger.warning(f"TooManyRequestsError en interest_over_time() (intento {i+1}/{MAX_RETRIES})")
            print(f"  TooManyRequestsError en interest_over_time() (intento {i+1}/{MAX_RETRIES})")
            
            # Si hay muchos 429 consecutivos, esperar mucho tiempo
            if consecutive_429_count >= 3:
                wait_if_blocked(consecutive_429_count)
                consecutive_429_count = 0  # Reset después de esperar
            
            if i == MAX_RETRIES - 1:
                logger.error("Máximo de reintentos alcanzado en interest_over_time")
                print("  Máximo de reintentos alcanzado en interest_over_time.")
                # En lugar de abortar inmediatamente, esperar y reintentar una vez más
                if consecutive_429_count < 3:
                    print("  Esperando tiempo adicional antes de fallar definitivamente...")
                    wait_if_blocked(consecutive_429_count)
                    # Último intento
                    try:
                        pytrends = make_pytrends()
                        time.sleep(10)
                        df = pytrends.interest_over_time()
                        # Resetear índice si es necesario (pytrends usa índice de fecha)
                        if df is not None and isinstance(df.index, pd.DatetimeIndex):
                            df = df.reset_index()
                            if len(df.columns) > 0 and df.columns[0] != 'date':
                                if pd.api.types.is_datetime64_any_dtype(df[df.columns[0]]):
                                    df = df.rename(columns={df.columns[0]: 'date'})
                        if df is not None and 'isPartial' in df.columns:
                            df = df.drop(columns=['isPartial'])
                        consecutive_429_count = 0
                        time.sleep(PAUSE_BETWEEN_CALLS)
                        return df if df is not None else pd.DataFrame()
                    except Exception as e:
                        logger.error(f"Último intento falló: {e}")
                        print(f"  Último intento falló: {e}")
                        # Retornar DataFrame vacío en lugar de fallar
                        return pd.DataFrame()
                # Retornar DataFrame vacío en lugar de fallar
                return pd.DataFrame()
            backoff_sleep(i)
        except (ConnectionError, Timeout, RequestException) as e:
            # Errores de conexión/red
            consecutive_429_count = 0
            logger.warning(f"Error de conexión/red en interest_over_time(): {e} (intento {i+1}/{MAX_RETRIES})")
            print(f"  Error de conexión en interest_over_time(): {e} (intento {i+1}/{MAX_RETRIES})")
            if i == MAX_RETRIES - 1:
                logger.error("Máximo de reintentos alcanzado por error de conexión")
                # Retornar DataFrame vacío en lugar de fallar
                return pd.DataFrame()
            # Esperar más tiempo para errores de conexión
            time.sleep(BASE_SLEEP_SECONDS * 2)
            backoff_sleep(i)
        except Exception as e:
            # Reset contador si es otro tipo de error
            consecutive_429_count = 0
            logger.warning(f"Error en interest_over_time(): {e} (intento {i+1}/{MAX_RETRIES})")
            print(f"  Error en interest_over_time(): {e} (intento {i+1}/{MAX_RETRIES})")
            if i == MAX_RETRIES - 1:
                logger.error(f"Error no recuperable en interest_over_time: {e}")
                # Retornar DataFrame vacío en lugar de fallar
                return pd.DataFrame()
            backoff_sleep(i)
    
    # Si llegamos aquí, retornar DataFrame vacío
    return pd.DataFrame()


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
    Maneja errores por candidato y continúa con los siguientes.
    """
    today = date.today()
    start = today - timedelta(days=DAYS_BACK)
    timeframe = f"{start} {today}"

    print(f"Descargando Google Trends para {len(CANDIDATES)} candidatos")
    print(f"Timeframe: {timeframe} (últimos {DAYS_BACK} días)\n")

    frames = []
    candidate_list = list(CANDIDATES.items())
    
    for idx, (cname, aliases) in enumerate(candidate_list, 1):
        print(f"\n[{idx}/{len(candidate_list)}] → Candidato: {cname}")
        
        # Pausa entre candidatos (excepto el primero)
        if idx > 1:
            print(f"  Esperando {PAUSE_BETWEEN_CANDIDATES}s antes de procesar siguiente candidato...")
            time.sleep(PAUSE_BETWEEN_CANDIDATES)
        
        try:
            # Si hay más de 5 alias, trocear en batches de 5 (límite Trends)
            alias_batches = [aliases[i:i + 5] for i in range(0, len(aliases), 5)]

            alias_series = []
            for batch_idx, batch in enumerate(alias_batches, 1):
                print(f"   - Batch {batch_idx}/{len(alias_batches)} aliases: {batch}")
                try:
                    safe_build_payload(
                        kw_list=batch,
                        timeframe=timeframe,
                        cat=CAT,
                        geo=GEO,
                        gprop=GPROP,
                    )
                    df = safe_interest_over_time()
                    if df is None or df.empty:
                        logger.warning(f"Sin datos para batch: {batch}")
                        print("     (sin datos en este batch)")
                        continue

                    # Validar DataFrame antes de procesar
                    is_valid, error_msg = validate_dataframe(df)
                    if not is_valid:
                        logger.warning(f"DataFrame inválido para batch {batch}: {error_msg}")
                        print(f"     ⚠ Datos inválidos: {error_msg}")
                        continue

                    # Asegurar que 'date' está como columna (pytrends la retorna como índice)
                    if isinstance(df.index, pd.DatetimeIndex):
                        df = df.reset_index()
                        if len(df.columns) > 0 and df.columns[0] != 'date':
                            if pd.api.types.is_datetime64_any_dtype(df[df.columns[0]]):
                                df = df.rename(columns={df.columns[0]: 'date'})
                    
                    # Quitar columna isPartial si viene
                    df = df.drop(columns=[c for c in df.columns if c.lower() == "ispartial"],
                                 errors="ignore")
                    alias_series.append(df)
                    print(f"     ✓ Datos obtenidos: {len(df)} días")
                    logger.info(f"Datos obtenidos para batch {batch}: {len(df)} días")
                except Exception as e:
                    logger.error(f"Error procesando batch {batch}: {e}")
                    print(f"     ✗ Error procesando batch: {e}")
                    # Continuar con siguiente batch en lugar de fallar todo
                    continue

            if not alias_series:
                print(f"   ⚠ No se obtuvieron datos para {cname}")
                continue

            # Asegurar que todos los DataFrames tengan 'date' como columna y como índice para merge
            for i, df_alias in enumerate(alias_series):
                if 'date' not in df_alias.columns:
                    if isinstance(df_alias.index, pd.DatetimeIndex):
                        df_alias = df_alias.reset_index()
                        if len(df_alias.columns) > 0:
                            first_col = df_alias.columns[0]
                            if pd.api.types.is_datetime64_any_dtype(df_alias[first_col]):
                                df_alias = df_alias.rename(columns={first_col: 'date'})
                            else:
                                # Crear columna date desde el índice si todavía no existe
                                df_alias['date'] = df_alias.index
                    alias_series[i] = df_alias
            
            # Combinar alias usando 'date' como clave de unión
            merged = alias_series[0].copy()
            for df_alias in alias_series[1:]:
                # Hacer merge por fecha
                merged = pd.merge(merged, df_alias, on='date', how='outer', suffixes=('', '_new'))
            
            # Convertir fechas a formato date si no lo están
            if 'date' in merged.columns:
                merged['date'] = pd.to_datetime(merged['date']).dt.date
            
            # Seleccionar solo columnas numéricas (excluyendo 'date' e 'isPartial')
            numeric_cols = [c for c in merged.columns if c != 'date' and c.lower() != 'ispartial' and pd.api.types.is_numeric_dtype(merged[c])]
            
            if not numeric_cols:
                logger.warning(f"No hay columnas numéricas para combinar en {cname}")
                continue
            
            # Crear columna única por candidato: máximo diario entre alias
            merged[cname] = merged[numeric_cols].max(axis=1)

            # Guardar solo la serie del candidato con fecha
            result_df = merged[['date', cname]].copy()
            frames.append(result_df)
            print(f"   ✓ {cname} completado exitosamente")
            
        except Exception as e:
            logger.error(f"Error crítico procesando {cname}: {e}")
            print(f"   ✗ Error crítico procesando {cname}: {e}")
            print(f"   Continuando con siguiente candidato...")
            continue

    if not frames:
        print("\n⚠ No se obtuvieron datos para ningún candidato.")
        return pd.DataFrame()

    # Combinar todos los frames por fecha usando merge
    out = frames[0].copy()
    for df_frame in frames[1:]:
        out = pd.merge(out, df_frame, on='date', how='outer', suffixes=('', '_new'))
    
    # Asegurar formato de fecha
    out["date"] = pd.to_datetime(out["date"]).dt.date
    
    # Ordenar por fecha
    out = out.sort_values("date").reset_index(drop=True)
    
    # Rellenar valores faltantes con 0 para columnas numéricas
    numeric_cols = out.select_dtypes(include=['number']).columns
    out[numeric_cols] = out[numeric_cols].fillna(0)
    
    # Ordenar columnas: date + candidatos en orden definido
    cols = ["date"] + list(CANDIDATES.keys())
    # Mantener solo columnas que existen
    available_cols = [c for c in cols if c in out.columns]
    extra_cols = [c for c in out.columns if c not in cols]
    out = out.reindex(columns=available_cols + extra_cols)

    return out


# ----------------- Main: unir con CSV histórico -----------------
def main():
    global consecutive_429_count
    
    try:
        # Reset contador de 429
        consecutive_429_count = 0
        
        # 1) Descarga últimos 90 días
        print("=" * 60)
        print("INICIANDO DESCARGA DE GOOGLE TRENDS")
        print("=" * 60)
        
        # Pausa inicial para evitar bloqueos inmediatos
        if INITIAL_DELAY > 0:
            print(f"\n⏳ Esperando {INITIAL_DELAY}s antes de comenzar (pausa inicial)...")
            time.sleep(INITIAL_DELAY)
            print("✓ Iniciando descarga...\n")
        
        df90 = fetch_last_90_days()
        
        if df90.empty:
            print("\n⚠ No hay datos nuevos que unir.")
            return

        print(f"\n✓ Descarga completada: {len(df90)} días de datos")
        print(f"  Candidatos con datos: {sum(1 for col in df90.columns if col != 'date' and df90[col].sum() > 0)}/{len(CANDIDATES)}")

        # 2) Si existe el histórico, unir y sobrescribir fechas solapadas
        if OUT_CSV_DAILY.exists():
            print(f"\n📂 Leyendo histórico: {OUT_CSV_DAILY}")
            try:
                # Intentar leer con diferentes encodings
                hist = None
                for encoding in ['utf-8', 'latin-1', 'iso-8859-1']:
                    try:
                        hist = pd.read_csv(OUT_CSV_DAILY, parse_dates=["date"], encoding=encoding)
                        logger.info(f"Histórico leído con encoding: {encoding}")
                        break
                    except (UnicodeDecodeError, pd.errors.EmptyDataError) as e:
                        logger.warning(f"Error leyendo con encoding {encoding}: {e}")
                        continue
                
                if hist is None or hist.empty:
                    raise ValueError("No se pudo leer el histórico o está vacío")
                
                # Validar fechas
                try:
                    hist["date"] = pd.to_datetime(hist["date"], errors='coerce')
                    hist = hist.dropna(subset=['date'])  # Eliminar filas con fechas inválidas
                    hist["date"] = hist["date"].dt.date
                except Exception as e:
                    logger.error(f"Error procesando fechas del histórico: {e}")
                    raise
                
                hist = ensure_all_candidate_cols(hist)
                df90 = ensure_all_candidate_cols(df90)

                combo = pd.concat([hist, df90], ignore_index=True)
                # Ordenar y eliminar duplicados por fecha (dejando el último = datos nuevos)
                combo = combo.sort_values("date").drop_duplicates(subset=["date"], keep="last")
                print(f"  ✓ Histórico cargado: {len(hist)} días previos")
                logger.info(f"Histórico cargado: {len(hist)} días previos")
            except Exception as e:
                logger.error(f"Error leyendo histórico: {e}")
                print(f"  ⚠ Error leyendo histórico: {e}")
                print("  Continuando solo con datos nuevos...")
                combo = ensure_all_candidate_cols(df90)
        else:
            print("\n📝 No existe histórico previo. Creando uno nuevo.")
            logger.info("No existe histórico previo. Creando uno nuevo.")
            combo = ensure_all_candidate_cols(df90)

        # 3) Reordenar columnas: date + candidatos + cualquier extra
        cols = ["date"] + list(CANDIDATES.keys())
        extra = [c for c in combo.columns if c not in cols]
        combo = combo.reindex(columns=cols + extra)

        # 4) Guardar con validación
        print(f"\n💾 Guardando datos...")
        logger.info("Guardando datos...")
        if not safe_save_dataframe(combo, OUT_CSV_DAILY, OUT_PARQUET_DAILY):
            logger.error("Error guardando datos. Intentando guardar progreso parcial...")
            # Intentar guardar progreso parcial
            try:
                if not df90.empty:
                    safe_save_dataframe(df90, PARTIAL_SAVE_FILE, None)
                    logger.info(f"Progreso parcial guardado en: {PARTIAL_SAVE_FILE}")
                    print(f"⚠ Progreso parcial guardado en: {PARTIAL_SAVE_FILE}")
            except Exception as e:
                logger.error(f"Error guardando progreso parcial: {e}")
            raise Exception("Error guardando datos finales")
        
        print("\n" + "=" * 60)
        print("✓ ACTUALIZACIÓN COMPLETADA")
        print("=" * 60)
        print(f"📄 CSV diario: {OUT_CSV_DAILY}")
        print(f"📄 Parquet diario: {OUT_PARQUET_DAILY}")
        print(f"📅 Rango: {combo['date'].min()} → {combo['date'].max()} (n={len(combo)} días)")
        print("=" * 60 + "\n")
        print("Últimas 5 filas:")
        print(combo.tail())
        print()
        
    except KeyboardInterrupt:
        logger.warning("Interrupción del usuario (Ctrl+C)")
        print("\n\n⚠ Interrupción del usuario. Intentando guardar datos parciales...")
        try:
            # Intentar guardar progreso parcial si existe
            if 'df90' in locals() and not df90.empty:
                safe_save_dataframe(df90, PARTIAL_SAVE_FILE, None)
                print(f"✓ Datos parciales guardados en: {PARTIAL_SAVE_FILE}")
                logger.info(f"Datos parciales guardados: {PARTIAL_SAVE_FILE}")
        except Exception as save_error:
            logger.error(f"Error guardando datos parciales: {save_error}")
            print(f"✗ No se pudieron guardar datos parciales: {save_error}")
        raise
    except Exception as e:
        logger.error(f"Error crítico en main(): {e}")
        logger.error(traceback.format_exc())
        print(f"\n\n✗ Error crítico en main(): {e}")
        traceback.print_exc()
        
        # Intentar guardar progreso parcial
        try:
            if 'df90' in locals() and not df90.empty:
                logger.info("Intentando guardar progreso parcial...")
                safe_save_dataframe(df90, PARTIAL_SAVE_FILE, None)
                print(f"⚠ Datos parciales guardados en: {PARTIAL_SAVE_FILE}")
        except Exception as save_error:
            logger.error(f"Error guardando datos parciales: {save_error}")
        
        raise


if __name__ == "__main__":
    main()
