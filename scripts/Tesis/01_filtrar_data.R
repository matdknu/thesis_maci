# =============================================================
# 0) Setup -----------------------------------------------------
# =============================================================
rm(list = ls())

pacman::p_load(
  tidyverse, stringr, lubridate, here,
  tidygraph, ggraph, widyr, scales, readr, sjmisc
)

set.seed(123)

# Rutas - Usando datos unificados más actualizados
# Los datos han sido unificados de project_reddit y thesis_reddit, eliminando duplicados
# Ver DATA_MERGE_REPORT.md para más detalles
PATH_GENERAL <- here("data/raw", "reddit_comentarios.csv")
PATH_DERECHA <- here("data/raw", "reddit_comentarios_derecha.csv")
OUT_DIR      <- here("outputs")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# Verificar que los archivos existen
if (!file.exists(PATH_GENERAL)) {
  stop("Error: No se encuentra ", PATH_GENERAL, 
       "\nAsegúrate de haber ejecutado scripts/merge_raw_data.py primero")
}
if (!file.exists(PATH_DERECHA)) {
  warning("Advertencia: No se encuentra ", PATH_DERECHA)
}

# Helper para guardar en PNG
save_png <- function(plot, filename, width_cm = 27, height_cm = 22, dpi = 300) {
  ggsave(filename = here(OUT_DIR, filename),
         plot = plot, width = width_cm, height = height_cm, units = "cm", dpi = dpi)
}

# Tema base
theme_base <- theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold", size = 14, hjust = 0.5),
    plot.subtitle = element_text(size = 12, hjust = 0.5),
    plot.caption  = element_text(size = 10, hjust = 0),
    axis.title.x  = element_text(face = "bold"),
    axis.title.y  = element_text(face = "bold"),
    axis.text.x   = element_text(angle = 30, hjust = 1),
    legend.title  = element_text(face = "bold"),
    legend.position = "bottom"
  )

# =============================================================
# 1) Carga y unión de datos -----------------------------------
# =============================================================
# NOTA: Los datos han sido unificados de project_reddit y thesis_reddit
# eliminando duplicados. Ver DATA_MERGE_REPORT.md para detalles.
# 
# Opción: Usar Parquet si está disponible (más rápido para archivos grandes)
# Descomentar las siguientes líneas si prefieres usar Parquet:
# library(arrow)
# reddit_general <- read_parquet(here("data/raw", "reddit_comentarios.parquet"))
# reddit_derecha <- read_parquet(here("data/raw", "reddit_comentarios_derecha.parquet"))

reddit_union <- bind_rows(
  readr::read_csv(PATH_GENERAL, show_col_types = FALSE) %>% mutate(dataset = "general"),
  readr::read_csv(PATH_DERECHA, show_col_types = FALSE) %>% mutate(dataset = "derecha")
)

glimpse(reddit_union)

# =============================================================
# 2) Patrones y utilidades ------------------------------------
# =============================================================
# Definición de patrones (insensibles a mayúsculas/tildes)
# Definición de patrones (insensibles a mayúsculas/tildes)
patrones <- tribble(
  ~candidato, ~patron,
  "kast",    "\\bj(os[eé])\\s*antonio\\s*kast\\b|\\bkast\\b",
  "kaiser",  "\\bjohannes\\s*kaiser\\b|\\bkaiser\\b",
  "matthei", "\\bevelyn\\s*matthei\\b|\\bmatthei\\b",
  "jara",    "\\bjeann?ette?\\s*jara\\b|\\bjara\\b",
  "parisi",  "\\bfranco\\s*parisi\\b|\\bparisi\\b",
  
  # --- Nuevos ---
  "mayne_nicholls", "\\bharold\\s*mayne[\\s-]*nicholls\\b|\\bmayne[\\s-]*nicholls\\b|\\bharold\\b",
  "meo",            "\\bmarco\\s+enr[ií]quez[\\s-]*ominami\\b|\\bmeo\\b",
  "artes",          "\\beduardo\\s*art[eé]s\\b|\\bart[eé]s\\b|\\bprofe\\s*art[eé]s\\b"
)

# Función: detectar si un texto menciona ALGÚN candidato
detect_any <- function(x) {
  reduce(patrones$patron, ~ .x | str_detect(x, regex(.y, ignore_case = TRUE)), .init = FALSE)
}

# Función: crear variables binarias por candidato en un df
flag_personajes <- function(df, titulo_col = post_title, cuerpo_col = comment_body) {
  titulo <- enquo(titulo_col); cuerpo <- enquo(cuerpo_col)
  reduce(patrones$candidato, .init = df, .f = function(d, nm) {
    pat <- patrones %>% filter(candidato == nm) %>% pull(patron)
    d %>% mutate("{nm}" := as.integer(
      str_detect(coalesce(!!titulo, ""), regex(pat, ignore_case = TRUE)) |
        str_detect(coalesce(!!cuerpo, ""), regex(pat, ignore_case = TRUE))
    ))
  })
}

# =============================================================
# 3) Filtrado y variables clave -------------------------------
# =============================================================
reddit_filtrado <-
  reddit_union %>%
  filter(
    detect_any(coalesce(post_title,   "")) |
      detect_any(coalesce(comment_body, ""))
  ) %>%
  transmute(
    post_id, post_title, post_selftext,
    post_created, post_author,
    comment_author, comment_body, comment_score,
    fecha = as.Date(post_created)
  ) %>%
  flag_personajes(post_title, comment_body)

glimpse(reddit_filtrado)


# Guardar datos procesados en la nueva estructura
write_rds(reddit_filtrado, here("data/processed/reddit_filtrado.rds"))
