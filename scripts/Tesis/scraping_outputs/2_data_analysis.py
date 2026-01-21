# Análisis de datos
import os
import time
import hashlib
from datetime import datetime

import pandas as pd
import praw
from prawcore.exceptions import RequestException, ResponseException, ServerError, Forbidden, NotFound
import csv
import pyreadr

# Ver directorio actual
print(os.getcwd())


# Si el archivo está en el directorio actual

rds_path = os.path.join("data", "proc_data", "reddit_filtrado.rds")
rds_result = pyreadr.read_r(rds_path)
df = next(iter(rds_result.values()))  # primer objeto dentro del .rds


# Ver las primeras filas
print(df.head())

# --- Depuración de texto en el DataFrame ---

import re

def clean_text(text):
    """
    Limpia el texto:
    - Elimina saltos de línea/carriage return dobles/redundantes
    - Reemplaza múltiples espacios por uno solo
    - Elimina espacios antes/después
    - Elimina caracteres no imprimibles salvo tabulación y salto de línea
    - Homogeniza unicode (opcional, aquí no incluimos normalización por simplicidad)
    """
    if pd.isnull(text):
        return text
    if not isinstance(text, str):
        text = str(text)
    # Elimina caracteres no imprimibles (excepto tab/newline/carriage)
    text = re.sub(r"[\x00-\x08\x0B-\x0C\x0E-\x1F]", "", text)
    # Reemplaza saltos de línea/carriage múltiple por uno solo
    text = re.sub(r"[\r\n]+", "\n", text)
    # Reemplaza múltiples espacios por uno solo
    text = re.sub(r"[ ]+", " ", text)
    # Quita espacios al inicio/fin de cada línea
    text = "\n".join([line.strip() for line in text.splitlines()])
    # Quita espacios al inicio/fin del texto
    text = text.strip()
    return text

#
