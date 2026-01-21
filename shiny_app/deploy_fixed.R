# =============================================================
# Script de despliegue con configuración SSL corregida
# =============================================================

library(rsconnect)

# Configurar opciones SSL antes del despliegue
options(
  rsconnect.http = "libcurl",
  rsconnect.http.libcurl = TRUE,
  rsconnect.check.certificate = FALSE  # Solo si es absolutamente necesario
)

# Configurar variables de entorno
Sys.setenv(
  CURL_CA_BUNDLE = "",
  SSL_CERT_FILE = ""
)

# Directorio de la app
app_dir <- here::here("shiny_app")

# Verificar que existe app.R
if (!file.exists(file.path(app_dir, "app.R"))) {
  stop("No se encontró app.R en ", app_dir)
}

cat("🚀 Iniciando despliegue con configuración SSL corregida...\n")
cat("   Directorio:", app_dir, "\n")

# Intentar despliegue
tryCatch({
  deployApp(
    appDir = app_dir,
    appName = "reddit-politico-chile",  # Cambia esto por el nombre que quieras
    account = NULL,  # Se usará la cuenta por defecto, o especifica: account = "tu_cuenta"
    forceUpdate = TRUE,
    launch.browser = TRUE
  )
  cat("\n✅ Despliegue exitoso!\n")
}, error = function(e) {
  cat("\n❌ Error en despliegue:\n")
  cat("   ", e$message, "\n\n")
  cat("💡 SOLUCIONES ALTERNATIVAS:\n")
  cat("   1. Actualiza curl: brew upgrade curl (macOS)\n")
  cat("   2. Actualiza R: updateR() o reinstala R\n")
  cat("   3. Usa RStudio: Tools > Global Options > Publishing > Deploy\n")
  cat("   4. Prueba desde terminal: Rscript deploy_fixed.R\n")
})










