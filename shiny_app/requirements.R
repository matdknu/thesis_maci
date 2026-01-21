# =============================================================
# Dependencias de R para la Shiny App
# =============================================================
# Instalar con: install.packages(c(...))

required_packages <- c(
  "shiny",           # Framework principal
  "shinydashboard",  # Dashboard UI
  "shinyWidgets",    # Widgets adicionales
  "tidyverse",       # Manipulación de datos
  "lubridate",       # Fechas
  "plotly",          # Gráficos interactivos
  "DT",              # Tablas interactivas
  "here",            # Rutas relativas
  "leaflet"          # Mapas interactivos
)

# Instalar si no están instaladas
install_if_missing <- function(pkg) {
  if (!require(pkg, character.only = TRUE)) {
    install.packages(pkg, dependencies = TRUE)
    library(pkg, character.only = TRUE)
  }
}

cat("Instalando/verificando paquetes necesarios...\n")
for (pkg in required_packages) {
  install_if_missing(pkg)
}

cat("\n✅ Todos los paquetes están instalados.\n")
cat("\nPara ejecutar la app:\n")
cat("  library(shiny)\n")
cat("  runApp('shiny_app')\n")

