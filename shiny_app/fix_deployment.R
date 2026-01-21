# =============================================================
# Script para solucionar problemas de SSL/TLS al desplegar en shinyapps.io
# =============================================================

# Solución 1: Actualizar paquetes relacionados con SSL
cat("🔧 SOLUCIÓN 1: Actualizando paquetes SSL...\n")
update.packages(c("curl", "httr", "rsconnect"), ask = FALSE)

# Solución 2: Configurar opciones de curl
cat("\n🔧 SOLUCIÓN 2: Configurando opciones de curl...\n")
options(
  rsconnect.http = "libcurl",
  rsconnect.http.libcurl = TRUE
)

# Solución 3: Verificar y configurar certificados
cat("\n🔧 SOLUCIÓN 3: Verificando certificados SSL...\n")

# En macOS, actualizar certificados
if (Sys.info()["sysname"] == "Darwin") {
  cat("   Sistema: macOS\n")
  cat("   Ejecuta en terminal:\n")
  cat("   brew install ca-certificates\n")
  cat("   O actualiza curl: brew upgrade curl\n")
}

# Solución 4: Configurar variables de entorno
cat("\n🔧 SOLUCIÓN 4: Configurando variables de entorno...\n")
Sys.setenv(
  CURL_CA_BUNDLE = "",
  SSL_CERT_FILE = "",
  CURLOPT_SSL_VERIFYPEER = "1"
)

# Solución 5: Probar conexión
cat("\n🔧 SOLUCIÓN 5: Probando conexión...\n")
tryCatch({
  test_url <- "https://api.shinyapps.io"
  response <- httr::GET(test_url, config = httr::config(ssl_verifypeer = TRUE))
  cat("   ✅ Conexión exitosa\n")
}, error = function(e) {
  cat("   ⚠️ Error de conexión:", e$message, "\n")
  cat("   Intenta las soluciones manuales abajo\n")
})

cat("\n" , paste0(rep("=", 70), collapse = ""), "\n")
cat("📋 SOLUCIONES MANUALES:\n")
cat(paste0(rep("=", 70), collapse = ""), "\n\n")

cat("1. Actualizar R y paquetes:\n")
cat("   update.packages(ask = FALSE)\n")
cat("   install.packages(c('curl', 'httr', 'rsconnect'), dependencies = TRUE)\n\n")

cat("2. En macOS, actualizar certificados:\n")
cat("   brew install ca-certificates\n")
cat("   brew upgrade curl\n\n")

cat("3. Configurar rsconnect con opciones SSL:\n")
cat("   library(rsconnect)\n")
cat("   options(rsconnect.http = 'libcurl')\n")
cat("   deployApp(appDir = 'shiny_app', account = 'tu_cuenta')\n\n")

cat("4. Si persiste, usar método alternativo:\n")
cat("   - Despliega desde RStudio (menú: Publish > Deploy Application)\n")
cat("   - O usa: rsconnect::deployApp() con forceUpdate = TRUE\n\n")

cat("5. Verificar versión de curl:\n")
cat("   system('curl --version')\n\n")

cat("6. Si nada funciona, reinstalar rsconnect:\n")
cat("   remove.packages('rsconnect')\n")
cat("   install.packages('rsconnect', repos = 'https://cran.rstudio.com/')\n\n")

cat("✅ Script completado. Prueba las soluciones arriba.\n")










