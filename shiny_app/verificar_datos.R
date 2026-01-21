# =============================================================
# Script para verificar que los datos están en su lugar
# Ejecutar: source("shiny_app/verificar_datos.R")
# =============================================================

cat("🔍 VERIFICANDO DATOS EN SHINY_APP...\n\n")

# Verificar estructura
app_dir <- "shiny_app"
data_dir <- file.path(app_dir, "data", "processed")

cat("📂 Estructura de directorios:\n")
cat("   App dir:", app_dir, "\n")
cat("   Data dir:", data_dir, "\n\n")

# Verificar archivo principal
archivo_principal <- file.path(data_dir, "reddit_filtrado.rds")
if (file.exists(archivo_principal)) {
  size_mb <- file.info(archivo_principal)$size / (1024^2)
  cat("✅ reddit_filtrado.rds encontrado\n")
  cat("   Ruta:", archivo_principal, "\n")
  cat("   Tamaño:", sprintf("%.1f MB", size_mb), "\n")
  
  # Intentar cargar
  tryCatch({
    df_test <- readRDS(archivo_principal)
    cat("   Filas:", nrow(df_test), "\n")
    cat("   Columnas:", ncol(df_test), "\n")
    cat("   ✅ Archivo se puede leer correctamente\n")
  }, error = function(e) {
    cat("   ❌ Error al leer:", e$message, "\n")
  })
} else {
  cat("❌ reddit_filtrado.rds NO encontrado en:", archivo_principal, "\n")
}

cat("\n")

# Verificar datos de ideología
ideologia_dir <- file.path(data_dir, "imputacion_ideologia")
if (dir.exists(ideologia_dir)) {
  cat("✅ Directorio de ideología encontrado\n")
  archivos_ideologia <- list.files(ideologia_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(archivos_ideologia) > 0) {
    cat("   Archivos CSV:", length(archivos_ideologia), "\n")
    for (archivo in archivos_ideologia) {
      cat("   -", basename(archivo), "\n")
    }
  }
} else {
  cat("⚠️ Directorio de ideología no encontrado (opcional)\n")
}

cat("\n")

# Verificar datos SERVEL
servel_dir <- file.path(app_dir, "data", "servel")
if (dir.exists(servel_dir)) {
  cat("✅ Directorio SERVEL encontrado\n")
  archivos_servel <- list.files(servel_dir, recursive = TRUE)
  if (length(archivos_servel) > 0) {
    cat("   Archivos:", length(archivos_servel), "\n")
  }
} else {
  cat("⚠️ Directorio SERVEL no encontrado (opcional)\n")
}

cat("\n")

# Resumen de tamaño
if (dir.exists(file.path(app_dir, "data"))) {
  total_size <- sum(file.info(list.files(file.path(app_dir, "data"), 
                                         recursive = TRUE, 
                                         full.names = TRUE))$size, na.rm = TRUE)
  cat("📊 Tamaño total de datos:", sprintf("%.1f MB", total_size / (1024^2)), "\n")
}

cat("\n✅ Verificación completada\n")
cat("\n💡 Si todos los datos están presentes, puedes desplegar la app.\n")










