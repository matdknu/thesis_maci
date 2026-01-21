# =============================================================
# Script R para copiar datos a shiny_app antes de desplegar
# Ejecutar: source("shiny_app/copiar_datos.R")
# =============================================================

cat("📦 Copiando datos a shiny_app para despliegue...\n\n")

# Crear directorios
dir.create("shiny_app/data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("shiny_app/data/servel", recursive = TRUE, showWarnings = FALSE)

# Copiar datos principales
archivo_reddit <- "data/processed/reddit_filtrado.rds"
if (file.exists(archivo_reddit)) {
  file.copy(archivo_reddit, "shiny_app/data/processed/reddit_filtrado.rds", overwrite = TRUE)
  size_mb <- file.info(archivo_reddit)$size / (1024^2)
  cat(sprintf("✅ reddit_filtrado.rds copiado (%.1f MB)\n", size_mb))
} else {
  cat("⚠️ reddit_filtrado.rds no encontrado\n")
}

# Copiar datos de ideología si existen
dir_ideologia <- "data/processed/imputacion_ideologia"
if (dir.exists(dir_ideologia)) {
  file.copy(dir_ideologia, "shiny_app/data/processed/", recursive = TRUE, overwrite = TRUE)
  cat("✅ Datos de ideología copiados\n")
}

# Copiar datos SERVEL si existen
dir_servel <- "data/servel"
if (dir.exists(dir_servel)) {
  archivos_servel <- list.files(dir_servel, full.names = TRUE, recursive = TRUE)
  if (length(archivos_servel) > 0) {
    file.copy(archivos_servel, "shiny_app/data/servel/", recursive = TRUE, overwrite = TRUE)
    cat("✅ Datos SERVEL copiados\n")
  }
}

# Resumen
cat("\n✅ Proceso completado. Los datos están en shiny_app/data/\n")
if (dir.exists("shiny_app/data")) {
  total_size <- sum(file.info(list.files("shiny_app/data", recursive = TRUE, full.names = TRUE))$size, na.rm = TRUE)
  cat(sprintf("📊 Tamaño total: %.1f MB\n", total_size / (1024^2)))
}

cat("\n💡 Ahora puedes desplegar la app con:\n")
cat("   rsconnect::deployApp('shiny_app')\n")
cat("   O desde RStudio: Publish > Deploy Application\n")










