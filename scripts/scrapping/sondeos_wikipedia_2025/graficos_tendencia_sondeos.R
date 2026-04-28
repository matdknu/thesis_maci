#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(lubridate)
  library(tidyr)
  library(ggplot2)
})

# Operador util
`%||%` <- function(a, b) if (!is.null(a)) a else b

# -------------------------------------------------------------------
# Configuracion de rutas (relativas a este script)
# -------------------------------------------------------------------
args <- commandArgs(trailingOnly = FALSE)
file_arg <- args[grepl("^--file=", args)]
if (length(file_arg) > 0) {
  # Caso normal: ejecutado con Rscript --file=...
  script_path <- sub("^--file=", "", file_arg[1])
  script_dir <- dirname(normalizePath(script_path, mustWork = FALSE))
  repo_root <- normalizePath(file.path(script_dir, "..", "..", ".."), mustWork = FALSE)
} else {
  # Caso interactivo: source(...) en consola R
  # Asumimos que el usuario esta parado en la raiz del repo.
  repo_root <- normalizePath(getwd(), mustWork = FALSE)
}
data_dir <- file.path(repo_root, "data", "raw", "sondeos_wikipedia_2025", "consolidado")
out_dir <- file.path(repo_root, "data", "raw", "sondeos_wikipedia_2025", "graficos")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

csv_primera <- file.path(data_dir, "primera_vuelta.csv")
csv_segunda <- file.path(data_dir, "segunda_vuelta.csv")

if (!file.exists(csv_primera) || !file.exists(csv_segunda)) {
  stop("No se encontraron los CSV consolidados. Ejecuta primero el scraper de Wikipedia.")
}

# -------------------------------------------------------------------
# Helpers de limpieza
# -------------------------------------------------------------------
to_ascii_lower <- function(x) {
  x %>%
    iconv(from = "UTF-8", to = "ASCII//TRANSLIT") %>%
    tolower()
}

find_date_col <- function(df) {
  nms <- names(df)
  nms_ascii <- to_ascii_lower(nms)
  idx <- which(str_detect(nms_ascii, "fecha|date"))
  if (length(idx) == 0) {
    stop("No se encontro columna de fecha.")
  }
  nms[idx[1]]
}

find_pollster_col <- function(df) {
  nms <- names(df)
  nms_ascii <- to_ascii_lower(nms)
  idx <- which(str_detect(nms_ascii, "encuesta"))
  if (length(idx) == 0) {
    return(NULL)
  }
  nms[idx[1]]
}

parse_fecha <- function(x) {
  # Intenta varios formatos comunes en tablas de sondeos
  suppressWarnings(parse_date_time(
    x,
    orders = c(
      "dmy", "ymd", "mdy",
      "d b Y", "d B Y",
      "Y-m-d", "d/m/Y", "d-m-Y"
    )
  ))
}

clean_numeric <- function(x) {
  x %>%
    as.character() %>%
    str_replace_all("%", "") %>%
    str_replace_all(",", ".") %>%
    str_replace_all("[^0-9\\.\\-]", "") %>%
    na_if("") %>%
    as.numeric() %>%
    # Blindaje: intencion de voto valida en 0-100.
    # Evita falsos positivos como "10/2025" -> 102025.
    { ifelse(. >= 0 & . <= 100, ., NA_real_) }
}

to_long_numeric <- function(df, fecha_col) {
  pollster_col <- find_pollster_col(df)

  out <- df
  if (!is.null(pollster_col)) {
    out <- out %>%
      filter(
        !str_detect(
          to_ascii_lower(coalesce(as.character(.data[[pollster_col]]), "")),
          "debate|prohibicion|inicio de la franja|inicio de la prohibicion"
        )
      )
  }

  out %>%
    mutate(fecha = as.Date(parse_fecha(.data[[fecha_col]]))) %>%
    filter(!is.na(fecha)) %>%
    mutate(across(-all_of(c(fecha_col, "fecha", "_heading")), clean_numeric)) %>%
    pivot_longer(
      cols = -any_of(c(fecha_col, "fecha", "_heading")),
      names_to = "candidato",
      values_to = "valor"
    ) %>%
    mutate(candidato = canon_candidate(candidato)) %>%
    filter(candidato %in% target_candidates) %>%
    filter(!is.na(valor))
}

month_scale <- scale_x_date(
  date_breaks = "2 weeks",
  date_labels = "%d %b",
  expand = expansion(mult = c(0.01, 0.02))
)

cutoff_primera <- as.Date("2025-11-15")
inicio_segunda <- as.Date("2025-11-16")

pal_tesis <- c(
  "Evelyn Matthei" = "#6f42c1",
  "Johannes Kaiser" = "#198754",
  "José Antonio Kast" = "#0d6efd",
  "Jeannette Jara" = "#dc3545"
)

theme_tesis <- function() {
  theme_minimal(base_size = 12, base_family = "sans") +
    theme(
      plot.title = element_text(face = "bold", size = 16, color = "#1a1a1a"),
      plot.subtitle = element_text(size = 11.5, color = "#4d4d4d"),
      plot.caption = element_text(size = 9, color = "#6b7280"),
      axis.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1),
      panel.grid.major = element_line(color = "#e5e7eb", linewidth = 0.45),
      panel.grid.minor = element_blank(),
      legend.position = "right",
      legend.title = element_text(face = "bold"),
      legend.key.height = unit(0.55, "cm"),
      plot.margin = margin(10, 14, 10, 10)
    )
}

target_candidates <- c(
  "Evelyn Matthei",
  "Johannes Kaiser",
  "José Antonio Kast",
  "Jeannette Jara"
)

canon_candidate <- function(candidato) {
  cand_ascii <- to_ascii_lower(candidato)
  case_when(
    str_detect(cand_ascii, "matthei") ~ "Evelyn Matthei",
    str_detect(cand_ascii, "kaiser") ~ "Johannes Kaiser",
    str_detect(cand_ascii, "kast") ~ "José Antonio Kast",
    str_detect(cand_ascii, "jara") ~ "Jeannette Jara",
    TRUE ~ candidato
  )
}

to_biweekly <- function(fecha_vec) {
  semana <- floor_date(fecha_vec, unit = "week", week_start = 1)
  base <- min(semana, na.rm = TRUE)
  idx <- as.integer(difftime(semana, base, units = "weeks"))
  base + weeks((idx %/% 2) * 2)
}

# -------------------------------------------------------------------
# Primera vuelta: candidatos disponibles
# -------------------------------------------------------------------
primera <- read_csv(csv_primera, show_col_types = FALSE)
fecha_primera_col <- find_date_col(primera)

primera_long <- to_long_numeric(primera, fecha_primera_col) %>%
  filter(month(fecha) >= 8) %>%
  filter(fecha <= cutoff_primera) %>%
  mutate(fecha_bisemana = to_biweekly(fecha)) %>%
  group_by(fecha_bisemana, candidato) %>%
  summarise(valor = mean(valor, na.rm = TRUE), .groups = "drop") %>%
  rename(fecha = fecha_bisemana) %>%
  group_by(fecha, candidato) %>%
  summarise(valor = mean(valor, na.rm = TRUE), .groups = "drop")

# -------------------------------------------------------------------
# Segunda vuelta: solo Kast y Jara
# -------------------------------------------------------------------
segunda <- read_csv(csv_segunda, show_col_types = FALSE)
fecha_segunda_col <- find_date_col(segunda)

segunda_long <- to_long_numeric(segunda, fecha_segunda_col) %>%
  filter(candidato %in% c("José Antonio Kast", "Jeannette Jara")) %>%
  filter(month(fecha) >= 8) %>%
  filter(fecha >= inicio_segunda) %>%
  mutate(fecha_bisemana = to_biweekly(fecha)) %>%
  group_by(fecha_bisemana, candidato) %>%
  summarise(valor = mean(valor, na.rm = TRUE), .groups = "drop") %>%
  rename(fecha = fecha_bisemana) %>%
  group_by(fecha, candidato) %>%
  summarise(valor = mean(valor, na.rm = TRUE), .groups = "drop")

if (nrow(segunda_long) == 0 || nrow(primera_long) == 0) {
  warning("No se detectaron columnas de Kast/Jara en segunda vuelta. Revisar encabezados.")
} else {
  df_plot <- bind_rows(primera_long, segunda_long)
  y_max <- max(df_plot$valor, na.rm = TRUE)

  g_panel <- ggplot(df_plot, aes(x = fecha, y = valor, color = candidato)) +
    geom_line(alpha = 0.8, linewidth = 0.9) +
    geom_point(alpha = 0.85, size = 2) +
    geom_vline(xintercept = inicio_segunda, linetype = "dashed", color = "#6b7280", linewidth = 0.9) +
    annotate(
      "label",
      x = inicio_segunda + 3,
      y = y_max * 0.97,
      label = "Inicio segunda vuelta\n(16 nov 2025)",
      hjust = 0,
      vjust = 1,
      size = 3.3,
      label.size = 0.2,
      label.r = unit(0.15, "lines"),
      fill = "white",
      color = "#374151"
    ) +
    month_scale +
    scale_color_manual(values = pal_tesis) +
    labs(
      title = "Tendencia de sondeos presidenciales 2025",
      subtitle = "Serie bi-semanal en un solo gráfico con corte a segunda vuelta",
      x = "Fecha",
      y = "Intención de voto (%)",
      color = "Candidatura",
      caption = "Consolidación de encuesta Cadem, Activa, Criteria, ICSO - UDP (Imputación promedial)."
    ) +
    theme_tesis()

  ggsave(
    filename = file.path(out_dir, "tendencia_panel_bisemanal_primera_segunda.png"),
    plot = g_panel,
    width = 12,
    height = 7.5,
    dpi = 320,
    bg = "white"
  )
}

message("Graficos generados en: ", out_dir)
