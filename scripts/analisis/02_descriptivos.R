# =============================================================
# 01) Estadísticas descriptivas + visualizaciones (unificado)
# Incluye tablas resumen, export CSV y figuras en español a color.
# Lee: data/processed/reddit_filtrado.rds (y Trends si existe)
# =============================================================

pacman::p_load(
  tidyverse, lubridate, here, readr, scales,
  ggtext, patchwork, jtools, viridis
)

set.seed(123)

suppressWarnings({
  try(Sys.setlocale("LC_TIME", "es_ES.UTF-8"), silent = TRUE)
  try(Sys.setlocale("LC_TIME", "es_CL.UTF-8"), silent = TRUE)
})

OUT_DIR <- here("outputs", "thesis_figures")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# Etiquetas de fechas en español (fallback si LC_TIME no aplica)
lab_mes_es <- function(fmt = "%d %b") {
  mes_es <- c(
    "ene", "feb", "mar", "abr", "may", "jun",
    "jul", "ago", "sep", "oct", "nov", "dic"
  )
  function(x) {
    d <- format(x, "%d")
    m <- mes_es[as.integer(format(x, "%m"))]
    y <- format(x, "%Y")
    paste(d, m, y)
  }
}

# Base theme for thesis using theme_apa from jtools
# Reference: https://jtools.jacob-long.com/reference/theme_apa
theme_thesis <- function(legend.pos = "bottom", ...) {
  theme_apa(
    legend.pos = legend.pos,
    legend.use.title = FALSE,
    legend.font.size = 12,
    x.font.size = 12,
    y.font.size = 12,
    facet.title.size = 12,
    remove.y.gridlines = TRUE,
    remove.x.gridlines = TRUE,
    ...
  ) +
    theme(
      plot.title = element_text(hjust = 0.5, margin = margin(b = 8)),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40", margin = margin(b = 12)),
      plot.caption = element_text(hjust = 0, color = "grey50", margin = margin(t = 8)),
      axis.text.x = element_text(angle = 45, hjust = 1),
      plot.margin = margin(10, 15, 10, 15)
    )
}

# Function to save plots
save_thesis_fig <- function(plot, filename, width_cm = 16, height_cm = 12, dpi = 300) {
  ggsave(
    filename = file.path(OUT_DIR, filename),
    plot = plot,
    width = width_cm,
    height = height_cm,
    units = "cm",
    dpi = dpi
  )
}

# =============================================================
# 1) Data loading
# =============================================================
cat("\n📂 Cargando datos...\n")
df <- readRDS(here("data/processed/reddit_filtrado.rds"))
cat(sprintf("   ✅ Reddit datos cargados: %d filas\n", nrow(df)))

CAND_KEYS <- intersect(
  c("kast", "kaiser", "matthei", "jara", "parisi", "mayne_nicholls"),
  names(df)
)
if (length(CAND_KEYS) < 1L) {
  stop("No se encontraron columnas de candidatos en reddit_filtrado.rds.")
}
CAND_LABEL <- c(
  kast = "Kast", kaiser = "Kaiser", matthei = "Matthei", jara = "Jara",
  parisi = "Parisi", mayne_nicholls = "Mayne"
)
orden_cand <- c("Kast", "Kaiser", "Matthei", "Jara", "Parisi", "Mayne")
nombres_candidatos <- intersect(orden_cand, unname(CAND_LABEL[CAND_KEYS]))
colores_candidatos <- setNames(
  c("#0072B2", "#E69F00", "#009E73", "#CC79A7", "#D55E00", "#56B4E9")[seq_along(nombres_candidatos)],
  nombres_candidatos
)
tipos_linea <- setNames(
  c("solid", "dashed", "dotted", "dotdash", "longdash", "twodash")[seq_along(nombres_candidatos)],
  nombres_candidatos
)

# Cargar trends si existe
df_trends <- NULL
trends_path <- here("data/trends/series/trends_candidatos_daily.csv")
if (file.exists(trends_path)) {
  df_trends <- read_csv(trends_path, show_col_types = FALSE)
  cat(sprintf("   ✅ Google Trends datos cargados: %d filas\n", nrow(df_trends)))
} else {
  cat("   ⚠️ Google Trends no encontrado, se omitirán gráficos relacionados\n")
}

# =============================================================
# 2–4) Distribución total y series temporales (figuras 1–3)
# =============================================================
menciones_totales <- df %>%
  summarise(across(all_of(CAND_KEYS), ~ sum(.x, na.rm = TRUE))) %>%
  pivot_longer(everything(), names_to = "cand_key", values_to = "menciones") %>%
  mutate(
    candidato = factor(CAND_LABEL[cand_key], levels = nombres_candidatos),
    candidato = fct_reorder(candidato, menciones, .desc = TRUE),
    pct = menciones / sum(menciones) * 100
  )

fig1 <- menciones_totales %>%
  ggplot(aes(x = candidato, y = menciones, fill = candidato)) +
  geom_col(alpha = 0.9, show.legend = FALSE, color = "white", linewidth = 0.35) +
  geom_text(
    aes(label = paste0(format(menciones, big.mark = ".", decimal.mark = ","), "\n(", round(pct, 1), "%)")),
    vjust = -0.25,
    size = 3.2,
    lineheight = 0.9,
    color = "gray20"
  ) +
  scale_fill_manual(values = colores_candidatos) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.18))
  ) +
  labs(
    title = "Distribución total de menciones por candidato",
    subtitle = "Reddit: corpus filtrado por menciones a candidaturas de interés",
    x = NULL,
    y = "Número de menciones",
    caption = "Nota. Los porcentajes entre paréntesis son la proporción sobre el total de menciones."
  ) +
  theme_thesis()

save_thesis_fig(fig1, "fig1_distribucion_menciones.png", width_cm = 14, height_cm = 10)

menciones_por_fecha <- df %>%
  group_by(fecha) %>%
  summarise(across(all_of(CAND_KEYS), ~ sum(.x, na.rm = TRUE)), .groups = "drop") %>%
  pivot_longer(-fecha, names_to = "cand_key", values_to = "menciones") %>%
  mutate(candidato = factor(CAND_LABEL[cand_key], levels = nombres_candidatos)) %>%
  filter(!is.na(fecha))

fig2 <- menciones_por_fecha %>%
  ggplot(aes(x = fecha, y = menciones, color = candidato, group = candidato)) +
  geom_line(linewidth = 0.95, alpha = 0.95) +
  geom_point(size = 1.8, alpha = 0.85) +
  scale_color_manual(values = colores_candidatos, name = "Candidato") +
  scale_x_date(
    date_breaks = "2 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Evolución temporal de menciones diarias",
    subtitle = "Serie diaria de menciones en Reddit por candidato",
    x = "Fecha",
    y = "Número de menciones",
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis(legend.pos = "right") +
  theme(legend.box.margin = margin(l = 10))

save_thesis_fig(fig2, "fig2_evolucion_temporal.png", width_cm = 18, height_cm = 10)

ncol_facet <- if (length(nombres_candidatos) <= 4) 2L else 3L
fig3 <- menciones_por_fecha %>%
  ggplot(aes(x = fecha, y = menciones, color = candidato, group = candidato)) +
  geom_line(linewidth = 1.05, show.legend = FALSE) +
  geom_point(size = 1.5, alpha = 0.75, show.legend = FALSE) +
  facet_wrap(~ candidato, ncol = ncol_facet, scales = "free_y") +
  scale_color_manual(values = colores_candidatos) +
  scale_x_date(
    date_breaks = "3 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.12))
  ) +
  labs(
    title = "Evolución temporal de menciones por candidato",
    subtitle = "Paneles separados para comparar la forma de cada serie",
    x = "Fecha",
    y = "Número de menciones",
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis() +
  theme(
    strip.background = element_rect(fill = "grey95", color = NA),
    strip.text = element_text(margin = margin(5, 0, 5, 0))
  )

save_thesis_fig(fig3, "fig3_small_multiples.png", width_cm = 20, height_cm = 14)

# =============================================================
# 5) Figure 4: Google Trends
# =============================================================
# Inicializar trends_long como NULL
trends_long <- NULL

if (!is.null(df_trends)) {
  trends_long <- df_trends %>%
    pivot_longer(-date, names_to = "candidato", values_to = "score") %>%
    filter(!is.na(date), !is.na(score)) %>%
    mutate(
      candidato_short = case_when(
        str_detect(candidato, "Matthei") ~ "Matthei",
        str_detect(candidato, "Kast") ~ "Kast",
        str_detect(candidato, "Kaiser") ~ "Kaiser",
        str_detect(candidato, "Jara") ~ "Jara",
        str_detect(candidato, "Parisi") ~ "Parisi",
        str_detect(candidato, "Mayne") ~ "Mayne",
        TRUE ~ candidato
      )
    ) %>%
    filter(candidato_short %in% nombres_candidatos)
  
  fig4 <- trends_long %>%
    ggplot(aes(x = date, y = score, color = candidato_short, group = candidato_short)) +
    geom_line(linewidth = 0.95, alpha = 0.95) +
    geom_point(size = 1.8, alpha = 0.85) +
    scale_color_manual(values = colores_candidatos, name = "Candidato") +
    scale_x_date(
      date_breaks = "1 month",
      labels = lab_mes_es(),
      expand = expansion(mult = 0.02)
    ) +
    scale_y_continuous(
      labels = label_number(big.mark = ".", decimal.mark = ","),
      expand = expansion(mult = c(0, 0.08)),
      limits = c(0, 100)
    ) +
    labs(
      title = "Evolución del interés en Google Trends",
      subtitle = "Interés relativo de búsqueda por candidato (escala 0–100)",
      x = "Fecha",
      y = "Interés relativo",
      caption = "Fuente: Google Trends. Elaboración propia."
    ) +
    theme_thesis(legend.pos = "right") +
    theme(legend.box.margin = margin(l = 10))
  
  fig4
  save_thesis_fig(fig4, "fig4_google_trends.png", width_cm = 18, height_cm = 10)
}

# =============================================================
# 6) Figure 5: Reddit vs Google Trends comparison
# =============================================================
comparacion <- NULL

if (!is.null(df_trends) && !is.null(trends_long)) {
  menciones_semanales <- menciones_por_fecha %>%
    mutate(semana = floor_date(fecha, "week", week_start = 1)) %>%
    group_by(semana, candidato) %>%
    summarise(menciones = mean(menciones, na.rm = TRUE), .groups = "drop")
  
  trends_semanales <- trends_long %>%
    mutate(semana = floor_date(date, "week", week_start = 1)) %>%
    group_by(semana, candidato_short) %>%
    summarise(score = mean(score, na.rm = TRUE), .groups = "drop") %>%
    rename(candidato = candidato_short)
  
  comparacion <- menciones_semanales %>%
    inner_join(trends_semanales, by = c("semana", "candidato")) %>%
    filter(!is.na(semana), !is.na(menciones), !is.na(score))
  
  if (nrow(comparacion) > 0) {
    fig5 <- comparacion %>%
      mutate(candidato = factor(candidato, levels = nombres_candidatos)) %>%
      ggplot(aes(x = menciones, y = score)) +
      geom_point(aes(color = candidato), alpha = 0.78, size = 2.6) +
      geom_smooth(method = "lm", se = TRUE, alpha = 0.22, linewidth = 0.85, color = "gray35", fill = "gray80") +
      scale_color_manual(values = colores_candidatos, name = "Candidato", guide = "none") +
      facet_wrap(~ candidato, ncol = 2, scales = "free") +
      labs(
        title = "Relación entre menciones en Reddit e interés en Google Trends",
        subtitle = "Puntos semanales con intervalo de confianza del 95 %",
        x = "Menciones promedio semanal (Reddit)",
        y = "Interés promedio semanal (Google Trends)",
        caption = "Fuente: elaboración propia. Reddit: scraping propio; Google Trends: API oficial."
      ) +
      theme_thesis() +
      theme(
        strip.background = element_rect(fill = "grey95", color = NA),
        strip.text = element_text(margin = margin(5, 0, 5, 0))
      )
    
    fig5
    save_thesis_fig(fig5, "fig5_comparacion_reddit_trends.png", width_cm = 20, height_cm = 14)
  }
}

# =============================================================
# 7) Figure 6: Weekly activity heatmap
# =============================================================
menciones_semanales_wide <- menciones_por_fecha %>%
  mutate(
    semana = floor_date(fecha, "week", week_start = 1),
    mes = month(fecha, label = TRUE, abbr = TRUE),
    semana_mes = week(fecha) - week(floor_date(fecha, "month")) + 1
  ) %>%
  group_by(semana, candidato) %>%
  summarise(menciones = mean(menciones, na.rm = TRUE), .groups = "drop") %>%
  mutate(
    semana_num = as.numeric(semana - min(semana)) %/% 7,
    candidato = factor(candidato, levels = nombres_candidatos)
  )

fig6 <- menciones_semanales_wide %>%
  mutate(candidato = factor(candidato, levels = nombres_candidatos)) %>%
  ggplot(aes(x = semana, y = candidato, fill = menciones)) +
  geom_tile(color = "white", linewidth = 0.3) +
  scale_fill_viridis_c(
    option = "C",
    labels = label_number(big.mark = ".", decimal.mark = ","),
    name = "Menciones\npromedio"
  ) +
  scale_x_date(
    date_breaks = "2 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0)
  ) +
  labs(
    title = "Mapa de calor: actividad semanal por candidato",
    subtitle = "Intensidad de menciones en Reddit a lo largo del tiempo",
    x = "Semana",
    y = NULL,
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis(legend.pos = "right") +
  theme(
    axis.text.y = element_text(face = "bold"),
    legend.key.height = unit(1.5, "cm")
  )

fig6
save_thesis_fig(fig6, "fig6_heatmap_actividad.png", width_cm = 20, height_cm = 10)

# =============================================================
# 8) Estadísticos Descriptivos Completos
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📊 ESTADÍSTICOS DESCRIPTIVOS COMPLETOS\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Resumen general del dataset
cat("\n📈 RESUMEN GENERAL:\n")
cat(sprintf("Total de comentarios: %s\n", format(nrow(df), big.mark = ".", decimal.mark = ",")))
cat(sprintf("Período: %s a %s\n", 
            min(df$fecha, na.rm = TRUE), 
            max(df$fecha, na.rm = TRUE)))
cat(sprintf("Rango temporal: %d días\n", 
            as.numeric(max(df$fecha, na.rm = TRUE) - min(df$fecha, na.rm = TRUE))))

# Usuarios únicos
n_usuarios <- n_distinct(df$comment_author[df$comment_author != "[deleted]"], na.rm = TRUE)
cat(sprintf("Usuarios únicos: %s\n", format(n_usuarios, big.mark = ".", decimal.mark = ",")))

# Posts únicos
n_posts <- n_distinct(df$post_id, na.rm = TRUE)
cat(sprintf("Posts únicos: %s\n", format(n_posts, big.mark = ".", decimal.mark = ",")))

# Count total a lo largo del tiempo
cat("\n📅 COUNT TOTAL A LO LARGO DEL TIEMPO:\n")
count_por_fecha <- df %>%
  filter(!is.na(fecha)) %>%
  group_by(fecha) %>%
  summarise(
    total_comentarios = n(),
    total_menciones = sum(rowSums(across(all_of(CAND_KEYS))), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    semana = floor_date(fecha, "week", week_start = 1),
    mes = floor_date(fecha, "month")
  )

# Estadísticos diarios
stats_diarios <- count_por_fecha %>%
  summarise(
    media_comentarios_dia = mean(total_comentarios, na.rm = TRUE),
    mediana_comentarios_dia = median(total_comentarios, na.rm = TRUE),
    sd_comentarios_dia = sd(total_comentarios, na.rm = TRUE),
    min_comentarios_dia = min(total_comentarios, na.rm = TRUE),
    max_comentarios_dia = max(total_comentarios, na.rm = TRUE),
    media_menciones_dia = mean(total_menciones, na.rm = TRUE),
    mediana_menciones_dia = median(total_menciones, na.rm = TRUE),
    max_menciones_dia = max(total_menciones, na.rm = TRUE)
  )

cat("\nEstadísticos diarios:\n")
print(stats_diarios)

# Estadísticos semanales
stats_semanales <- count_por_fecha %>%
  group_by(semana) %>%
  summarise(
    total_comentarios = sum(total_comentarios, na.rm = TRUE),
    total_menciones = sum(total_menciones, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  summarise(
    media_comentarios_semana = mean(total_comentarios, na.rm = TRUE),
    mediana_comentarios_semana = median(total_comentarios, na.rm = TRUE),
    max_comentarios_semana = max(total_comentarios, na.rm = TRUE),
    media_menciones_semana = mean(total_menciones, na.rm = TRUE),
    max_menciones_semana = max(total_menciones, na.rm = TRUE)
  )

cat("\nEstadísticos semanales:\n")
print(stats_semanales)

# Estadísticos mensuales
stats_mensuales <- count_por_fecha %>%
  group_by(mes) %>%
  summarise(
    total_comentarios = sum(total_comentarios, na.rm = TRUE),
    total_menciones = sum(total_menciones, na.rm = TRUE),
    dias = n(),
    .groups = "drop"
  ) %>%
  mutate(
    comentarios_por_dia = total_comentarios / dias,
    menciones_por_dia = total_menciones / dias
  )

cat("\nEstadísticos mensuales:\n")
print(stats_mensuales)

# Guardar estadísticos
write_csv(stats_diarios, file.path(OUT_DIR, "estadisticos_diarios.csv"))
write_csv(stats_semanales, file.path(OUT_DIR, "estadisticos_semanales.csv"))
write_csv(stats_mensuales, file.path(OUT_DIR, "estadisticos_mensuales.csv"))
write_csv(count_por_fecha, file.path(OUT_DIR, "count_total_por_fecha.csv"))

# Gráfico: Count total a lo largo del tiempo
fig_count_total <- count_por_fecha %>%
  ggplot(aes(x = fecha, y = total_comentarios)) +
  geom_line(linewidth = 1.2, color = "#0072B2", alpha = 0.95) +
  geom_area(fill = "#56B4E9", alpha = 0.35) +
  scale_x_date(
    date_breaks = "2 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Total de comentarios en el tiempo",
    subtitle = "Serie diaria de todos los comentarios del corpus",
    x = "Fecha",
    y = "Número de comentarios",
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis()

fig_count_total

save_thesis_fig(fig_count_total, "fig_count_total_tiempo.png", width_cm = 18, height_cm = 10)

# Gráfico: Count total de menciones a lo largo del tiempo
fig_menciones_total <- count_por_fecha %>%
  ggplot(aes(x = fecha, y = total_menciones)) +
  geom_line(linewidth = 1.2, color = "#009E73", alpha = 0.95) +
  geom_area(fill = "#69DB7C", alpha = 0.35) +
  scale_x_date(
    date_breaks = "2 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Total de menciones a candidatos en el tiempo",
    subtitle = "Serie diaria de menciones (suma de todas las candidaturas)",
    x = "Fecha",
    y = "Número de menciones",
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis()

save_thesis_fig(fig_menciones_total, "fig_menciones_total_tiempo.png", width_cm = 18, height_cm = 10)

# =============================================================
# 9) Visualizaciones descriptivas adicionales: Count total por candidato
# =============================================================

# Preparar datos de menciones por fecha y candidato para visualizaciones
count_por_fecha_candidato <- df %>%
  filter(!is.na(fecha)) %>%
  group_by(fecha) %>%
  summarise(across(all_of(CAND_KEYS), ~ sum(.x, na.rm = TRUE)), .groups = "drop") %>%
  pivot_longer(-fecha, names_to = "cand_key", values_to = "count") %>%
  mutate(
    candidato = factor(CAND_LABEL[cand_key], levels = nombres_candidatos),
    semana = floor_date(fecha, "week", week_start = 1)
  )

# 9.1) Gráfico apilado (stacked area) - Count total por candidato
fig_count_apilado <- count_por_fecha_candidato %>%
  ggplot(aes(x = fecha, y = count, fill = candidato)) +
  geom_area(alpha = 0.82, position = "stack", color = "white", linewidth = 0.15) +
  scale_fill_manual(values = colores_candidatos, name = "Candidato") +
  scale_x_date(
    date_breaks = "2 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    title = "Áreas apiladas: menciones por candidato en el tiempo",
    subtitle = "Menciones diarias apiladas por candidato",
    x = "Fecha",
    y = "Número de menciones",
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis(legend.pos = "bottom")

save_thesis_fig(fig_count_apilado, "fig_count_apilado_candidatos.png", width_cm = 18, height_cm = 12)

# 9.2) Gráfico apilado (stacked bar) semanal - Count total por candidato
count_semanal_candidato <- count_por_fecha_candidato %>%
  group_by(semana, candidato) %>%
  summarise(count = sum(count, na.rm = TRUE), .groups = "drop") %>%
  mutate(candidato = factor(candidato, levels = nombres_candidatos))

fig_count_apilado_bar <- count_semanal_candidato %>%
  ggplot(aes(x = semana, y = count, fill = candidato)) +
  geom_col(position = "stack", color = "white", linewidth = 0.2, alpha = 0.92) +
  scale_fill_manual(values = colores_candidatos, name = "Candidato") +
  scale_x_date(
    date_breaks = "2 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    title = "Barras apiladas: menciones semanales por candidato",
    subtitle = "Agregación semanal de menciones (apiladas)",
    x = "Semana",
    y = "Número de menciones",
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis(legend.pos = "bottom")

save_thesis_fig(fig_count_apilado_bar, "fig_count_apilado_bar_semanal.png", width_cm = 18, height_cm = 12)

# 9.3) Gráfico por facet (small multiples) - Count total por candidato
# Crear transformación personalizada para valores grandes
threshold <- 1000
k <- 5  # compression factor for values > 1000

trans_compress_above_1000 <- trans_new(
  name = "compress_above_1000",
  transform = function(y) {
    y <- pmax(y, 0)
    ifelse(y <= threshold, y, threshold + (y - threshold) / k)
  },
  inverse = function(y) {
    y <- pmax(y, 0)
    ifelse(y <= threshold, y, threshold + (y - threshold) * k)
  }
)

fig_count_facet <- count_por_fecha_candidato %>%
  ggplot(aes(x = fecha, y = count, color = candidato, group = candidato)) +
  geom_line(linewidth = 1.05) +
  geom_area(aes(fill = candidato), alpha = 0.22) +
  facet_wrap(~ candidato, ncol = 2) +
  scale_color_manual(values = colores_candidatos, guide = "none") +
  scale_fill_manual(values = colores_candidatos, guide = "none") +
  scale_x_date(
    date_breaks = "3 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    trans  = trans_compress_above_1000,
    breaks = c(0, 250, 500, 750, 1000, 2000, 3000, 4000),
    labels = label_number(big.mark = ".", decimal.mark = ",")
  ) +
  labs(
    title = "Menciones por candidato en el tiempo (paneles)",
    subtitle = "Cada panel muestra la serie diaria de un candidato",
    x = "Fecha",
    y = "Número de menciones",
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis()

save_thesis_fig(fig_count_facet, "fig_count_facet_candidatos.png", width_cm = 20, height_cm = 14)

count_semanal_heatmap_share <- count_por_fecha_candidato %>%
  group_by(semana, candidato) %>%
  summarise(count = sum(count, na.rm = TRUE), .groups = "drop") %>%
  group_by(semana) %>%
  mutate(
    share = count / sum(count, na.rm = TRUE),
    candidato = factor(candidato, levels = nombres_candidatos)
  ) %>%
  ungroup()

fig_count_heatmap_semanal <- count_semanal_heatmap_share %>%
  ggplot(aes(x = semana, y = candidato, fill = share)) +
  geom_tile(color = "white", linewidth = 0.5) +
  scale_fill_viridis_c(
    option = "B",
    labels = percent_format(accuracy = 1),
    name = "Participación\nsemanal"
  ) +
  scale_x_date(
    date_breaks = "2 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0)
  ) +
  labs(
    title = "Mapa de calor: participación semanal entre candidatos",
    subtitle = "Cada semana suma 100 % entre candidatos",
    x = "Semana",
    y = NULL,
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis(legend.pos = "right") +
  theme(
    axis.text.y = element_text(face = "bold"),
    legend.key.height = unit(2, "cm")
  )



count_semanal_heatmap_within_cand <- count_por_fecha_candidato %>%
  group_by(semana, candidato) %>%
  summarise(count = sum(count, na.rm = TRUE), .groups = "drop") %>%
  group_by(candidato) %>%
  mutate(
    share = count / sum(count, na.rm = TRUE),
    candidato = factor(candidato, levels = nombres_candidatos)
  ) %>%
  ungroup()

fig_count_heatmap_semanal_within <- count_semanal_heatmap_within_cand %>%
  ggplot(aes(x = semana, y = candidato, fill = share)) +
  geom_tile(color = "white", linewidth = 0.5) +
  scale_fill_viridis_c(
    option = "D",
    labels = percent_format(accuracy = 0.1),
    name = "Participación\ndel candidato"
  ) +
  scale_x_date(
    date_breaks = "2 weeks",
    labels = lab_mes_es(),
    expand = expansion(mult = 0)
  ) +
  labs(
    title = "Mapa de calor: distribución interna por candidato",
    subtitle = "Dentro de cada candidato, cómo se reparten sus menciones entre semanas",
    x = "Semana",
    y = NULL,
    caption = "Fuente: elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis(legend.pos = "right") +
  theme(
    axis.text.y = element_text(face = "bold"),
    legend.key.height = unit(2, "cm")
  )

save_thesis_fig(fig_count_heatmap_semanal, "fig_count_heatmap_semanal_candidatos.png", width_cm = 20, height_cm = 10)

# Guardar también el heatmap within-candidate
save_thesis_fig(fig_count_heatmap_semanal_within, "fig_count_heatmap_semanal_within_candidatos.png", width_cm = 20, height_cm = 10)

# =============================================================
# 10) Visualizaciones descriptivas de Google Trends
# =============================================================
if (!is.null(df_trends) && !is.null(trends_long)) {
  
  # Preparar datos semanales de trends
  trends_semanales_long <- trends_long %>%
    mutate(semana = floor_date(date, "week", week_start = 1)) %>%
    group_by(semana, candidato_short) %>%
    summarise(score = mean(score, na.rm = TRUE), .groups = "drop") %>%
    rename(candidato = candidato_short) %>%
    mutate(candidato = factor(candidato, levels = nombres_candidatos)) %>%
    filter(!is.na(semana), !is.na(score))
  
  # 10.1) Gráfico apilado (stacked area) - Google Trends
  fig_trends_apilado <- trends_long %>%
    mutate(candidato_short = factor(candidato_short, levels = nombres_candidatos)) %>%
    ggplot(aes(x = date, y = score, fill = candidato_short)) +
    geom_area(alpha = 0.82, position = "stack", color = "white", linewidth = 0.12) +
    scale_fill_manual(values = colores_candidatos, name = "Candidato") +
    scale_x_date(
      date_breaks = "1 month",
      labels = lab_mes_es(),
      expand = expansion(mult = 0.02)
    ) +
    scale_y_continuous(
      labels = label_number(big.mark = ".", decimal.mark = ","),
      expand = expansion(mult = c(0, 0.05)),
      limits = c(0, NA)
    ) +
    labs(
      title = "Google Trends: interés apilado por candidato",
      subtitle = "Interés de búsqueda diario apilado (escala 0–100)",
      x = "Fecha",
      y = "Interés relativo",
      caption = "Fuente: Google Trends. Elaboración propia."
    ) +
    theme_thesis(legend.pos = "bottom")
  
  save_thesis_fig(fig_trends_apilado, "fig_trends_apilado_candidatos.png", width_cm = 18, height_cm = 12)
  
  # 10.2) Gráfico por facet (small multiples) - Google Trends
  fig_trends_facet <- trends_long %>%
    mutate(candidato_short = factor(candidato_short, levels = nombres_candidatos)) %>%
    ggplot(aes(x = date, y = score, color = candidato_short, group = candidato_short)) +
    geom_line(linewidth = 1.05) +
    geom_area(aes(fill = candidato_short), alpha = 0.25) +
    facet_wrap(~ candidato_short, ncol = 2, scales = "free_y") +
    scale_color_manual(values = colores_candidatos, guide = "none") +
    scale_fill_manual(values = colores_candidatos, guide = "none") +
    scale_x_date(
      date_breaks = "2 months",
      labels = lab_mes_es(),
      expand = expansion(mult = 0.02)
    ) +
    scale_y_continuous(
      labels = label_number(big.mark = ".", decimal.mark = ","),
      expand = expansion(mult = c(0, 0.1)),
      limits = c(0, NA)
    ) +
    labs(
      title = "Google Trends: paneles por candidato",
      subtitle = "Tendencia del interés de búsqueda en cada candidato",
      x = "Fecha",
      y = "Interés relativo",
      caption = "Fuente: Google Trends. Elaboración propia."
    ) +
    theme_thesis() +
    theme(
      strip.background = element_rect(fill = "grey95", color = NA),
      strip.text = element_text(margin = margin(5, 0, 5, 0))
    )
  
  save_thesis_fig(fig_trends_facet, "fig_trends_facet_candidatos.png", width_cm = 20, height_cm = 14)
  
  # 10.3) Heatmap semanal - Google Trends
  fig_trends_heatmap_semanal <- trends_semanales_long %>%
    ggplot(aes(x = semana, y = candidato, fill = score)) +
    geom_tile(color = "white", linewidth = 0.5) +
    scale_fill_viridis_c(
      option = "C",
      labels = label_number(big.mark = ".", decimal.mark = ","),
      name = "Interés\nsemanal",
      limits = c(0, 100)
    ) +
    scale_x_date(
      date_breaks = "1 month",
      labels = lab_mes_es(),
      expand = expansion(mult = 0)
    ) +
    labs(
      title = "Mapa de calor: Google Trends por candidato (semanal)",
      subtitle = "Intensidad del interés agregado por semana",
      x = "Semana",
      y = NULL,
      caption = "Fuente: Google Trends. Elaboración propia."
    ) +
    theme_thesis(legend.pos = "right") +
    theme(
      axis.text.y = element_text(face = "bold"),
      legend.key.height = unit(2, "cm")
    )
  
  save_thesis_fig(fig_trends_heatmap_semanal, "fig_trends_heatmap_semanal_candidatos.png", width_cm = 20, height_cm = 10)
  
  cat("\n✅ Visualizaciones de Google Trends generadas\n")
}

n_png <- length(list.files(OUT_DIR, pattern = "\\.png$"))

cat("\n=== FIGURAS GENERADAS ===\n")
cat("Directorio:", OUT_DIR, "\n")
cat("Archivos PNG:", n_png, "\n\n")

cat("=== ESTADÍSTICAS DESCRIPTIVAS (RESUMEN) ===\n")
cat("\nMenciones totales por candidato:\n")
print(menciones_totales)

cat("\n\nRango de fechas (Reddit):\n")
cat("Desde:", as.character(min(df$fecha, na.rm = TRUE)), "\n")
cat("Hasta:", as.character(max(df$fecha, na.rm = TRUE)), "\n")
cat("Días:", as.numeric(max(df$fecha, na.rm = TRUE) - min(df$fecha, na.rm = TRUE)), "\n")

if (!is.null(df_trends)) {
  cat("\n\nRango de fechas (Google Trends):\n")
  cat("Desde:", as.character(min(df_trends$date, na.rm = TRUE)), "\n")
  cat("Hasta:", as.character(max(df_trends$date, na.rm = TRUE)), "\n")
  cat("Días:", as.numeric(max(df_trends$date, na.rm = TRUE) - min(df_trends$date, na.rm = TRUE)), "\n")
  
  if (!is.null(comparacion) && nrow(comparacion) > 0) {
    cat("\n=== CORRELACIONES REDDIT vs TRENDS ===\n")
    correlaciones <- comparacion %>%
      group_by(candidato) %>%
      summarise(
        correlacion = cor(menciones, score, use = "complete.obs"),
        n_semanas = n(),
        .groups = "drop"
      ) %>%
      arrange(desc(correlacion))
    
    print(correlaciones)
  } else {
    cat("\n⚠️ No se pudo calcular correlaciones (datos insuficientes)\n")
  }
} else {
  cat("\n⚠️ Google Trends no disponible - correlaciones omitidas\n")
}

cat("\n\n✅ Estadísticas descriptivas y figuras generadas correctamente.\n")

