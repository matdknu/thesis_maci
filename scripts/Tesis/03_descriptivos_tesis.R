# =============================================================
# 02) Thesis Descriptive Visualizations
# Generates academic/APA style plots for the thesis
# Reads from: data/processed/
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

# Definir nombres de candidatos y tipos de línea
nombres_candidatos <- c("Kast", "Kaiser", "Matthei", "Jara")
tipos_linea <- c("Kast" = "solid", "Kaiser" = "dashed", "Matthei" = "dotted", "Jara" = "dotdash")

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
# 2) Figure 1: Total distribution of mentions
# =============================================================
menciones_totales <- df %>%
  summarise(
    Kast = sum(kast, na.rm = TRUE),
    Kaiser = sum(kaiser, na.rm = TRUE),
    Matthei = sum(matthei, na.rm = TRUE),
    Jara = sum(jara, na.rm = TRUE)
  ) %>%
  pivot_longer(everything(), names_to = "candidato", values_to = "menciones") %>%
  mutate(
    candidato = factor(candidato, levels = candidato[order(menciones, decreasing = TRUE)]),
    pct = menciones / sum(menciones) * 100
  )

# =============================================================
# 3) Figure 2: Combined temporal evolution
# =============================================================
menciones_por_fecha <- df %>%
  group_by(fecha) %>%
  summarise(
    Kast = sum(kast, na.rm = TRUE),
    Kaiser = sum(kaiser, na.rm = TRUE),
    Matthei = sum(matthei, na.rm = TRUE),
    Jara = sum(jara, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_longer(-fecha, names_to = "candidato", values_to = "menciones") %>%
  filter(!is.na(fecha))


# =============================================================
# 4) Figure 3: Small multiples by candidate
# =============================================================
# (Esta figura se genera más adelante en la sección 9.3)

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
        TRUE ~ candidato
      )
    ) %>%
    filter(candidato_short %in% nombres_candidatos)
  
  fig4 <- trends_long %>%
    ggplot(aes(x = date, y = score, linetype = candidato_short, group = candidato_short)) +
    geom_line(linewidth = 0.9, alpha = 0.9, color = "black") +
    geom_point(size = 1.8, alpha = 0.7, shape = 21, fill = "white", stroke = 0.5, color = "black") +
    scale_linetype_manual(values = tipos_linea, name = "Candidate") +
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
      title = "Evolution of interest in Google Trends",
      subtitle = "Relative search interest by candidate (scale 0-100)",
      x = "Date",
      y = "Relative interest",
      caption = "Source: Google Trends. Own elaboration."
    ) +
    theme_thesis(legend.pos = "right") +
    theme(
      legend.box.margin = margin(l = 10)
    )
  
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
      geom_point(alpha = 0.7, size = 2.5, shape = 21, fill = "grey60", stroke = 0.8, color = "black") +
      geom_smooth(method = "lm", se = TRUE, alpha = 0.2, linewidth = 0.8, fill = "grey70", color = "black") +
      facet_wrap(~ candidato, ncol = 2, scales = "free") +
      labs(
        title = "Relationship between Reddit mentions and Google Trends interest",
        subtitle = "Weekly points with 95% confidence interval",
        x = "Average weekly mentions (Reddit)",
        y = "Average weekly interest (Google Trends)",
        caption = "Source: Own elaboration. Reddit: own scraping; Google Trends: official API."
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
  scale_fill_gradient(
    low = "white",
    high = "black",
    labels = label_number(),
    name = "Average\nmentions"
  ) +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0)
  ) +
  labs(
    title = "Heatmap: Weekly activity by candidate",
    subtitle = "Intensity of mentions on Reddit over time",
    x = "Week",
    y = NULL,
    caption = "Source: Own elaboration based on Reddit scraping."
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
    total_menciones = sum(kast + kaiser + matthei + jara, na.rm = TRUE),
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
  geom_line(linewidth = 1.2, color = "black", alpha = 0.8) +
  geom_area(fill = "grey70", alpha = 0.3) +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Total count of comments over time",
    subtitle = "Daily series of all comments in the dataset",
    x = "Date",
    y = "Number of comments",
    caption = "Source: Own elaboration based on Reddit scraping."
  ) +
  theme_thesis()

save_thesis_fig(fig_count_total, "fig_count_total_tiempo.png", width_cm = 18, height_cm = 10)

# Gráfico: Count total de menciones a lo largo del tiempo
fig_menciones_total <- count_por_fecha %>%
  ggplot(aes(x = fecha, y = total_menciones)) +
  geom_line(linewidth = 1.2, color = "black", alpha = 0.8) +
  geom_area(fill = "grey70", alpha = 0.3) +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Total count of mentions over time",
    subtitle = "Daily series of all mentions (sum of all candidates)",
    x = "Date",
    y = "Number of mentions",
    caption = "Source: Own elaboration based on Reddit scraping."
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
  summarise(
    Kast = sum(kast, na.rm = TRUE),
    Kaiser = sum(kaiser, na.rm = TRUE),
    Matthei = sum(matthei, na.rm = TRUE),
    Jara = sum(jara, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_longer(-fecha, names_to = "candidato", values_to = "count") %>%
  mutate(
    candidato = factor(candidato, levels = nombres_candidatos),
    semana = floor_date(fecha, "week", week_start = 1)
  )

# 9.1) Gráfico apilado (stacked area) - Count total por candidato
fig_count_apilado <- count_por_fecha_candidato %>%
  ggplot(aes(x = fecha, y = count, fill = candidato)) +
  geom_area(alpha = 0.7, position = "stack", color = "black", linewidth = 0.2) +
  scale_fill_grey(start = 0.2, end = 0.9, name = "Candidate") +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    title = "Stacked area chart: Total count by candidate over time",
    subtitle = "Cumulative daily mentions by candidate (stacked)",
    x = "Date",
    y = "Number of mentions",
    caption = "Source: Own elaboration based on Reddit scraping."
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
  geom_col(position = "stack", color = "black", linewidth = 0.2, alpha = 0.8) +
  scale_fill_grey(start = 0.2, end = 0.9, name = "Candidate") +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0.02)
  ) +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    title = "Stacked bar chart: Weekly count by candidate",
    subtitle = "Weekly aggregated mentions by candidate (stacked)",
    x = "Week",
    y = "Number of mentions",
    caption = "Source: Own elaboration based on Reddit scraping."
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
  ggplot(aes(x = fecha, y = count, group = candidato)) +
  geom_line(linewidth = 1, color = "black") +
  geom_area(fill = "grey70", alpha = 0.3) +
  facet_wrap(~ candidato, ncol = 2) +
  scale_x_date(date_breaks = "3 weeks", date_labels = "%d %b",
               expand = expansion(mult = 0.02)) +
  scale_y_continuous(
    trans  = trans_compress_above_1000,
    breaks = c(0, 250, 500, 750, 1000, 2000, 3000, 4000),
    labels = label_number(big.mark = ".", decimal.mark = ",")
  ) +
  labs(
    title = "Total count by candidate over time",
    subtitle = "Separate panels showing individual candidate trends",
    x = "Date", y = "Number of mentions",
    caption = "Source: Own elaboration based on Reddit scraping."
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
  scale_fill_gradient(
    low = "white",
    high = "black",
    labels = percent_format(accuracy = 1),
    name = "Weekly\nshare"
  ) +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0)
  ) +
  labs(
    title = "Weekly heatmap: Share of mentions by candidate",
    subtitle = "Each week sums to 100% across candidates",
    x = "Week",
    y = NULL,
    caption = "Source: Own elaboration based on Reddit scraping."
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
  scale_fill_gradient(
    low = "white",
    high = "black",
    labels = percent_format(accuracy = 0.1),
    name = "Candidate\nshare"
  ) +
  scale_x_date(
    date_breaks = "2 weeks",
    date_labels = "%d %b",
    expand = expansion(mult = 0)
  ) +
  labs(
    title = "Weekly heatmap: Within-candidate distribution over time",
    subtitle = "For each candidate, tiles show how their mentions concentrate across weeks",
    x = "Week",
    y = NULL,
    caption = "Source: Own elaboration based on Reddit scraping."
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
    geom_area(alpha = 0.7, position = "stack", color = "black", linewidth = 0.2) +
    scale_fill_grey(start = 0.2, end = 0.9, name = "Candidate") +
    scale_x_date(
      date_breaks = "1 month",
      date_labels = "%b %Y",
      expand = expansion(mult = 0.02)
    ) +
    scale_y_continuous(
      labels = label_number(),
      expand = expansion(mult = c(0, 0.05)),
      limits = c(0, NA)
    ) +
    labs(
      title = "Stacked area chart: Google Trends interest by candidate",
      subtitle = "Cumulative daily search interest by candidate (stacked, 0-100 scale)",
      x = "Date",
      y = "Relative interest",
      caption = "Source: Google Trends. Own elaboration."
    ) +
    theme_thesis(legend.pos = "bottom")
  
  save_thesis_fig(fig_trends_apilado, "fig_trends_apilado_candidatos.png", width_cm = 18, height_cm = 12)
  
  # 10.2) Gráfico por facet (small multiples) - Google Trends
  fig_trends_facet <- trends_long %>%
    mutate(candidato_short = factor(candidato_short, levels = nombres_candidatos)) %>%
    ggplot(aes(x = date, y = score, group = candidato_short)) +
    geom_line(linewidth = 1, color = "black") +
    geom_area(fill = "grey70", alpha = 0.3) +
    facet_wrap(~ candidato_short, ncol = 2, scales = "free_y") +
    scale_x_date(
      date_breaks = "2 months",
      date_labels = "%b %Y",
      expand = expansion(mult = 0.02)
    ) +
    scale_y_continuous(
      labels = label_number(),
      expand = expansion(mult = c(0, 0.1)),
      limits = c(0, NA)
    ) +
    labs(
      title = "Small multiples: Google Trends interest by candidate",
      subtitle = "Separate panels showing individual candidate trends",
      x = "Date",
      y = "Relative interest",
      caption = "Source: Google Trends. Own elaboration."
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
    scale_fill_gradient(
      low = "white",
      high = "black",
      labels = label_number(),
      name = "Weekly\ninterest",
      limits = c(0, 100)
    ) +
    scale_x_date(
      date_breaks = "1 month",
      date_labels = "%b %Y",
      expand = expansion(mult = 0)
    ) +
    labs(
      title = "Weekly heatmap: Google Trends interest by candidate",
      subtitle = "Intensity of weekly aggregated search interest by candidate",
      x = "Week",
      y = NULL,
      caption = "Source: Google Trends. Own elaboration."
    ) +
    theme_thesis(legend.pos = "right") +
    theme(
      axis.text.y = element_text(face = "bold"),
      legend.key.height = unit(2, "cm")
    )
  
  save_thesis_fig(fig_trends_heatmap_semanal, "fig_trends_heatmap_semanal_candidatos.png", width_cm = 20, height_cm = 10)
  
  cat("\n✅ Google Trends visualizations generated\n")
}

# Contar figuras generadas
n_figuras <- 8  # Figuras base (1-6, más count_total_tiempo, menciones_total_tiempo)
n_figuras <- n_figuras + 4  # Figuras adicionales Reddit (9.1-9.4)
if (!is.null(df_trends) && !is.null(trends_long)) {
  n_figuras <- n_figuras + 4  # Figuras de trends (fig4, 10.1, 10.2, 10.3)
}

cat("\n=== FIGURES GENERATED ===\n")
cat("Directory:", OUT_DIR, "\n")
cat("Total figures:", n_figuras, "\n\n")

cat("=== DESCRIPTIVE STATISTICS ===\n")
cat("\nTotal mentions by candidate:\n")
print(menciones_totales)

cat("\n\nReddit date range:\n")
cat("From:", as.character(min(df$fecha, na.rm = TRUE)), "\n")
cat("To:", as.character(max(df$fecha, na.rm = TRUE)), "\n")
cat("Days:", as.numeric(max(df$fecha, na.rm = TRUE) - min(df$fecha, na.rm = TRUE)), "\n")

if (!is.null(df_trends)) {
  cat("\n\nGoogle Trends date range:\n")
  cat("From:", as.character(min(df_trends$date, na.rm = TRUE)), "\n")
  cat("To:", as.character(max(df_trends$date, na.rm = TRUE)), "\n")
  cat("Days:", as.numeric(max(df_trends$date, na.rm = TRUE) - min(df_trends$date, na.rm = TRUE)), "\n")
  
  if (!is.null(comparacion) && nrow(comparacion) > 0) {
    cat("\n=== REDDIT vs TRENDS CORRELATIONS ===\n")
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

cat("\n\n✅ Figures and descriptive statistics generated successfully!\n")

