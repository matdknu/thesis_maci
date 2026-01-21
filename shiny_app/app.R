# =============================================================
# Shiny App - Análisis Interactivo de Reddit Político
# =============================================================
# App interactiva para visualizar eventos, frames y emergencia
# de personajes políticos en Reddit
# =============================================================

# Cargar librerías
library(shiny)
library(shinydashboard)
library(shinyWidgets)
library(tidyverse)
library(lubridate)
library(plotly)
library(DT)
library(here)
library(leaflet)

# =============================================================
# CONFIGURACIÓN
# =============================================================

# Rutas - Compatible con shinyapps.io
# PRIORIDAD: 1) Dentro de shiny_app/data, 2) Fuera de shiny_app, 3) here()
get_data_path <- function(...) {
  # PRIORIDAD 1: Buscar dentro del directorio de la app (para producción)
  app_dir <- getwd()
  if (basename(app_dir) != "shiny_app") {
    # Si estamos en el directorio raíz, ir a shiny_app
    app_dir <- file.path(app_dir, "shiny_app")
  }
  
  # Buscar primero dentro de shiny_app/data
  path_local <- file.path(app_dir, ...)
  if (file.exists(path_local)) {
    cat("✅ Datos encontrados en:", path_local, "\n")
    return(path_local)
  }
  
  # PRIORIDAD 2: Buscar fuera de shiny_app (desarrollo local)
  path_parent <- file.path(app_dir, "..", ...)
  path_parent <- normalizePath(path_parent, mustWork = FALSE)
  if (file.exists(path_parent)) {
    cat("✅ Datos encontrados en:", path_parent, "\n")
    return(path_parent)
  }
  
  # PRIORIDAD 3: Intentar con here() (último recurso)
  tryCatch({
    path_here <- here(...)
    if (file.exists(path_here)) {
      cat("✅ Datos encontrados en:", path_here, "\n")
      return(path_here)
    }
  }, error = function(e) NULL)
  
  # Si no se encuentra, devolver la ruta local (para mensajes de error)
  return(path_local)
}

DATA_DIR <- get_data_path("data", "processed")
IMAGES_DIR <- file.path("www", "images")

# Crear directorio de imágenes si no existe
if (!dir.exists(IMAGES_DIR)) {
  dir.create(IMAGES_DIR, recursive = TRUE)
}

# Cargar datos con mejor manejo de errores
df_reddit <- NULL
menciones_fecha <- NULL
totales_candidatos <- NULL

tryCatch({
  # PRIORIDAD: Buscar primero en shiny_app/data (para producción en shinyapps.io)
  app_dir <- getwd()
  if (basename(app_dir) != "shiny_app") {
    app_dir <- file.path(app_dir, "shiny_app")
  }
  
  # Lista de rutas a intentar (en orden de prioridad)
  rutas_posibles <- c(
    file.path(app_dir, "data", "processed", "reddit_filtrado.rds"),  # 1. Local shiny_app/data (PRODUCCIÓN)
    file.path(DATA_DIR, "reddit_filtrado.rds"),                        # 2. DATA_DIR calculado
    file.path(app_dir, "..", "data", "processed", "reddit_filtrado.rds") # 3. Parent directory (desarrollo)
  )
  
  data_file <- NULL
  for (ruta in rutas_posibles) {
    if (file.exists(ruta)) {
      data_file <- ruta
      cat("📂 Datos encontrados en:", ruta, "\n")
      break
    }
  }
  
  if (!is.null(data_file) && file.exists(data_file)) {
    df_reddit <- readRDS(data_file)
    cat("✅ Datos de Reddit cargados:", nrow(df_reddit), "filas\n")
    
    # Preparar datos para visualización
    menciones_fecha <- df_reddit %>%
      group_by(fecha) %>%
      summarise(
        Kast = sum(kast, na.rm = TRUE),
        Kaiser = sum(kaiser, na.rm = TRUE),
        Matthei = sum(matthei, na.rm = TRUE),
        Jara = sum(jara, na.rm = TRUE),
        Parisi = sum(parisi, na.rm = TRUE),
        Mayne_Nicholls = sum(mayne_nicholls, na.rm = TRUE),
        Total = n(),
        .groups = "drop"
      ) %>%
      pivot_longer(-c(fecha, Total), names_to = "candidato", values_to = "menciones") %>%
      filter(!is.na(fecha))
    
    # Totales por candidato
    totales_candidatos <- df_reddit %>%
      summarise(
        Kast = sum(kast, na.rm = TRUE),
        Kaiser = sum(kaiser, na.rm = TRUE),
        Matthei = sum(matthei, na.rm = TRUE),
        Jara = sum(jara, na.rm = TRUE),
        Parisi = sum(parisi, na.rm = TRUE),
        Mayne_Nicholls = sum(mayne_nicholls, na.rm = TRUE)
      ) %>%
      pivot_longer(everything(), names_to = "candidato", values_to = "total") %>%
      arrange(desc(total))
  } else {
    cat("⚠️ Archivo de datos no encontrado en ninguna de las rutas:\n")
    for (ruta in rutas_posibles) {
      cat("   -", ruta, "\n")
    }
  }
}, error = function(e) {
  cat("⚠️ Error cargando datos de Reddit:", e$message, "\n")
})

# Cargar datos de imputación de ideología si existen
tryCatch({
  # PRIORIDAD: Buscar primero en shiny_app/data
  app_dir <- getwd()
  if (basename(app_dir) != "shiny_app") {
    app_dir <- file.path(app_dir, "shiny_app")
  }
  
  rutas_ideologia <- c(
    file.path(app_dir, "data", "processed", "imputacion_ideologia"),  # 1. Local
    file.path(DATA_DIR, "imputacion_ideologia"),                      # 2. DATA_DIR
    file.path(app_dir, "..", "data", "processed", "imputacion_ideologia") # 3. Parent
  )
  
  ideologia_dir <- NULL
  for (ruta in rutas_ideologia) {
    if (dir.exists(ruta)) {
      ideologia_dir <- ruta
      cat("📂 Datos de ideología encontrados en:", ruta, "\n")
      break
    }
  }
  
  if (!is.null(ideologia_dir) && dir.exists(ideologia_dir)) {
    dirs <- list.dirs(ideologia_dir, full.names = TRUE, recursive = FALSE)
    if (length(dirs) > 0) {
      dirs_info <- file.info(dirs)
      dir_mas_reciente <- rownames(dirs_info)[which.max(dirs_info$mtime)]
      csv_files <- list.files(dir_mas_reciente, pattern = "imputacion.*\\.csv$", full.names = TRUE)
      if (length(csv_files) > 0) {
        df_ideologia <- read_csv(csv_files[1], show_col_types = FALSE)
        cat("✅ Datos de ideología cargados\n")
      } else {
        df_ideologia <- NULL
      }
    } else {
      df_ideologia <- NULL
    }
  } else {
    df_ideologia <- NULL
  }
}, error = function(e) {
  cat("⚠️ Datos de ideología no disponibles:", e$message, "\n")
  df_ideologia <- NULL
})

# Preparar datos para visualización
if (!is.null(df_reddit)) {
  # Menciones por fecha y candidato
  menciones_fecha <- df_reddit %>%
    group_by(fecha) %>%
    summarise(
      Kast = sum(kast, na.rm = TRUE),
      Kaiser = sum(kaiser, na.rm = TRUE),
      Matthei = sum(matthei, na.rm = TRUE),
      Jara = sum(jara, na.rm = TRUE),
      Parisi = sum(parisi, na.rm = TRUE),
      Mayne_Nicholls = sum(mayne_nicholls, na.rm = TRUE),
      Total = n(),
      .groups = "drop"
    ) %>%
    pivot_longer(-c(fecha, Total), names_to = "candidato", values_to = "menciones") %>%
    filter(!is.na(fecha))
  
  # Totales por candidato
  totales_candidatos <- df_reddit %>%
    summarise(
      Kast = sum(kast, na.rm = TRUE),
      Kaiser = sum(kaiser, na.rm = TRUE),
      Matthei = sum(matthei, na.rm = TRUE),
      Jara = sum(jara, na.rm = TRUE),
      Parisi = sum(parisi, na.rm = TRUE),
      Mayne_Nicholls = sum(mayne_nicholls, na.rm = TRUE)
    ) %>%
    pivot_longer(everything(), names_to = "candidato", values_to = "total") %>%
    arrange(desc(total))
}

# Información de personajes (con rutas de imágenes)
# Nota: Algunas imágenes pueden ser .jpg o .png - la función buscará ambas extensiones
personajes_info <- tibble(
  nombre = c("Kast", "Kaiser", "Matthei", "Jara", "Parisi", "Mayne_Nicholls"),
  nombre_completo = c("José Antonio Kast", "Johannes Kaiser", "Evelyn Matthei", 
                      "Jeannette Jara", "Franco Parisi", "Sebastián Sichel"),
  imagen_base = c("kast", "kaiser", "matthei", "jara", "parisi", "mayne_nicholls"),
  color = c("#3498db", "#27ae60", "#f1c40f", "#e74c3c", "#95a5a6", "#9b59b6")  # Kast: azul, Kaiser: verde, Matthei: amarillo, Jara: rojo, Parisi: gris, Mayne: morado
) %>%
  mutate(
    # Buscar imagen existente (.png o .jpg)
    # En shinyapps.io, las imágenes deben estar en www/images/
    imagen = map_chr(imagen_base, function(base) {
      # Rutas relativas desde www/ (estándar de Shiny)
      png_path <- file.path("www", "images", paste0(base, ".png"))
      jpg_path <- file.path("www", "images", paste0(base, ".jpg"))
      
      # También verificar ruta absoluta si existe IMAGES_DIR
      if (exists("IMAGES_DIR") && dir.exists(IMAGES_DIR)) {
        png_abs <- file.path(IMAGES_DIR, paste0(base, ".png"))
        jpg_abs <- file.path(IMAGES_DIR, paste0(base, ".jpg"))
        if (file.exists(png_abs)) return(paste0(base, ".png"))
        if (file.exists(jpg_abs)) return(paste0(base, ".jpg"))
      }
      
      # Verificar rutas relativas
      if (file.exists(png_path)) {
        return(paste0(base, ".png"))
      } else if (file.exists(jpg_path)) {
        return(paste0(base, ".jpg"))
      } else {
        return(paste0(base, ".png"))  # Default (aunque no exista)
      }
    })
  )

# =============================================================
# UI
# =============================================================

ui <- dashboardPage(
  skin = "red",
  
  # Header
  dashboardHeader(
    title = tags$span(
      tags$strong("Análisis Político Reddit"),
      style = "font-size: 20px; font-weight: 600; color: #ffffff;"
    ),
    titleWidth = 300,
    tags$li(
      class = "dropdown",
      tags$a(
        href = "#",
        icon("info-circle"),
        title = "Acerca de",
        style = "color: #ffffff; font-size: 18px; padding: 15px;"
      )
    )
  ),
  
  # Sidebar
  dashboardSidebar(
    width = 280,
    sidebarMenu(
      id = "sidebar_menu",
      menuItem("Bienvenida", tabName = "bienvenida", icon = icon("home"), selected = TRUE),
      menuItem("Dashboard", tabName = "dashboard", icon = icon("chart-line")),
      menuItem("Personajes", tabName = "personajes", icon = icon("user-tie")),
      menuItem("Eventos", tabName = "eventos", icon = icon("calendar-alt")),
      menuItem("Frames", tabName = "frames", icon = icon("tags")),
      menuItem("Ideología", tabName = "ideologia", icon = icon("balance-scale")),
      menuItem("Resultados Electorales", tabName = "resultados_servel", icon = icon("map")),
      menuItem("Datos", tabName = "datos", icon = icon("database")),
      br(),
      div(
        style = "padding: 15px; color: #95a5a6; font-size: 12px; border-top: 1px solid #34495e; margin-top: 20px;",
        tags$p(strong("Análisis de Discurso Político"), style = "color: #ecf0f1; margin-bottom: 5px;"),
        tags$p("Tesis de Maestría", style = "color: #bdc3c7; font-size: 11px;")
      )
    )
  ),
  
  # Body
  dashboardBody(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "images/custom.css"),
      tags$style(HTML("
        /* Tema general - Colores formales (rojo y grisáceo) */
        :root {
          --primary-red: #c0392b;
          --dark-red: #a93226;
          --light-red: #e74c3c;
          --dark-gray: #2c3e50;
          --medium-gray: #7f8c8d;
          --light-gray: #ecf0f1;
          --very-light-gray: #f8f9fa;
          --white: #ffffff;
        }
        
        /* Body y contenido */
        .content-wrapper {
          background: linear-gradient(135deg, #f8f9fa 0%, #ecf0f1 100%);
          min-height: 100vh;
        }
        
        .main-header {
          background: linear-gradient(135deg, var(--dark-red) 0%, var(--primary-red) 100%) !important;
          border-bottom: 3px solid var(--dark-red);
        }
        
        .main-header .logo {
          background: transparent !important;
          border-right: none !important;
        }
        
        /* Sidebar elegante */
        .sidebar {
          background-color: var(--dark-gray) !important;
        }
        
        .sidebar .sidebar-menu .treeview-menu > li > a {
          color: #bdc3c7;
        }
        
        .sidebar .sidebar-menu .treeview-menu > li.active > a {
          color: var(--primary-red);
          background-color: rgba(192, 57, 43, 0.1);
        }
        
        /* Menú items */
        .sidebar-menu > li > a {
          color: #ecf0f1 !important;
          border-left: 3px solid transparent;
          transition: all 0.3s ease;
          padding: 12px 20px !important;
        }
        
        .sidebar-menu > li > a:hover {
          background-color: #34495e !important;
          border-left-color: var(--primary-red);
          color: #ffffff !important;
        }
        
        .sidebar-menu > li.active > a {
          background-color: rgba(192, 57, 43, 0.15) !important;
          border-left-color: var(--primary-red) !important;
          color: #ffffff !important;
          font-weight: 600;
        }
        
        /* Boxes elegantes */
        .box {
          border-radius: 8px !important;
          box-shadow: 0 2px 8px rgba(0,0,0,0.1) !important;
          border-top: 3px solid var(--primary-red) !important;
          background: var(--white) !important;
          margin-bottom: 20px;
        }
        
        .box-header {
          background: linear-gradient(135deg, var(--very-light-gray) 0%, var(--white) 100%) !important;
          border-bottom: 1px solid #dee2e6 !important;
          padding: 15px 20px !important;
        }
        
        .box-title {
          font-weight: 600 !important;
          color: var(--dark-gray) !important;
          font-size: 16px !important;
        }
        
        /* Value boxes elegantes */
        .small-box {
          border-radius: 8px !important;
          box-shadow: 0 3px 10px rgba(0,0,0,0.15) !important;
          transition: transform 0.2s ease, box-shadow 0.2s ease;
        }
        
        .small-box:hover {
          transform: translateY(-3px);
          box-shadow: 0 5px 15px rgba(0,0,0,0.2) !important;
        }
        
        .small-box .inner h3 {
          font-weight: 600;
          font-size: 38px;
        }
        
        /* Botones elegantes */
        .btn {
          border-radius: 6px !important;
          padding: 8px 20px !important;
          font-weight: 500 !important;
          transition: all 0.3s ease !important;
          border: none !important;
          box-shadow: 0 2px 5px rgba(0,0,0,0.1) !important;
        }
        
        .btn-primary {
          background: linear-gradient(135deg, var(--primary-red) 0%, var(--light-red) 100%) !important;
          color: white !important;
        }
        
        .btn-primary:hover {
          background: linear-gradient(135deg, var(--dark-red) 0%, var(--primary-red) 100%) !important;
          box-shadow: 0 4px 10px rgba(192, 57, 43, 0.3) !important;
          transform: translateY(-1px);
        }
        
        .btn-info {
          background: linear-gradient(135deg, #3498db 0%, #2980b9 100%) !important;
          color: white !important;
        }
        
        .btn-info:hover {
          background: linear-gradient(135deg, #2980b9 0%, #1f6391 100%) !important;
          box-shadow: 0 4px 10px rgba(52, 152, 219, 0.3) !important;
        }
        
        .btn-success {
          background: linear-gradient(135deg, #27ae60 0%, #229954 100%) !important;
          color: white !important;
        }
        
        /* Personaje card elegante */
        .personaje-card { 
          text-align: center; 
          padding: 30px 20px;
          margin: 15px;
          background: linear-gradient(135deg, var(--white) 0%, var(--very-light-gray) 100%);
          border-radius: 12px;
          box-shadow: 0 4px 12px rgba(0,0,0,0.1);
          transition: transform 0.3s ease, box-shadow 0.3s ease;
          border: 1px solid #e0e0e0;
        }
        
        .personaje-card:hover {
          transform: translateY(-5px);
          box-shadow: 0 8px 20px rgba(0,0,0,0.15);
        }
        
        .personaje-img { 
          width: 180px; 
          height: 180px; 
          border-radius: 50%;
          object-fit: cover;
          border: 4px solid #e0e0e0;
          box-shadow: 0 4px 10px rgba(0,0,0,0.2);
          margin-bottom: 20px;
        }
        
        /* Página de bienvenida */
        .welcome-container {
          background: linear-gradient(135deg, var(--white) 0%, var(--very-light-gray) 100%);
          padding: 60px 40px;
          border-radius: 12px;
          box-shadow: 0 6px 20px rgba(0,0,0,0.1);
          text-align: center;
          margin: 40px auto;
          max-width: 900px;
        }
        
        .welcome-title {
          font-size: 42px;
          font-weight: 700;
          color: var(--dark-gray);
          margin-bottom: 20px;
          background: linear-gradient(135deg, var(--dark-red) 0%, var(--primary-red) 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
        }
        
        .welcome-subtitle {
          font-size: 20px;
          color: var(--medium-gray);
          margin-bottom: 40px;
          line-height: 1.6;
        }
        
        .welcome-features {
          display: flex;
          justify-content: space-around;
          flex-wrap: wrap;
          margin-top: 50px;
        }
        
        .feature-card {
          background: var(--white);
          padding: 30px;
          border-radius: 10px;
          box-shadow: 0 3px 10px rgba(0,0,0,0.08);
          margin: 15px;
          flex: 1;
          min-width: 200px;
          max-width: 250px;
          transition: transform 0.3s ease;
        }
        
        .feature-card:hover {
          transform: translateY(-5px);
        }
        
        .feature-icon {
          font-size: 48px;
          color: var(--primary-red);
          margin-bottom: 15px;
        }
        
        .feature-title {
          font-size: 18px;
          font-weight: 600;
          color: var(--dark-gray);
          margin-bottom: 10px;
        }
        
        .feature-text {
          font-size: 14px;
          color: var(--medium-gray);
          line-height: 1.5;
        }
        
        /* Inputs elegantes */
        .form-control, .selectize-input {
          border-radius: 6px !important;
          border: 2px solid #e0e0e0 !important;
          padding: 8px 12px !important;
          transition: border-color 0.3s ease !important;
        }
        
        .form-control:focus, .selectize-input.focus {
          border-color: var(--primary-red) !important;
          box-shadow: 0 0 0 0.2rem rgba(192, 57, 43, 0.15) !important;
        }
        
        /* Tablas elegantes */
        .dataTables_wrapper {
          background: var(--white);
          border-radius: 8px;
          padding: 20px;
          box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
      "))
    ),
    
    tabItems(
      
      # ===== BIENVENIDA =====
      tabItem(
        tabName = "bienvenida",
        div(
          class = "welcome-container",
          # Logo UDEC
          div(
            style = "text-align: center; margin-bottom: 30px;",
            tags$img(
              src = "images/udec_logo.png",
              alt = "Logo Universidad de Concepción",
              style = "max-width: 250px; height: auto; margin-bottom: 20px; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.1));",
              onerror = "this.style.display='none'"
            )
          ),
          div(
            class = "welcome-title",
            "Análisis Político de Reddit"
          ),
          div(
            class = "welcome-subtitle",
            tags$p("Visualización interactiva de discurso político en Reddit chileno"),
            tags$p("Explora menciones, eventos, frames discursivos e ideología de los principales candidatos presidenciales", 
                   style = "font-size: 16px; color: #7f8c8d; margin-top: 15px;")
          ),
          div(
            class = "welcome-features",
            div(
              class = "feature-card",
              div(class = "feature-icon", icon("chart-line")),
              div(class = "feature-title", "Dashboard Analítico"),
              div(class = "feature-text", "Estadísticas generales, evolución temporal y distribuciones")
            ),
            div(
              class = "feature-card",
              div(class = "feature-icon", icon("user-tie")),
              div(class = "feature-title", "Análisis por Personaje"),
              div(class = "feature-text", "Visualizaciones detalladas para cada candidato político")
            ),
            div(
              class = "feature-card",
              div(class = "feature-icon", icon("calendar-alt")),
              div(class = "feature-title", "Eventos Temporales"),
              div(class = "feature-text", "Identificación de picos y eventos relevantes en el tiempo")
            ),
            div(
              class = "feature-card",
              div(class = "feature-icon", icon("balance-scale")),
              div(class = "feature-title", "Ideología"),
              div(class = "feature-text", "Análisis de posicionamiento left-right mediante IA")
            )
          ),
          div(
            style = "margin-top: 50px; padding-top: 30px; border-top: 2px solid #e0e0e0;",
            tags$p(
              tags$strong("Datos:", style = "color: var(--dark-gray);"),
              tags$span(" Reddit (r/chile, r/RepublicadeChile)", style = "color: var(--medium-gray);")
            ),
            if (!is.null(df_reddit) && "fecha" %in% names(df_reddit)) {
              tags$p(
                tags$strong("Período:", style = "color: var(--dark-gray);"),
                tags$span(paste(" ", min(df_reddit$fecha, na.rm = TRUE), "a", max(df_reddit$fecha, na.rm = TRUE)), 
                         style = "color: var(--medium-gray);")
              )
            } else {
              tags$p(
                tags$strong("Período:", style = "color: var(--dark-gray);"),
                tags$span(" Datos no disponibles", style = "color: var(--medium-gray);")
              )
            },
            br(),
            actionButton("ir_dashboard", 
                        label = tags$span(icon("arrow-right"), " Comenzar Exploración"),
                        class = "btn btn-primary btn-lg",
                        style = "padding: 15px 40px; font-size: 18px; border-radius: 30px;")
          ),
          div(
            style = "margin-top: 60px; padding-top: 30px; border-top: 1px solid #e0e0e0; text-align: center;",
            tags$p(
              style = "color: #7f8c8d; font-size: 14px; line-height: 1.8; margin: 0;",
              "Desarrollado por",
              tags$br(),
              tags$strong("Matías Deneken", style = "color: #2c3e50; font-size: 16px;"),
              tags$br(),
              "Sociólogo | Mag. en Sociología | Mg. (c) en Ciencia de Datos"
            )
          )
        )
      ),
      
      # ===== DASHBOARD =====
      tabItem(
        tabName = "dashboard",
        fluidRow(
          column(12,
            h2("Dashboard General"),
            p("Visualización interactiva de datos políticos de Reddit")
          )
        ),
        fluidRow(
          valueBoxOutput("total_comentarios", width = 3),
          valueBoxOutput("total_menciones", width = 3),
          valueBoxOutput("periodo_dias", width = 3),
          valueBoxOutput("usuarios_unicos", width = 3)
        ),
        fluidRow(
          column(12,
            box(
              title = "Evolución Temporal de Menciones", 
              status = "primary", 
              solidHeader = TRUE,
              width = 12,
              height = 500,
              plotlyOutput("plot_evolucion", height = "450px")
            )
          )
        ),
        fluidRow(
          column(6,
            box(
              title = "Distribución de Menciones",
              status = "info",
              solidHeader = TRUE,
              width = 12,
              plotlyOutput("plot_distribucion", height = "300px")
            )
          ),
          column(6,
            box(
              title = "Top 10 Usuarios Más Activos",
              status = "success",
              solidHeader = TRUE,
              width = 12,
              height = 380,
              DT::dataTableOutput("tabla_usuarios")
            )
          )
        )
      ),
      
      # ===== PERSONAJES =====
      tabItem(
        tabName = "personajes",
        h2("Análisis por Personaje"),
        fluidRow(
          column(3,
            wellPanel(
              selectInput("personaje_seleccionado", 
                         "Seleccionar Personaje:",
                         choices = personajes_info$nombre,
                         selected = "Kast")
            )
          ),
          column(9,
            fluidRow(
              uiOutput("personaje_card")
            )
          )
        ),
        fluidRow(
          column(12,
            box(
              title = "Evolución Temporal",
              status = "primary",
              solidHeader = TRUE,
              width = 12,
              plotlyOutput("plot_personaje_evolucion", height = "400px")
            )
          )
        ),
        fluidRow(
          column(6,
            box(
              title = "Menciones por Día de la Semana",
              status = "info",
              solidHeader = TRUE,
              width = 12,
              plotlyOutput("plot_personaje_dia_semana", height = "300px")
            )
          ),
          column(6,
            box(
              title = "Menciones por Hora del Día",
              status = "warning",
              solidHeader = TRUE,
              width = 12,
              plotlyOutput("plot_personaje_hora", height = "300px")
            )
          )
        )
      ),
      
      # ===== EVENTOS =====
      tabItem(
        tabName = "eventos",
        h2("Análisis de Eventos"),
        fluidRow(
          column(4,
            if (!is.null(menciones_fecha) && nrow(menciones_fecha) > 0) {
              dateRangeInput("rango_fecha_eventos",
                            "Rango de Fechas:",
                            start = min(menciones_fecha$fecha, na.rm = TRUE),
                            end = max(menciones_fecha$fecha, na.rm = TRUE))
            } else {
              dateRangeInput("rango_fecha_eventos",
                            "Rango de Fechas:",
                            start = Sys.Date() - 30,
                            end = Sys.Date())
            }
          ),
          column(4,
            if (!is.null(menciones_fecha) && nrow(menciones_fecha) > 0) {
              pickerInput("candidatos_eventos",
                         "Candidatos:",
                         choices = unique(menciones_fecha$candidato),
                         selected = unique(menciones_fecha$candidato),
                         multiple = TRUE,
                         options = list(`actions-box` = TRUE))
            } else {
              pickerInput("candidatos_eventos",
                         "Candidatos:",
                         choices = c("Kast", "Kaiser", "Matthei", "Jara"),
                         selected = c("Kast", "Kaiser", "Matthei", "Jara"),
                         multiple = TRUE,
                         options = list(`actions-box` = TRUE))
            }
          )
        ),
        fluidRow(
          column(12,
            box(
              title = "Eventos y Picos de Menciones",
              status = "primary",
              solidHeader = TRUE,
              width = 12,
              height = 500,
              plotlyOutput("plot_eventos", height = "450px")
            )
          )
        ),
        fluidRow(
          column(12,
            box(
              title = "Tabla de Eventos Destacados",
              status = "info",
              solidHeader = TRUE,
              width = 12,
              DT::dataTableOutput("tabla_eventos")
            )
          )
        )
      ),
      
      # ===== FRAMES =====
      tabItem(
        tabName = "frames",
        h2("Análisis de Frames Discursivos"),
        fluidRow(
          column(12,
            p("Análisis de frames y marcos discursivos en los comentarios")
          )
        ),
        fluidRow(
          column(6,
            box(
              title = "Frames por Candidato",
              status = "primary",
              solidHeader = TRUE,
              width = 12,
              plotlyOutput("plot_frames_candidato", height = "400px")
            )
          ),
          column(6,
            box(
              title = "Evolución de Frames",
              status = "info",
              solidHeader = TRUE,
              width = 12,
              plotlyOutput("plot_frames_evolucion", height = "400px")
            )
          )
        )
      ),
      
      # ===== IDEOLOGÍA =====
      tabItem(
        tabName = "ideologia",
        h2("Análisis de Ideología"),
        conditionalPanel(
          condition = "output.ideologia_disponible",
          fluidRow(
            column(6,
              box(
                title = "Distribución de Ideologías",
                status = "primary",
                solidHeader = TRUE,
                width = 12,
                plotlyOutput("plot_ideologia_dist", height = "350px")
              )
            ),
            column(6,
              box(
                title = "Scores Left-Right",
                status = "info",
                solidHeader = TRUE,
                width = 12,
                plotlyOutput("plot_ideologia_scores", height = "350px")
              )
            )
          )
        ),
        conditionalPanel(
          condition = "!output.ideologia_disponible",
          fluidRow(
            column(12,
              box(
                title = "Datos de Ideología no Disponibles",
                status = "warning",
                solidHeader = TRUE,
                width = 12,
                p("Ejecuta el script 05_aplicacion_api.R para generar datos de imputación de ideología.")
              )
            )
          )
        )
      ),
      
      # ===== RESULTADOS SERVEL =====
      tabItem(
        tabName = "resultados_servel",
        h2("Resultados Electorales - SERVEL"),
        fluidRow(
          column(3,
            wellPanel(
              selectInput("candidato_servel",
                         "Seleccionar Candidato:",
                         choices = c("Kast", "Kaiser", "Matthei", "Jara", "Parisi", "Mayne_Nicholls"),
                         selected = "Kast"),
              radioButtons("nivel_geografico",
                          "Nivel Geográfico:",
                          choices = list("Regional" = "regional", "Comunal" = "comunal"),
                          selected = "regional"),
              br(),
              selectInput("vista_chile",
                         tags$span("Vista del Mapa:", 
                                  tags$span(icon("info-circle"), 
                                           title = "Norte: Arica a Atacama | Centro: Coquimbo a Maule (Santiago) | Sur: Ñuble a Magallanes",
                                           style = "margin-left: 5px; color: #95a5a6; cursor: help;")),
                         choices = list(
                           "Centro (Santiago)" = "centro",
                           "Norte" = "norte",
                           "Sur" = "sur",
                           "Todo Chile" = "todo"
                         ),
                         selected = "centro"),
              p(style = "font-size: 11px; color: #7f8c8d; font-style: italic; margin-top: -10px;",
                "Cambia la vista para explorar diferentes zonas del país"),
              p(strong("Nota:"), "Los datos deben procesarse primero"),
              br(),
              p(style = "font-size: 11px; color: #7f8c8d;",
                "Ejecuta:",
                tags$code("source('shiny_app/procesar_datos_servel.R')"),
                tags$br(),
                "Coloca archivos CSV en:",
                tags$code("data/servel/"))
            )
          ),
          column(9,
            fluidRow(
              column(12,
                box(
                  title = "Mapa de Resultados",
                  status = "primary",
                  solidHeader = TRUE,
                  width = 12,
                  height = 600,
                  leafletOutput("mapa_resultados", height = "550px")
                )
              )
            ),
            fluidRow(
              column(12,
                box(
                  title = "Tabla de Resultados",
                  status = "info",
                  solidHeader = TRUE,
                  width = 12,
                  height = 400,
                  DT::dataTableOutput("tabla_resultados_servel")
                )
              )
            )
          )
        )
      ),
      
      # ===== DATOS =====
      tabItem(
        tabName = "datos",
        h2("Tabla de Datos"),
        fluidRow(
          column(12,
            box(
              title = "Datos de Reddit",
              status = "primary",
              solidHeader = TRUE,
              width = 12,
              height = 600,
              DT::dataTableOutput("tabla_datos")
            )
          )
        )
      )
      
    )
  )
)

# =============================================================
# SERVER
# =============================================================

server <- function(input, output, session) {
  
  # Observador para botón de bienvenida
  observeEvent(input$ir_dashboard, {
    updateTabItems(session, "sidebar_menu", "dashboard")
  })
  
  # Value boxes con validación
  output$total_comentarios <- renderValueBox({
    if (is.null(df_reddit)) {
      valueBox(
        value = "N/A",
        subtitle = tags$strong("Total Comentarios"),
        icon = icon("comments", class = "fa-2x"),
        color = "red"
      )
    } else {
      valueBox(
        value = format(nrow(df_reddit), big.mark = "."),
        subtitle = tags$strong("Total Comentarios"),
        icon = icon("comments", class = "fa-2x"),
        color = "red"
      )
    }
  })
  
  output$total_menciones <- renderValueBox({
    if (is.null(df_reddit)) {
      valueBox(
        value = "N/A",
        subtitle = tags$strong("Total Menciones"),
        icon = icon("user-tag", class = "fa-2x"),
        color = "red"
      )
    } else {
      total <- sum(c(sum(df_reddit$kast, na.rm = TRUE),
                     sum(df_reddit$kaiser, na.rm = TRUE),
                     sum(df_reddit$matthei, na.rm = TRUE),
                     sum(df_reddit$jara, na.rm = TRUE)))
      valueBox(
        value = format(total, big.mark = "."),
        subtitle = tags$strong("Total Menciones"),
        icon = icon("user-tag", class = "fa-2x"),
        color = "red"
      )
    }
  })
  
  output$periodo_dias <- renderValueBox({
    if (is.null(df_reddit) || !"fecha" %in% names(df_reddit)) {
      valueBox(
        value = "N/A",
        subtitle = tags$strong("Días Analizados"),
        icon = icon("calendar-alt", class = "fa-2x"),
        color = "red"
      )
    } else {
      dias <- as.numeric(max(df_reddit$fecha, na.rm = TRUE) - min(df_reddit$fecha, na.rm = TRUE))
      valueBox(
        value = dias,
        subtitle = tags$strong("Días Analizados"),
        icon = icon("calendar-alt", class = "fa-2x"),
        color = "red"
      )
    }
  })
  
  output$usuarios_unicos <- renderValueBox({
    if (is.null(df_reddit) || !"comment_author" %in% names(df_reddit)) {
      valueBox(
        value = "N/A",
        subtitle = tags$strong("Usuarios Únicos"),
        icon = icon("users", class = "fa-2x"),
        color = "red"
      )
    } else {
      n_usuarios <- n_distinct(df_reddit$comment_author[df_reddit$comment_author != "[deleted]"], na.rm = TRUE)
      valueBox(
        value = format(n_usuarios, big.mark = "."),
        subtitle = tags$strong("Usuarios Únicos"),
        icon = icon("users", class = "fa-2x"),
        color = "red"
      )
    }
  })
  
  # Plot: Evolución temporal
  output$plot_evolucion <- renderPlotly({
    if (is.null(menciones_fecha) || nrow(menciones_fecha) == 0) {
      return(plotly_empty() %>% 
        add_annotations(text = "Datos no disponibles", 
                       xref = "paper", yref = "paper", 
                       x = 0.5, y = 0.5, showarrow = FALSE))
    }
    # Colores específicos para cada candidato
    colores_candidatos <- c(
      "Kast" = "#3498db",           # Azul
      "Kaiser" = "#27ae60",         # Verde
      "Matthei" = "#f1c40f",        # Amarillo
      "Jara" = "#e74c3c",           # Rojo
      "Parisi" = "#95a5a6",         # Gris
      "Mayne_Nicholls" = "#9b59b6"  # Morado
    )
    
    p <- menciones_fecha %>%
      ggplot(aes(x = fecha, y = menciones, color = candidato, group = candidato)) +
      geom_line(size = 1.2, alpha = 0.8) +
      geom_point(size = 1.5, alpha = 0.7) +
      scale_color_manual(values = colores_candidatos) +
      scale_x_date(date_labels = "%d %b", date_breaks = "1 week") +
      labs(
        title = "Evolución Temporal de Menciones",
        x = "Fecha",
        y = "Número de Menciones",
        color = "Candidato"
      ) +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.title = element_text(size = 16, face = "bold", color = "#2c3e50"),
        legend.position = "right"
      )
    
    ggplotly(p, tooltip = c("fecha", "menciones", "candidato")) %>%
      layout(legend = list(orientation = "v", x = 1.05, y = 0.5))
  })
  
  # Plot: Distribución
  output$plot_distribucion <- renderPlotly({
    if (is.null(totales_candidatos) || nrow(totales_candidatos) == 0) {
      return(plotly_empty() %>% 
        add_annotations(text = "Datos no disponibles", 
                       xref = "paper", yref = "paper", 
                       x = 0.5, y = 0.5, showarrow = FALSE))
    }
    # Colores específicos para cada candidato
    colores_candidatos <- c(
      "Kast" = "#3498db",           # Azul
      "Kaiser" = "#27ae60",         # Verde
      "Matthei" = "#f1c40f",        # Amarillo
      "Jara" = "#e74c3c",           # Rojo
      "Parisi" = "#95a5a6",         # Gris
      "Mayne_Nicholls" = "#9b59b6"  # Morado
    )
    
    p <- totales_candidatos %>%
      ggplot(aes(x = reorder(candidato, total), y = total, fill = candidato)) +
      geom_col(color = "white", size = 0.5, alpha = 0.9) +
      scale_fill_manual(values = colores_candidatos) +
      coord_flip() +
      labs(
        title = "Total de Menciones",
        x = "Candidato",
        y = "Menciones"
      ) +
      theme_minimal() +
      theme(
        legend.position = "none",
        plot.title = element_text(size = 14, face = "bold", color = "#2c3e50"),
        axis.text = element_text(color = "#2c3e50")
      )
    
    ggplotly(p, tooltip = c("candidato", "total"))
  })
  
  # Tabla: Usuarios
  output$tabla_usuarios <- DT::renderDataTable({
    if (is.null(df_reddit) || !"comment_author" %in% names(df_reddit)) {
      return(DT::datatable(data.frame(Usuario = character(0), Comentarios = numeric(0)),
                          options = list(pageLength = 10, dom = "t")))
    }
    df_reddit %>%
      filter(comment_author != "[deleted]", !is.na(comment_author)) %>%
      count(comment_author, sort = TRUE) %>%
      head(10) %>%
      rename(Usuario = comment_author, Comentarios = n) %>%
      DT::datatable(options = list(pageLength = 10, dom = "t"))
  })
  
  # Personaje card
  output$personaje_card <- renderUI({
    if (is.null(df_reddit)) {
      return(div(
        class = "personaje-card",
        tags$h3("Datos no disponibles"),
        tags$p("Los datos de Reddit no se pudieron cargar.")
      ))
    }
    
    personaje <- input$personaje_seleccionado
    info <- personajes_info %>% filter(nombre == personaje)
    
    # Colores específicos por personaje
    colores_personajes <- c(
      "Kast" = "#3498db",           # Azul
      "Kaiser" = "#27ae60",         # Verde
      "Matthei" = "#f1c40f",        # Amarillo
      "Jara" = "#e74c3c",           # Rojo
      "Parisi" = "#95a5a6",         # Gris
      "Mayne_Nicholls" = "#9b59b6"  # Morado
    )
    
    color_personaje <- colores_personajes[personaje]
    if (is.na(color_personaje)) color_personaje <- "#7f8c8d"  # Default gris
    
    col_name <- tolower(personaje)
    if (col_name %in% names(df_reddit)) {
      total <- df_reddit %>%
        summarise(total = sum(!!sym(col_name), na.rm = TRUE)) %>%
        pull(total)
    } else {
      total <- 0
    }
    
    # Verificar si existe la imagen (rutas relativas desde www/)
    imagen_path_rel <- file.path("www", "images", info$imagen)
    imagen_path_abs <- if (exists("IMAGES_DIR") && dir.exists(IMAGES_DIR)) {
      file.path(IMAGES_DIR, info$imagen)
    } else {
      NULL
    }
    imagen_existe <- file.exists(imagen_path_rel) || (!is.null(imagen_path_abs) && file.exists(imagen_path_abs))
    
    div(
      class = "personaje-card",
      if (imagen_existe) {
        tags$img(
          src = file.path("images", info$imagen), 
          class = "personaje-img",
          alt = info$nombre_completo,
          style = paste0("border-color: ", color_personaje, " !important;")
        )
      } else {
        tags$div(
          class = "personaje-img",
          style = paste0("background: ", color_personaje, "; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; font-size: 24px;"),
          substr(info$nombre, 1, 3)
        )
      },
      tags$h3(info$nombre_completo),
      tags$h2(format(total, big.mark = "."), style = paste0("color: ", color_personaje, "; margin: 10px 0; font-weight: 600;")),
      tags$p("Total de menciones", style = "color: #666;")
    )
  })
  
  # Plot: Personaje evolución
  output$plot_personaje_evolucion <- renderPlotly({
    if (is.null(menciones_fecha) || nrow(menciones_fecha) == 0) {
      return(plotly_empty() %>% 
        add_annotations(text = "Datos no disponibles", 
                       xref = "paper", yref = "paper", 
                       x = 0.5, y = 0.5, showarrow = FALSE))
    }
    
    personaje <- input$personaje_seleccionado
    col_name <- tolower(personaje)
    
    # Colores específicos por personaje
    colores_personajes <- c(
      "Kast" = "#3498db",           # Azul
      "Kaiser" = "#27ae60",         # Verde
      "Matthei" = "#f1c40f",        # Amarillo
      "Jara" = "#e74c3c",           # Rojo
      "Parisi" = "#95a5a6",         # Gris
      "Mayne_Nicholls" = "#9b59b6"  # Morado
    )
    
    color_personaje <- colores_personajes[personaje]
    if (is.na(color_personaje)) color_personaje <- "#7f8c8d"  # Default gris
    
    data <- menciones_fecha %>%
      filter(candidato == personaje)
    
    p <- data %>%
      ggplot(aes(x = fecha, y = menciones)) +
      geom_line(color = color_personaje, linewidth = 1.5) +
      geom_area(fill = color_personaje, alpha = 0.25) +
      scale_x_date(date_labels = "%d %b", date_breaks = "1 week") +
      labs(
        title = paste("Evolución de menciones:", personaje),
        x = "Fecha",
        y = "Menciones"
      ) +
      theme_minimal() +
      theme(
        plot.title = element_text(size = 16, face = "bold", color = "#2c3e50")
      )
    
    ggplotly(p)
  })
  
  # Plot: Día de la semana
  output$plot_personaje_dia_semana <- renderPlotly({
    if (is.null(df_reddit) || !"fecha" %in% names(df_reddit)) {
      return(plotly_empty() %>% 
        add_annotations(text = "Datos no disponibles", 
                       xref = "paper", yref = "paper", 
                       x = 0.5, y = 0.5, showarrow = FALSE))
    }
    
    personaje <- input$personaje_seleccionado
    col_name <- tolower(personaje)
    
    if (!col_name %in% names(df_reddit)) {
      return(plotly_empty() %>% 
        add_annotations(text = "Datos no disponibles para este personaje", 
                       xref = "paper", yref = "paper", 
                       x = 0.5, y = 0.5, showarrow = FALSE))
    }
    
    # Colores específicos por personaje
    colores_personajes <- c(
      "Kast" = "#3498db",           # Azul
      "Kaiser" = "#27ae60",         # Verde
      "Matthei" = "#f1c40f",        # Amarillo
      "Jara" = "#e74c3c",           # Rojo
      "Parisi" = "#95a5a6",         # Gris
      "Mayne_Nicholls" = "#9b59b6"  # Morado
    )
    
    color_personaje <- colores_personajes[personaje]
    if (is.na(color_personaje)) color_personaje <- "#7f8c8d"  # Default gris
    
    data <- df_reddit %>%
      filter(!!sym(col_name) == 1, !is.na(fecha)) %>%
      mutate(dia_semana = wday(fecha, label = TRUE, abbr = FALSE)) %>%
      count(dia_semana) %>%
      arrange(match(dia_semana, c("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")))
    
    p <- data %>%
      ggplot(aes(x = dia_semana, y = n)) +
      geom_col(fill = color_personaje, alpha = 0.8, color = "white", size = 0.5) +
      labs(
        title = "Menciones por Día de la Semana",
        x = "Día",
        y = "Menciones"
      ) +
      theme_minimal() +
      theme(
        legend.position = "none", 
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.title = element_text(size = 14, face = "bold", color = "#2c3e50")
      )
    
    ggplotly(p)
  })
  
  # Plot: Hora
  output$plot_personaje_hora <- renderPlotly({
    if (is.null(df_reddit) || !"post_created" %in% names(df_reddit)) {
      return(plotly_empty() %>% 
        add_annotations(text = "Datos no disponibles", 
                       xref = "paper", yref = "paper", 
                       x = 0.5, y = 0.5, showarrow = FALSE))
    }
    
    personaje <- input$personaje_seleccionado
    col_name <- tolower(personaje)
    
    if (!col_name %in% names(df_reddit)) {
      return(plotly_empty() %>% 
        add_annotations(text = "Datos no disponibles para este personaje", 
                       xref = "paper", yref = "paper", 
                       x = 0.5, y = 0.5, showarrow = FALSE))
    }
    
    # Colores específicos por personaje
    colores_personajes <- c(
      "Kast" = "#3498db",           # Azul
      "Kaiser" = "#27ae60",         # Verde
      "Matthei" = "#f1c40f",        # Amarillo
      "Jara" = "#e74c3c",           # Rojo
      "Parisi" = "#95a5a6",         # Gris
      "Mayne_Nicholls" = "#9b59b6"  # Morado
    )
    
    color_personaje <- colores_personajes[personaje]
    if (is.na(color_personaje)) color_personaje <- "#7f8c8d"  # Default gris
    
    data <- df_reddit %>%
      filter(!!sym(col_name) == 1, !is.na(post_created)) %>%
      mutate(hora = hour(post_created)) %>%
      count(hora)
    
    p <- data %>%
      ggplot(aes(x = hora, y = n)) +
      geom_line(color = color_personaje, linewidth = 1.5) +
      geom_area(fill = color_personaje, alpha = 0.25) +
      scale_x_continuous(breaks = seq(0, 23, 2)) +
      labs(
        title = "Menciones por Hora del Día",
        x = "Hora",
        y = "Menciones"
      ) +
      theme_minimal() +
      theme(
        plot.title = element_text(size = 14, face = "bold", color = "#2c3e50")
      )
    
    ggplotly(p)
  })
  
  # Plot: Eventos
  output$plot_eventos <- renderPlotly({
    if (is.null(menciones_fecha) || nrow(menciones_fecha) == 0) {
      return(plotly_empty() %>% 
        add_annotations(text = "Datos no disponibles", 
                       xref = "paper", yref = "paper", 
                       x = 0.5, y = 0.5, showarrow = FALSE))
    }
    # Colores específicos para cada candidato
    colores_candidatos <- c(
      "Kast" = "#3498db",           # Azul
      "Kaiser" = "#27ae60",         # Verde
      "Matthei" = "#f1c40f",        # Amarillo
      "Jara" = "#e74c3c",           # Rojo
      "Parisi" = "#95a5a6",         # Gris
      "Mayne_Nicholls" = "#9b59b6"  # Morado
    )
    
    data <- menciones_fecha %>%
      filter(fecha >= input$rango_fecha_eventos[1],
             fecha <= input$rango_fecha_eventos[2],
             candidato %in% input$candidatos_eventos)
    
    p <- data %>%
      ggplot(aes(x = fecha, y = menciones, color = candidato)) +
      geom_line(linewidth = 1.2, alpha = 0.8) +
      geom_point(size = 1.5, alpha = 0.7) +
      scale_color_manual(values = colores_candidatos) +
      scale_x_date(date_labels = "%d %b", date_breaks = "3 days") +
      labs(
        title = "Eventos y Picos de Menciones",
        x = "Fecha",
        y = "Menciones",
        color = "Candidato"
      ) +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.title = element_text(size = 16, face = "bold", color = "#2c3e50"),
        legend.position = "right"
      )
    
    ggplotly(p, tooltip = c("fecha", "menciones", "candidato")) %>%
      layout(legend = list(orientation = "v", x = 1.05, y = 0.5))
  })
  
  # Tabla: Eventos
  output$tabla_eventos <- DT::renderDataTable({
    if (is.null(menciones_fecha) || nrow(menciones_fecha) == 0) {
      return(DT::datatable(data.frame(Fecha = character(0), Candidato = character(0), Menciones = numeric(0)),
                          options = list(pageLength = 15)))
    }
    menciones_fecha %>%
      filter(fecha >= input$rango_fecha_eventos[1],
             fecha <= input$rango_fecha_eventos[2],
             candidato %in% input$candidatos_eventos) %>%
      arrange(desc(menciones)) %>%
      head(50) %>%
      rename(Fecha = fecha, Candidato = candidato, Menciones = menciones) %>%
      DT::datatable(options = list(pageLength = 15))
  })
  
  # Ideología disponible
  output$ideologia_disponible <- reactive({
    !is.null(df_ideologia)
  })
  outputOptions(output, "ideologia_disponible", suspendWhenHidden = FALSE)
  
  # Plot: Ideología distribución
  output$plot_ideologia_dist <- renderPlotly({
    if (!is.null(df_ideologia) && "left_right_label" %in% names(df_ideologia)) {
      data <- df_ideologia %>%
        filter(!is.na(left_right_label)) %>%
        count(left_right_label) %>%
        arrange(desc(n))
      
      p <- data %>%
        ggplot(aes(x = reorder(left_right_label, n), y = n, fill = left_right_label)) +
        geom_col() +
        coord_flip() +
        labs(
          title = "Distribución de Labels de Ideología",
          x = "Label",
          y = "Frecuencia"
        ) +
        theme_minimal() +
        theme(legend.position = "none")
      
      ggplotly(p)
    }
  })
  
  # Plot: Ideología scores
  output$plot_ideologia_scores <- renderPlotly({
    if (!is.null(df_ideologia) && "left_right_score" %in% names(df_ideologia)) {
      data <- df_ideologia %>%
        filter(!is.na(left_right_score))
      
      p <- data %>%
        ggplot(aes(x = left_right_score)) +
        geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7, color = "black") +
        geom_vline(xintercept = 0, linetype = "dashed", color = "red") +
        labs(
          title = "Distribución de Scores Left-Right",
          subtitle = paste("Media:", round(mean(data$left_right_score, na.rm = TRUE), 3)),
          x = "Score (-1 = Left, +1 = Right)",
          y = "Frecuencia"
        ) +
        theme_minimal()
      
      ggplotly(p)
    }
  })
  
  # Tabla: Datos
  output$tabla_datos <- DT::renderDataTable({
    if (is.null(df_reddit) || nrow(df_reddit) == 0) {
      return(DT::datatable(data.frame(Mensaje = "Datos no disponibles"),
                          options = list(pageLength = 25, scrollX = TRUE)))
    }
    cols_to_select <- intersect(c("post_title", "comment_author", "comment_body", "fecha", 
                                   "kast", "kaiser", "matthei", "jara"), 
                                names(df_reddit))
    if (length(cols_to_select) == 0) {
      return(DT::datatable(data.frame(Mensaje = "Columnas no disponibles"),
                          options = list(pageLength = 25, scrollX = TRUE)))
    }
    df_reddit %>%
      select(all_of(cols_to_select)) %>%
      head(1000) %>%
      DT::datatable(
        options = list(pageLength = 25, scrollX = TRUE),
        filter = "top"
      )
  })
  
  # ===== RESULTADOS SERVEL =====
  
  # Cargar datos procesados del SERVEL
  df_servel_regional <- reactive({
    # Buscar en múltiples ubicaciones
    app_dir <- getwd()
    if (basename(app_dir) != "shiny_app") {
      app_dir <- file.path(app_dir, "shiny_app")
    }
    
    archivos <- c(
      file.path(app_dir, "data", "processed", "servel", "servel_regional.rds"),
      file.path(app_dir, "data", "servel", "servel_regional.rds"),
      get_data_path("data", "processed", "servel", "servel_regional.rds"),
      get_data_path("data", "servel", "servel_regional.rds")
    )
    
    for (archivo in archivos) {
      if (file.exists(archivo)) {
        tryCatch({
          return(readRDS(archivo))
        }, error = function(e) {
          return(NULL)
        })
      }
    }
    return(NULL)
  })
  
  df_servel_comunal <- reactive({
    # Buscar en múltiples ubicaciones
    app_dir <- getwd()
    if (basename(app_dir) != "shiny_app") {
      app_dir <- file.path(app_dir, "shiny_app")
    }
    
    archivos <- c(
      file.path(app_dir, "data", "processed", "servel", "servel_comunal.rds"),
      file.path(app_dir, "data", "servel", "servel_comunal.rds"),
      get_data_path("data", "processed", "servel", "servel_comunal.rds"),
      get_data_path("data", "servel", "servel_comunal.rds")
    )
    
    for (archivo in archivos) {
      if (file.exists(archivo)) {
        tryCatch({
          return(readRDS(archivo))
        }, error = function(e) {
          return(NULL)
        })
      }
    }
    return(NULL)
  })
  
  # Datos unificados según nivel seleccionado
  df_servel <- reactive({
    nivel <- input$nivel_geografico
    
    if (nivel == "regional") {
      return(df_servel_regional())
    } else {
      return(df_servel_comunal())
    }
  })
  
  
  # Mapa de resultados
  output$mapa_resultados <- renderLeaflet({
    candidato <- input$candidato_servel
    nivel <- input$nivel_geografico
    vista <- input$vista_chile
    
    # Coordenadas de Chile según vista
    # Longitud central: ~-70.5° a -71.5°
    vistas_chile <- list(
      "norte" = list(
        lat = -22.5,  # Centro de la zona norte
        lng = -70.0,
        zoom = 6,
        bounds = list(
          north = -17.5,   # Arica y Parinacota
          south = -27.0,   # Atacama
          east = -66.4,
          west = -75.0
        )
      ),
      "centro" = list(
        lat = -33.4489,  # Santiago (centro del centro)
        lng = -70.6693,
        zoom = 7,
        bounds = list(
          north = -27.0,   # Coquimbo
          south = -36.0,   # Maule
          east = -66.4,
          west = -75.0
        )
      ),
      "sur" = list(
        lat = -41.5,  # Centro de la zona sur
        lng = -72.0,
        zoom = 6,
        bounds = list(
          north = -36.0,   # Ñuble
          south = -56.0,   # Magallanes
          east = -66.4,
          west = -75.0
        )
      ),
      "todo" = list(
        lat = -35.0,  # Centro geográfico aproximado
        lng = -71.0,
        zoom = 5,
        bounds = list(
          north = -17.5,
          south = -56.0,
          east = -66.4,
          west = -75.0
        )
      )
    )
    
    vista_config <- vistas_chile[[vista]]
    
    # Crear mapa base de Chile con bounds apropiados
    # maxBounds limita el área visible del mapa
    mapa_base <- leaflet(options = leafletOptions(
      minZoom = 4, 
      maxZoom = 12,
      maxBounds = matrix(c(-56.0, -75.0, -17.5, -66.4), nrow = 2, byrow = TRUE)
    )) %>%
      addTiles() %>%
      setView(lng = vista_config$lng, lat = vista_config$lat, zoom = vista_config$zoom) %>%
      # Limitar el mapa a Chile
      fitBounds(
        lng1 = vista_config$bounds$west,
        lat1 = vista_config$bounds$south,
        lng2 = vista_config$bounds$east,
        lat2 = vista_config$bounds$north
      )
    
    # Si hay datos del SERVEL, procesar y agregar
    datos <- df_servel()
    if (!is.null(datos) && nrow(datos) > 0 && "candidato" %in% names(datos)) {
      datos_filtrados <- datos %>%
        filter(candidato == !!candidato)
      
      if (nrow(datos_filtrados) > 0) {
        # Agregar marcadores o polígonos por región/comuna si tenemos coordenadas
        # Por ahora, agregamos control con información
        mapa_base <- mapa_base %>%
          addControl(
            html = tags$div(
              style = "background: white; padding: 10px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);",
              tags$strong(style = "color: #c0392b;", "✅ Datos del SERVEL cargados"),
              tags$br(),
              tags$small(sprintf("Candidato: %s | Nivel: %s", candidato, nivel)),
              tags$br(),
              tags$small(sprintf("Vista: %s | Registros: %d", 
                                switch(vista, 
                                       "norte" = "Norte",
                                       "centro" = "Centro",
                                       "sur" = "Sur",
                                       "todo" = "Todo Chile",
                                       vista), 
                                nrow(datos_filtrados)))
            ),
            position = "topright"
          )
      } else {
        mapa_base
      }
    } else {
      # Mapa base con mensaje informativo
      mapa_base %>%
        addControl(
          html = tags$div(
            style = "background: white; padding: 15px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.2); max-width: 300px;",
            tags$strong(style = "color: #c0392b;", "Datos del SERVEL no disponibles"),
            tags$br(), tags$br(),
            tags$p("Pasos:", style = "font-weight: bold; margin: 5px 0;"),
            tags$ol(
              style = "font-size: 11px; margin: 5px 0; padding-left: 20px;",
              tags$li("Coloca archivos CSV en", tags$code("data/servel/")),
              tags$li("Ejecuta:", tags$code("source('shiny_app/procesar_datos_servel.R')")),
              tags$li("Recarga la app")
            ),
            tags$br(),
            tags$p("Ver README.md en data/servel/ para formato esperado", 
                   style = "font-size: 11px; color: #95a5a6;")
          ),
          position = "topright"
        )
    }
  })
  
  # Tabla de resultados
  output$tabla_resultados_servel <- DT::renderDataTable({
    candidato <- input$candidato_servel
    nivel <- input$nivel_geografico
    
    datos <- df_servel()
    
    if (is.null(datos) || nrow(datos) == 0) {
      # Datos de ejemplo para mostrar estructura esperada
      ejemplo <- tibble(
        `Región/Comuna` = c("Metropolitana", "Valparaíso", "Bío Bío"),
        `Candidato` = candidato,
        `Votos` = c(0, 0, 0),
        `Porcentaje (%)` = c(0.0, 0.0, 0.0),
        `Total Votos` = c(0, 0, 0)
      )
      
      return(
        ejemplo %>%
          DT::datatable(
            options = list(
              pageLength = 15,
              dom = "t",
              language = list(
                emptyTable = "No hay datos del SERVEL disponibles"
              )
            ),
            rownames = FALSE
          ) %>%
          DT::formatStyle(columns = 1:5, fontSize = "90%")
      )
    }
    
    # Los datos ya están filtrados por nivel geográfico en df_servel()
    # Solo necesitamos filtrar por candidato y ordenar
    datos_procesados <- datos %>%
      filter(candidato == !!candidato) %>%
      arrange(desc(porcentaje))
    
    # Identificar columna de porcentaje para formatear
    pct_cols <- which(str_detect(names(datos_procesados), "(?i)porcentaje|pct|%"))
    
    # Crear tabla
    tabla <- DT::datatable(
      datos_procesados,
      options = list(
        pageLength = 15,
        scrollX = TRUE,
        order = list(list(if(length(pct_cols) > 0) pct_cols[1] else 1, "desc"))
      ),
      filter = "top",
      rownames = FALSE
    )
    
    # Formatear porcentajes si existen
    if (length(pct_cols) > 0) {
      for (col in pct_cols) {
        # Detectar si los valores están en 0-100 o 0-1
        valores <- datos_procesados[[col]]
        if (max(valores, na.rm = TRUE) <= 1 && min(valores, na.rm = TRUE) >= 0) {
          tabla <- tabla %>%
            DT::formatPercentage(col, digits = 2)
        } else {
          # Si están en 0-100, dividir por 100 para formateo
          tabla <- tabla %>%
            DT::formatRound(col, digits = 2) %>%
            DT::formatStyle(col, 
                           backgroundColor = DT::styleInterval(
                             c(20, 30, 40),
                             c("#fee5d9", "#fcae91", "#fb6a4a", "#de2d26")
                           ))
        }
      }
    }
    
    tabla
  })
  
}

# =============================================================
# RUN APP
# =============================================================

shinyApp(ui = ui, server = server)

