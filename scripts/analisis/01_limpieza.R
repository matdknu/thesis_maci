# =============================================================
# 01 — Limpieza de datos (filtrado y preparación común del corpus)
# La implementación principal está en scripts/procesamiento/
# =============================================================

pacman::p_load(here)

source(here::here("scripts/procesamiento/01_filtrar_data.R"), encoding = "UTF-8")
