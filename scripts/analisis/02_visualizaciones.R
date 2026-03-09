# =============================================================
# Visualizaciones formales tipo tesis
# Genera gráficos con estilo académico/APA para el informe
# =============================================================

# Setup
pacman::p_load(
  tidyverse, lubridate, here, readr, scales, 
  ggtext, patchwork, jtools
)

set.seed(123)

# Rutas
OUT_DIR <- here("outputs", "thesis_figures")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# Tema base para tesis usando theme_apa de jtools
# Referencia: https://jtools.jacob-long.com/reference/theme_apa
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

# Función para guardar gráficos
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
# 1) Carga de datos
# =============================================================
df <- readRDS(here("data/processed/reddit_filtrado.rds"))
df_trends <- read_csv(here("data/trends/series/trends_candidatos_daily.csv"), 
                      show_col_types = FALSE)

# =============================================================
# 2) Figura 1: Distribución total de menciones
# =============================================================
menciones_totales <- df %>%
  summarise(
    Kast = sum(kast, na.rm = TRUE),
    Kaiser = sum(kaiser, na.rm = TRUE),
    Matthei = sum(matthei, na.rm = TRUE),
    Jara = sum(jara, na.rm = TRUE),
    Parisi = sum(parisi, na.rm = TRUE),
    Mayne = sum(mayne_nicholls, na.rm = TRUE)
  ) %>%
  pivot_longer(everything(), names_to = "candidato", values_to = "menciones") %>%
  mutate(
    candidato = factor(candidato, levels = candidato[order(menciones, decreasing = TRUE)]),
    pct = menciones / sum(menciones) * 100
  )

# Escala de grises para barras (estilo APA - sin colores)
fig1 <- menciones_totales %>%
  ggplot(aes(x = candidato, y = menciones, fill = candidato)) +
  geom_col(alpha = 0.7, show.legend = FALSE, color = "black", linewidth = 0.3) +
  geom_text(
    aes(label = paste0(format(menciones, big.mark = ".", decimal.mark = ","), "\n(", round(pct, 1), "%)")),
    vjust = -0.3,
    size = 3.2,
    lineheight = 0.9
  ) +
  scale_fill_grey(start = 0.3, end = 0.8) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.15))
  ) +
  labs(
    title = "Distribución total de menciones por candidato",
    subtitle = "Reddit: agosto - diciembre 2025",
    x = NULL,
    y = "Número de menciones",
    caption = "Nota. Los porcentajes entre paréntesis representan la proporción del total."
  ) +
  theme_thesis()

fig1
save_thesis_fig(fig1, "fig1_distribucion_menciones.png", width_cm = 14, height_cm = 10)

# =============================================================
# 3) Figura 2: Evolución temporal combinada
# =============================================================
menciones_por_fecha <- df %>%
  group_by(fecha) %>%
  summarise(
    Kast = sum(kast, na.rm = TRUE),
    Kaiser = sum(kaiser, na.rm = TRUE),
    Matthei = sum(matthei, na.rm = TRUE),
    Jara = sum(jara, na.rm = TRUE),
    Parisi = sum(parisi, na.rm = TRUE),
    Mayne = sum(mayne_nicholls, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_longer(-fecha, names_to = "candidato", values_to = "menciones") %>%
  filter(!is.na(fecha))

# Usar tipos de línea y escala de grises en lugar de colores (estilo APA)
# Tipos de línea diferentes para distinguir candidatos
tipos_linea <- c("solid", "dashed", "dotted", "dotdash", "longdash", "twodash")
nombres_candidatos <- c("Kast", "Kaiser", "Matthei", "Jara", "Parisi", "Mayne")
names(tipos_linea) <- nombres_candidatos

# Escala de grises para colores
colores_grises <- gray.colors(6, start = 0.2, end = 0.8)
names(colores_grises) <- nombres_candidatos

fig2 <- menciones_por_fecha %>%
  ggplot(aes(x = fecha, y = menciones, linetype = candidato, group = candidato)) +
  geom_line(linewidth = 0.9, alpha = 0.9, color = "black") +
  geom_point(size = 1.8, alpha = 0.7, shape = 21, fill = "white", stroke = 0.5, color = "black") +
  scale_linetype_manual(values = tipos_linea, name = "Candidato") +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Evolución temporal de menciones diarias",
    subtitle = "Serie diaria de menciones en Reddit por candidato",
    x = "Fecha",
    y = "Número de menciones",
    caption = "Fuente: Elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis(legend.pos = "right") +
  theme(
    legend.box.margin = margin(l = 10)
  )

fig2
save_thesis_fig(fig2, "fig2_evolucion_temporal.png", width_cm = 18, height_cm = 10)

# =============================================================
# 4) Figura 3: Small multiples por candidato
# =============================================================
fig3 <- menciones_por_fecha %>%
  mutate(candidato = factor(candidato, levels = nombres_candidatos)) %>%
  ggplot(aes(x = fecha, y = menciones, group = candidato)) +
  geom_line(linewidth = 1, show.legend = FALSE, color = "black") +
  geom_point(size = 1.5, alpha = 0.6, show.legend = FALSE, color = "black", shape = 21, fill = "white") +
  facet_wrap(~ candidato, ncol = 3, scales = "free_y") +
  scale_x_date(
    date_breaks = "3 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(),
    expand = expansion(mult = c(0, 0.12))
  ) +
  labs(
    title = "Evolución temporal de menciones por candidato",
    subtitle = "Paneles separados para facilitar la comparación de patrones individuales",
    x = "Fecha",
    y = "Número de menciones",
    caption = "Fuente: Elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis() +
  theme(
    strip.background = element_rect(fill = "grey95", color = NA),
    strip.text = element_text(margin = margin(5, 0, 5, 0))
  )

fig3
save_thesis_fig(fig3, "fig3_small_multiples.png", width_cm = 20, height_cm = 14)

# =============================================================
# 5) Figura 4: Google Trends
# =============================================================
trends_long <- df_trends %>%
  pivot_longer(-date, names_to = "candidato", values_to = "score") %>%
  filter(!is.na(date), !is.na(score)) %>%
  mutate(
    candidato_short = case_when(
      str_detect(candidato, "Matthei") ~ "Matthei",
      str_detect(candidato, "Kast") ~ "Kast",
      str_detect(candidato, "Kaiser") ~ "Kaiser",
      str_detect(candidato, "Parisi") ~ "Parisi",
      str_detect(candidato, "Jara") ~ "Jara",
      str_detect(candidato, "Mayne") ~ "Mayne",
      TRUE ~ candidato
    )
  ) %>%
  filter(candidato_short %in% nombres_candidatos)

fig4 <- trends_long %>%
  ggplot(aes(x = date, y = score, linetype = candidato_short, group = candidato_short)) +
  geom_line(linewidth = 0.9, alpha = 0.9, color = "black") +
  geom_point(size = 1.8, alpha = 0.7, shape = 21, fill = "white", stroke = 0.5, color = "black") +
  scale_linetype_manual(values = tipos_linea, name = "Candidato") +
  scale_x_date(
    date_breaks = "1 month",
    date_labels = "%b %Y",
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(),
    expand = expansion(mult = c(0, 0.08)),
    limits = c(0, 100)
  ) +
  labs(
    title = "Evolución del interés en Google Trends",
    subtitle = "Interés relativo de búsqueda por candidato (escala 0-100)",
    x = "Fecha",
    y = "Interés relativo",
    caption = "Fuente: Google Trends. Elaboración propia."
  ) +
  theme_thesis(legend.pos = "right") +
  theme(
    legend.box.margin = margin(l = 10)
  )

fig4
save_thesis_fig(fig4, "fig4_google_trends.png", width_cm = 18, height_cm = 10)

# =============================================================
# 6) Figura 5: Comparación Reddit vs Google Trends
# =============================================================
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

fig5 <- comparacion %>%
  mutate(candidato = factor(candidato, levels = nombres_candidatos)) %>%
  ggplot(aes(x = menciones, y = score)) +
  geom_point(alpha = 0.7, size = 2.5, shape = 21, fill = "grey60", stroke = 0.8, color = "black") +
  geom_smooth(method = "lm", se = TRUE, alpha = 0.2, linewidth = 0.8, fill = "grey70", color = "black") +
  facet_wrap(~ candidato, ncol = 3, scales = "free") +
  labs(
    title = "Relación entre menciones en Reddit e interés en Google Trends",
    subtitle = "Puntos semanales con intervalo de confianza del 95%",
    x = "Menciones promedio semanal (Reddit)",
    y = "Interés promedio semanal (Google Trends)",
    caption = "Fuente: Elaboración propia. Reddit: scraping propio; Google Trends: API oficial."
  ) +
  theme_thesis() +
  theme(
    strip.background = element_rect(fill = "grey95", color = NA),
    strip.text = element_text(margin = margin(5, 0, 5, 0))
  )

fig5
save_thesis_fig(fig5, "fig5_comparacion_reddit_trends.png", width_cm = 20, height_cm = 14)

# =============================================================
# 7) Figura 6: Heatmap de actividad semanal
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
    candidato = factor(candidato, levels = names(colores_candidatos))
  )

fig6 <- menciones_semanales_wide %>%
  mutate(candidato = factor(candidato, levels = nombres_candidatos)) %>%
  ggplot(aes(x = semana, y = candidato, fill = menciones)) +
  geom_tile(color = "white", linewidth = 0.3) +
  scale_fill_gradient(
    low = "white",
    high = "black",
    labels = label_number(),
    name = "Menciones\npromedio"
  ) +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0)
  ) +
  labs(
    title = "Mapa de calor: Actividad semanal por candidato",
    subtitle = "Intensidad de menciones en Reddit a lo largo del tiempo",
    x = "Semana",
    y = NULL,
    caption = "Fuente: Elaboración propia a partir de scraping de Reddit."
  ) +
  theme_thesis(legend.pos = "right") +
  theme(
    axis.text.y = element_text(face = "bold"),
    legend.key.height = unit(1.5, "cm")
  )

fig6
save_thesis_fig(fig6, "fig6_heatmap_actividad.png", width_cm = 20, height_cm = 10)

# =============================================================
# 8) Resumen de estadísticas descriptivas
# =============================================================
cat("\n=== FIGURAS GENERADAS ===\n")
cat("Directorio:", OUT_DIR, "\n")
cat("Total de figuras:", 6, "\n\n")

cat("=== ESTADÍSTICAS DESCRIPTIVAS ===\n")
cat("\nMenciones totales por candidato:\n")
print(menciones_totales)

cat("\n\nRango de fechas Reddit:\n")
cat("Desde:", as.character(min(df$fecha, na.rm = TRUE)), "\n")
cat("Hasta:", as.character(max(df$fecha, na.rm = TRUE)), "\n")
cat("Días:", as.numeric(max(df$fecha, na.rm = TRUE) - min(df$fecha, na.rm = TRUE)), "\n")

cat("\n\nRango de fechas Google Trends:\n")
cat("Desde:", as.character(min(df_trends$date, na.rm = TRUE)), "\n")
cat("Hasta:", as.character(max(df_trends$date, na.rm = TRUE)), "\n")
cat("Días:", as.numeric(max(df_trends$date, na.rm = TRUE) - min(df_trends$date, na.rm = TRUE)), "\n")

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

cat("\n\n¡Figuras generadas exitosamente!\n")

