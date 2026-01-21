# =============================================================
# Script de Procesamiento de Datos del SERVEL
# =============================================================
# Procesa los datos del SERVEL y los guarda en formato optimizado
# para usar en la app Shiny
# =============================================================

rm(list = ls())
set.seed(123)

library(tidyverse)
library(here)
library(readr)

# =============================================================
# CONFIGURACIÓN
# =============================================================

# Rutas
SERVEL_DIR <- here("data", "servel")
OUT_DIR <- here("data", "processed", "servel")

if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# =============================================================
# FUNCIONES HELPER
# =============================================================

# Función para procesar datos del SERVEL (formato wide o long)
procesar_datos_servel <- function(df) {
  # Normalizar nombres de columnas
  names(df) <- tolower(names(df))
  
  # Buscar columna geográfica
  geo_col <- NULL
  if ("region" %in% names(df)) {
    geo_col <- "region"
  } else if (any(str_detect(names(df), "^región"))) {
    geo_col <- names(df)[str_detect(names(df), "^región")][1]
  } else if ("comuna" %in% names(df)) {
    geo_col <- "comuna"
  }
  
  if (is.null(geo_col)) {
    cat("⚠️ No se encontró columna geográfica (region/comuna)\n")
    return(NULL)
  }
  
  # Detectar si es formato wide (columnas por candidato) o long (columna candidato)
  if ("candidato" %in% names(df)) {
    # Formato long - ya está listo
    cat("✅ Formato long detectado\n")
    return(df)
  } else {
    # Formato wide - transformar a long
    candidatos_cols <- names(df)[!names(df) %in% c(geo_col, "total", "votos_total", "votos_totales")]
    
    if (length(candidatos_cols) == 0) {
      cat("⚠️ No se encontraron columnas de candidatos\n")
      return(NULL)
    }
    
    cat(sprintf("✅ Formato wide detectado: %d columnas de candidatos\n", length(candidatos_cols)))
    
    df_long <- df %>%
      pivot_longer(
        cols = all_of(candidatos_cols),
        names_to = "candidato_original",
        values_to = "porcentaje",
        values_drop_na = TRUE
      ) %>%
      mutate(
        candidato = case_when(
          str_detect(candidato_original, "(?i)kast|josé.*antonio|jose.*antonio") ~ "Kast",
          str_detect(candidato_original, "(?i)kaiser|johannes") ~ "Kaiser",
          str_detect(candidato_original, "(?i)matthei|evelyn") ~ "Matthei",
          str_detect(candidato_original, "(?i)jara|jeannette|jeanette") ~ "Jara",
          str_detect(candidato_original, "(?i)parisi|franco") ~ "Parisi",
          str_detect(candidato_original, "(?i)mayne|nicholls|sichel") ~ "Mayne_Nicholls",
          TRUE ~ candidato_original
        )
      ) %>%
      select(-candidato_original)
    
    # Renombrar columna geográfica a nombre estándar si es necesario
    if (geo_col != "region" && geo_col != "comuna") {
      if (str_detect(geo_col, "(?i)region")) {
        df_long <- df_long %>%
          rename(region = all_of(geo_col))
      } else if (str_detect(geo_col, "(?i)comuna")) {
        df_long <- df_long %>%
          rename(comuna = all_of(geo_col))
      }
    }
    
    return(df_long)
  }
}

# =============================================================
# CARGA Y PROCESAMIENTO
# =============================================================

cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("📊 PROCESAMIENTO DE DATOS DEL SERVEL\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Buscar archivos en data/servel/
if (!dir.exists(SERVEL_DIR)) {
  cat(sprintf("\n⚠️ Directorio %s no existe. Creándolo...\n", SERVEL_DIR))
  dir.create(SERVEL_DIR, recursive = TRUE)
  cat("   Coloca los archivos CSV del SERVEL en ese directorio\n")
} else {
  archivos <- list.files(SERVEL_DIR, pattern = "\\.csv$", full.names = TRUE)
  
  if (length(archivos) == 0) {
    cat(sprintf("\n⚠️ No se encontraron archivos CSV en %s\n", SERVEL_DIR))
    cat("   Buscando en trends como ejemplo...\n")
    
    # Fallback: usar datos de trends
    trends_path <- here("data", "trends", "series", "trends_candidatos_region.csv")
    if (file.exists(trends_path)) {
      cat(sprintf("   ✅ Encontrado: %s\n", basename(trends_path)))
      archivos <- trends_path
    }
  }
  
  if (length(archivos) > 0) {
    cat(sprintf("\n📂 Procesando %d archivo(s)...\n", length(archivos)))
    
    resultados <- list()
    
    for (i in seq_along(archivos)) {
      archivo <- archivos[i]
      cat(sprintf("\n   Archivo %d/%d: %s\n", i, length(archivos), basename(archivo)))
      
      tryCatch({
        df_raw <- read_csv(archivo, show_col_types = FALSE, locale = locale(encoding = "UTF-8"))
        cat(sprintf("      ✅ Cargado: %d filas, %d columnas\n", nrow(df_raw), ncol(df_raw)))
        
        df_procesado <- procesar_datos_servel(df_raw)
        
        if (!is.null(df_procesado) && nrow(df_procesado) > 0) {
          cat(sprintf("      ✅ Procesado: %d registros\n", nrow(df_procesado)))
          
          # Guardar archivo procesado
          nombre_base <- tools::file_path_sans_ext(basename(archivo))
          archivo_salida <- file.path(OUT_DIR, paste0(nombre_base, "_procesado.rds"))
          
          saveRDS(df_procesado, archivo_salida)
          cat(sprintf("      💾 Guardado en: %s\n", archivo_salida))
          
          resultados[[i]] <- df_procesado
        } else {
          cat("      ❌ Error al procesar\n")
        }
      }, error = function(e) {
        cat(sprintf("      ❌ Error: %s\n", e$message))
      })
    }
    
    # Consolidar todos los resultados en un solo dataframe
    if (length(resultados) > 0) {
      cat("\n📊 Consolidando resultados...\n")
      
      df_consolidado <- bind_rows(resultados) %>%
        arrange(across(any_of(c("region", "comuna", "candidato"))))
      
      # Separar datos regionales y comunales
      if ("comuna" %in% names(df_consolidado)) {
        df_regional <- df_consolidado %>%
          filter(is.na(comuna) | comuna == "") %>%
          select(-comuna)
        
        df_comunal <- df_consolidado %>%
          filter(!is.na(comuna) & comuna != "")
        
        if (nrow(df_regional) > 0) {
          saveRDS(df_regional, file.path(OUT_DIR, "servel_regional.rds"))
          cat(sprintf("   ✅ Datos regionales: %d registros\n", nrow(df_regional)))
        }
        
        if (nrow(df_comunal) > 0) {
          saveRDS(df_comunal, file.path(OUT_DIR, "servel_comunal.rds"))
          cat(sprintf("   ✅ Datos comunales: %d registros\n", nrow(df_comunal)))
        }
      } else {
        # Solo datos regionales
        saveRDS(df_consolidado, file.path(OUT_DIR, "servel_regional.rds"))
        cat(sprintf("   ✅ Datos regionales: %d registros\n", nrow(df_consolidado)))
      }
      
      # Guardar también en CSV para fácil inspección
      write_csv(df_consolidado, file.path(OUT_DIR, "servel_consolidado.csv"))
      cat(sprintf("   💾 CSV consolidado guardado\n"))
      
      cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
      cat("✅ PROCESAMIENTO COMPLETADO\n")
      cat(paste0(rep("=", 70), collapse = ""), "\n")
      cat(sprintf("\n📁 Archivos guardados en: %s\n", OUT_DIR))
    }
  }
}











