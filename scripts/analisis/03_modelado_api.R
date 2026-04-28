# =============================================================
# 04) API-based Text Analysis
# Sentiment classification and topic extraction using Gemini and GPT APIs
# Reads from: data/processed/
# =============================================================
#
# NOTA: Este script está preparado pero NO se ejecutará todavía.
# Requiere:
# - Configuración de credenciales API (GEMINI_API_KEY, OPENAI_API_KEY)
# - Consideraciones de costo y tiempo de procesamiento
# - Revisión de límites de rate limiting
#
# =============================================================

# Setup
pacman::p_load(
  tidyverse, here, readr, httr, jsonlite, lubridate
)

# Configuración
OUT_DIR <- here("data", "processed", "analisis_texto")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# Cargar variables de entorno (desde .env o sistema)
# GEMINI_API_KEY <- Sys.getenv("GEMINI_API_KEY")
# OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")

# =============================================================
# 1) Carga y preparación de datos
# =============================================================

cargar_datos <- function() {
  df <- readRDS(here("data/processed/reddit_filtrado.rds"))
  
  # Preparar textos para análisis
  df_texto <- df %>%
    mutate(
      texto_completo = paste(
        coalesce(post_title, ""),
        coalesce(post_selftext, ""),
        coalesce(comment_body, ""),
        sep = " "
      ),
      texto_id = row_number(),
      n_palabras = str_count(texto_completo, "\\S+"),
      n_caracteres = nchar(texto_completo)
    ) %>%
    filter(
      !is.na(texto_completo),
      texto_completo != "",
      texto_completo != " ",
      n_caracteres >= 10  # Filtrar textos muy cortos
    ) %>%
    select(
      texto_id, texto_completo, fecha, post_id, comment_author,
      kast, kaiser, matthei, jara, parisi, mayne_nicholls,
      n_palabras, n_caracteres
    )
  
  return(df_texto)
}

# =============================================================
# 2) Funciones para API de Gemini
# =============================================================

# Clasificar sentimiento con Gemini
clasificar_sentimiento_gemini <- function(texto, api_key) {
  # URL de la API de Gemini
  url <- "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
  
  # Prompt para clasificación
  prompt <- paste0(
    "Analiza el siguiente texto en español y clasifica su sentimiento hacia el candidato mencionado. ",
    "Responde ÚNICAMENTE con una de estas opciones: POSITIVO, NEGATIVO, NEUTRO. ",
    "Si el texto expresa apoyo, admiración o comentarios favorables, responde POSITIVO. ",
    "Si expresa crítica, rechazo o comentarios desfavorables, responde NEGATIVO. ",
    "Si es neutral, informativo o no expresa una posición clara, responde NEUTRO.\n\n",
    "Texto a analizar:\n", texto
  )
  
  # Preparar request
  body <- list(
    contents = list(
      list(
        parts = list(
          list(text = prompt)
        )
      )
    ),
    generationConfig = list(
      temperature = 0.1,
      maxOutputTokens = 10
    )
  )
  
  # Realizar request
  response <- tryCatch({
    httr::POST(
      url = paste0(url, "?key=", api_key),
      body = body,
      encode = "json",
      httr::add_headers("Content-Type" = "application/json")
    )
  }, error = function(e) {
    return(NULL)
  })
  
  if (is.null(response) || httr::status_code(response) != 200) {
    return(list(sentimiento = NA, confianza = NA, error = TRUE))
  }
  
  # Parsear respuesta
  content <- httr::content(response, "parsed")
  
  if (is.null(content$candidates) || length(content$candidates) == 0) {
    return(list(sentimiento = NA, confianza = NA, error = TRUE))
  }
  
  resultado_texto <- content$candidates[[1]]$content$parts[[1]]$text
  resultado_texto <- trimws(toupper(resultado_texto))
  
  # Extraer sentimiento
  sentimiento <- case_when(
    str_detect(resultado_texto, "POSITIVO") ~ "positivo",
    str_detect(resultado_texto, "NEGATIVO") ~ "negativo",
    str_detect(resultado_texto, "NEUTRO") ~ "neutro",
    TRUE ~ NA_character_
  )
  
  return(list(
    sentimiento = sentimiento,
    confianza = ifelse(!is.na(sentimiento), 0.8, 0),
    error = FALSE,
    respuesta_raw = resultado_texto
  ))
}

# Extraer tópicos con Gemini
extraer_topicos_gemini <- function(texto, api_key) {
  url <- "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
  
  prompt <- paste0(
    "Analiza el siguiente texto en español y extrae los tópicos principales mencionados. ",
    "Responde con una lista de 3-5 tópicos principales separados por comas. ",
    "Los tópicos pueden ser: seguridad, economía, migración, educación, salud, género, ",
    "corrupción, constitución, empleo, o cualquier otro tema relevante mencionado.\n\n",
    "Texto a analizar:\n", texto
  )
  
  body <- list(
    contents = list(
      list(
        parts = list(
          list(text = prompt)
        )
      )
    ),
    generationConfig = list(
      temperature = 0.3,
      maxOutputTokens = 100
    )
  )
  
  response <- tryCatch({
    httr::POST(
      url = paste0(url, "?key=", api_key),
      body = body,
      encode = "json",
      httr::add_headers("Content-Type" = "application/json")
    )
  }, error = function(e) {
    return(NULL)
  })
  
  if (is.null(response) || httr::status_code(response) != 200) {
    return(list(topicos = NA, error = TRUE))
  }
  
  content <- httr::content(response, "parsed")
  
  if (is.null(content$candidates) || length(content$candidates) == 0) {
    return(list(topicos = NA, error = TRUE))
  }
  
  topicos_texto <- content$candidates[[1]]$content$parts[[1]]$text
  topicos <- str_split(trimws(topicos_texto), ",") %>%
    unlist() %>%
    str_trim() %>%
    str_to_lower()
  
  return(list(
    topicos = paste(topicos, collapse = "; "),
    error = FALSE
  ))
}

# =============================================================
# 3) Funciones para API de OpenAI GPT
# =============================================================

# Clasificar sentimiento con GPT
clasificar_sentimiento_gpt <- function(texto, api_key) {
  url <- "https://api.openai.com/v1/chat/completions"
  
  # Prompt mejorado para clasificación (Reddit + elecciones) + puntaje de polarización
  prompt <- paste0(
    "Eres un/a anotador/a experto/a de discurso político. ",
    "Analiza el siguiente texto (español informal, puede incluir sarcasmo, insultos, emojis o ironía) ",
    "y entrega (a) el SENTIMIENTO del autor HACIA el/los candidato(s) mencionado(s) y (b) un PUNTAJE de POLARIZACIÓN.\n\n",
    
    "INSTRUCCIONES CLAVE (SENTIMIENTO):\n",
    "1) Identifica a quién va dirigido el juicio (el candidato o candidatos mencionados).\n",
    "2) Si hay sarcasmo/ironía, interpreta el sentido real (por ejemplo, elogio irónico cuenta como NEGATIVO).\n",
    "3) Si el texto critica a un adversario para beneficiar implícitamente a otro candidato, ",
    "clasifica según el candidato aludido (si el candidato evaluado no queda claro -> NEUTRO).\n",
    "4) Si el texto mezcla positivo y negativo hacia el MISMO candidato, elige el sentimiento DOMINANTE.\n",
    "5) Si el texto solo informa (encuestas, noticias, resultados) sin juicio, responde NEUTRO.\n\n",
    
    "INSTRUCCIONES CLAVE (POLARIZACIÓN):\n",
    "La polarización significa lenguaje de 'nosotros vs ellos', insultos grupales, deshumanización, ",
    "generalizaciones absolutas, atribución moral extrema, llamados a excluir/castigar, o hostilidad intensa ",
    "hacia grupos/candidatos.\n",
    "Si hay sarcasmo/ironía, puntúa según el sentido real.\n\n",
    
    "ESCALA DE POLARIZACIÓN (solo valores permitidos: 0.0, 0.1, 0.2, ..., 1.0):\n",
    "0.0 = Máxima polarización (odio/insultos fuertes, deshumaniza, incita violencia/exclusión).\n",
    "0.1 = Muy alta (ataques intensos y absolutos, estigmatiza al otro bando).\n",
    "0.2 = Alta (ataques claros + generalizaciones 'todos son...', tono agresivo).\n",
    "0.3 = Media-alta (confrontación marcada, burlas fuertes, 'ellos vs nosotros' explícito).\n",
    "0.4 = Media (crítica dura o sarcástica, sin deshumanización ni llamados extremos).\n",
    "0.5 = Media-baja (crítica moderada con sesgo/tribalismo leve).\n",
    "0.6 = Baja (opinión política sin hostilidad, crítica razonada).\n",
    "0.7 = Muy baja (discusión relativamente equilibrada, mínima carga afectiva).\n",
    "0.8 = Casi nada (informativo/analítico, sin ataque ni tribalismo).\n",
    "0.9 = Prácticamente neutral (descriptivo o pregunta, sin postura fuerte).\n",
    "1.0 = No polarizado (neutral/informativo o no político).\n\n",
    
    "SALIDA OBLIGATORIA:\n",
    "Responde ÚNICAMENTE en este formato EXACTO (sin texto extra):\n",
    "SENTIMIENTO=POSITIVO|NEGATIVO|NEUTRO; POLARIZACION=X.X\n",
    "donde X.X debe ser uno de: 0.0, 0.1, 0.2, ..., 1.0.\n\n",
    
    "Texto:\n",
    texto
  )
  
  
  body <- list(
    model = "gpt-3.5-turbo",
    messages = list(
      list(
        role = "system",
        content = "Eres un analista de sentimiento especializado en discurso político en español."
      ),
      list(
        role = "user",
        content = prompt
      )
    ),
    temperature = 0.1,
    max_tokens = 10
  )
  
  response <- tryCatch({
    httr::POST(
      url = url,
      body = body,
      encode = "json",
      httr::add_headers(
        "Authorization" = paste("Bearer", api_key),
        "Content-Type" = "application/json"
      )
    )
  }, error = function(e) {
    return(NULL)
  })
  
  if (is.null(response) || httr::status_code(response) != 200) {
    return(list(sentimiento = NA, confianza = NA, error = TRUE))
  }
  
  content <- httr::content(response, "parsed")
  
  if (is.null(content$choices) || length(content$choices) == 0) {
    return(list(sentimiento = NA, confianza = NA, error = TRUE))
  }
  
  resultado_texto <- content$choices[[1]]$message$content
  resultado_texto <- trimws(toupper(resultado_texto))
  
  sentimiento <- case_when(
    str_detect(resultado_texto, "POSITIVO") ~ "positivo",
    str_detect(resultado_texto, "NEGATIVO") ~ "negativo",
    str_detect(resultado_texto, "NEUTRO") ~ "neutro",
    TRUE ~ NA_character_
  )
  
  return(list(
    sentimiento = sentimiento,
    confianza = ifelse(!is.na(sentimiento), 0.8, 0),
    error = FALSE,
    respuesta_raw = resultado_texto
  ))
}

# Extraer tópicos con GPT
extraer_topicos_gpt <- function(texto, api_key) {
  url <- "https://api.openai.com/v1/chat/completions"
  
  prompt <- paste0(
    "Analiza el siguiente texto en español y extrae los tópicos principales mencionados. ",
    "Responde con una lista de 3-5 tópicos principales separados por comas.\n\n",
    "Texto a analizar:\n", texto
  )
  
  body <- list(
    model = "gpt-3.5-turbo",
    messages = list(
      list(
        role = "system",
        content = "Eres un analista de tópicos especializado en discurso político."
      ),
      list(
        role = "user",
        content = prompt
      )
    ),
    temperature = 0.3,
    max_tokens = 100
  )
  
  response <- tryCatch({
    httr::POST(
      url = url,
      body = body,
      encode = "json",
      httr::add_headers(
        "Authorization" = paste("Bearer", api_key),
        "Content-Type" = "application/json"
      )
    )
  }, error = function(e) {
    return(NULL)
  })
  
  if (is.null(response) || httr::status_code(response) != 200) {
    return(list(topicos = NA, error = TRUE))
  }
  
  content <- httr::content(response, "parsed")
  
  if (is.null(content$choices) || length(content$choices) == 0) {
    return(list(topicos = NA, error = TRUE))
  }
  
  topicos_texto <- content$choices[[1]]$message$content
  topicos <- str_split(trimws(topicos_texto), ",") %>%
    unlist() %>%
    str_trim() %>%
    str_to_lower()
  
  return(list(
    topicos = paste(topicos, collapse = "; "),
    error = FALSE
  ))
}

# =============================================================
# 4) Función principal de procesamiento
# =============================================================

procesar_textos <- function(
  df_texto,
  gemini_api_key = NULL,
  openai_api_key = NULL,
  n_muestra = NULL,
  batch_size = 10,
  delay_seconds = 1
) {
  
  # Filtrar muestra si se especifica
  if (!is.null(n_muestra)) {
    df_texto <- df_texto %>%
      sample_n(min(n_muestra, nrow(df_texto)))
  }
  
  # Inicializar resultados
  resultados <- df_texto %>%
    mutate(
      sentimiento_gemini = NA_character_,
      confianza_gemini = NA_real_,
      sentimiento_gpt = NA_character_,
      confianza_gpt = NA_real_,
      sentimiento_final = NA_character_,
      topicos_gemini = NA_character_,
      topicos_gpt = NA_character_,
      topicos_final = NA_character_,
      error_gemini = FALSE,
      error_gpt = FALSE,
      procesado = FALSE
    )
  
  # Procesar por lotes
  n_total <- nrow(resultados)
  n_batches <- ceiling(n_total / batch_size)
  
  cat("Procesando", n_total, "textos en", n_batches, "lotes de", batch_size, "\n")
  
  for (i in 1:n_batches) {
    inicio <- (i - 1) * batch_size + 1
    fin <- min(i * batch_size, n_total)
    
    cat("Procesando lote", i, "de", n_batches, "(textos", inicio, "-", fin, ")\n")
    
    for (j in inicio:fin) {
      texto <- resultados$texto_completo[j]
      
      # Procesar con Gemini si está disponible
      if (!is.null(gemini_api_key)) {
        resultado_gemini <- clasificar_sentimiento_gemini(texto, gemini_api_key)
        resultados$sentimiento_gemini[j] <- resultado_gemini$sentimiento
        resultados$confianza_gemini[j] <- resultado_gemini$confianza
        resultados$error_gemini[j] <- resultado_gemini$error
        
        # Extraer tópicos
        topicos_gemini <- extraer_topicos_gemini(texto, gemini_api_key)
        resultados$topicos_gemini[j] <- topicos_gemini$topicos
      }
      
      # Procesar con GPT si está disponible
      if (!is.null(openai_api_key)) {
        resultado_gpt <- clasificar_sentimiento_gpt(texto, openai_api_key)
        resultados$sentimiento_gpt[j] <- resultado_gpt$sentimiento
        resultados$confianza_gpt[j] <- resultado_gpt$confianza
        resultados$error_gpt[j] <- resultado_gpt$error
        
        # Extraer tópicos
        topicos_gpt <- extraer_topicos_gpt(texto, openai_api_key)
        resultados$topicos_gpt[j] <- topicos_gpt$topicos
      }
      
      # Determinar sentimiento final (consenso)
      if (!is.null(gemini_api_key) && !is.null(openai_api_key)) {
        if (!is.na(resultados$sentimiento_gemini[j]) && 
            !is.na(resultados$sentimiento_gpt[j])) {
          if (resultados$sentimiento_gemini[j] == resultados$sentimiento_gpt[j]) {
            resultados$sentimiento_final[j] <- resultados$sentimiento_gemini[j]
          } else {
            # En caso de desacuerdo, usar el de mayor confianza
            if (resultados$confianza_gemini[j] >= resultados$confianza_gpt[j]) {
              resultados$sentimiento_final[j] <- resultados$sentimiento_gemini[j]
            } else {
              resultados$sentimiento_final[j] <- resultados$sentimiento_gpt[j]
            }
          }
        } else if (!is.na(resultados$sentimiento_gemini[j])) {
          resultados$sentimiento_final[j] <- resultados$sentimiento_gemini[j]
        } else if (!is.na(resultados$sentimiento_gpt[j])) {
          resultados$sentimiento_final[j] <- resultados$sentimiento_gpt[j]
        }
      } else if (!is.null(gemini_api_key)) {
        resultados$sentimiento_final[j] <- resultados$sentimiento_gemini[j]
      } else if (!is.null(openai_api_key)) {
        resultados$sentimiento_final[j] <- resultados$sentimiento_gpt[j]
      }
      
      # Combinar tópicos
      topicos_list <- c(
        if (!is.na(resultados$topicos_gemini[j])) str_split(resultados$topicos_gemini[j], "; ")[[1]] else NULL,
        if (!is.na(resultados$topicos_gpt[j])) str_split(resultados$topicos_gpt[j], "; ")[[1]] else NULL
      )
      if (length(topicos_list) > 0) {
        resultados$topicos_final[j] <- paste(unique(topicos_list), collapse = "; ")
      }
      
      resultados$procesado[j] <- TRUE
      
      # Delay para evitar rate limiting
      Sys.sleep(delay_seconds)
    }
    
    # Guardar progreso después de cada lote
    write_rds(resultados, file.path(OUT_DIR, "analisis_texto_progreso.rds"))
    cat("Progreso guardado. Lote", i, "completado.\n")
  }
  
  return(resultados)
}

# =============================================================
# 5) Función para ejecutar análisis (NO EJECUTAR AÚN)
# =============================================================

# ejecutar_analisis <- function() {
#   # Cargar datos
#   df_texto <- cargar_datos()
#   
#   # Cargar API keys (desde variables de entorno)
#   gemini_key <- Sys.getenv("GEMINI_API_KEY")
#   openai_key <- Sys.getenv("OPENAI_API_KEY")
#   
#   if (gemini_key == "" && openai_key == "") {
#     stop("Se requiere al menos una API key configurada")
#   }
#   
#   # Procesar muestra inicial (ejemplo: 100 textos)
#   resultados <- procesar_textos(
#     df_texto = df_texto,
#     gemini_api_key = if (gemini_key != "") gemini_key else NULL,
#     openai_api_key = if (openai_key != "") openai_key else NULL,
#     n_muestra = 100,  # Empezar con muestra pequeña
#     batch_size = 10,
#     delay_seconds = 2  # 2 segundos entre requests
#   )
#   
#   # Guardar resultados finales
#   write_rds(resultados, file.path(OUT_DIR, "analisis_texto_completo.rds"))
#   write_csv(resultados, file.path(OUT_DIR, "analisis_texto_completo.csv"))
#   
#   cat("Análisis completado. Resultados guardados en", OUT_DIR, "\n")
#   
#   return(resultados)
# }

# =============================================================
# NOTA FINAL
# =============================================================
# 
# Este script está preparado pero NO debe ejecutarse todavía.
# 
# Antes de ejecutar:
# 1. Configurar variables de entorno con las API keys
# 2. Revisar límites de rate limiting de ambas APIs
# 3. Estimar costos de procesamiento
# 4. Considerar procesar por lotes más pequeños
# 5. Implementar sistema de reintentos más robusto
# 
# Para ejecutar en el futuro:
# - Descomentar la función ejecutar_analisis()
# - Configurar las API keys
# - Ejecutar: ejecutar_analisis()
#
# =============================================================

cat("\n=== Script de análisis de texto con APIs ===\n")
cat("Estado: Preparado pero NO ejecutado\n")
cat("Requisitos: API keys de Gemini y/o OpenAI\n")
cat("Ubicación:", here("scripts/analysis/analisis_texto_apis.R"), "\n\n")



















