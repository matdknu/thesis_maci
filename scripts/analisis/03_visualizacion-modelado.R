# ==============================================================================
# VISUALIZACIONES TESIS — REDDIT CHILE 2025
# Input:  data/processed/analisis_API.csv
# Output: outputs/figuras/fig*.png
# Fixes:  left_join con select() previo para evitar ambigüedad de columnas
#         COLORES_FRONTERA usa labels post-factor (no valores originales)
# ==============================================================================

library(tidyverse)
library(viridis)
library(lubridate)
library(here)
library(scales)

# ── Rutas ─────────────────────────────────────────────────────────────────────
OUT_DIR <- here("outputs", "figuras")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ── Paletas ───────────────────────────────────────────────────────────────────
COLORES_CAND <- c(
  "Kast"    = "#C0392B",
  "Kaiser"  = "#E67E22",
  "Matthei" = "#2980B9",
  "Jara"    = "#27AE60"
)

COLORES_SENT <- c(
  "POSITIVO" = "#27AE60",
  "NEUTRO"   = "#7F8C8D",
  "NEGATIVO" = "#C0392B"
)

# Fig 4: colores con los labels exactos que usará factor()
COLORES_FRONTERA <- c(
  "Inter-bloque\n(derecha vs izquierda)" = "#8E44AD",
  "Intra-bloque\n(dentro de la derecha)" = "#E67E22"
)

COLORES_EMOCION <- c(
  "Indignación" = "#C0392B",
  "Desprecio"   = "#8E44AD",
  "Ira"         = "#E74C3C",
  "Miedo"       = "#2C3E50",
  "Esperanza"   = "#27AE60",
  "Alegría"     = "#F39C12"
)

# ── Tema base ─────────────────────────────────────────────────────────────────
TEMA <- theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(size = 14, face = "bold", margin = margin(b = 4)),
    plot.subtitle    = element_text(size = 11, color = "grey40", margin = margin(b = 12)),
    plot.caption     = element_text(size = 9,  color = "grey50", margin = margin(t = 10)),
    axis.title       = element_text(size = 10, color = "grey30"),
    axis.text        = element_text(size = 9,  color = "grey30"),
    legend.position  = "bottom",
    legend.title     = element_text(size = 9),
    legend.text      = element_text(size = 9),
    panel.grid.minor = element_blank(),
    strip.text       = element_text(size = 10, face = "bold")
  )

theme_set(TEMA)

# ==============================================================================
# CARGA Y PREPARACIÓN
# ==============================================================================
df_raw <- read_csv(
  here("data", "processed", "analisis_API.csv"),
  show_col_types = FALSE
) |>
  filter(post_id != "post_id") |>
  mutate(
    fecha                 = as.Date(fecha),
    polarizacion_consenso = as.numeric(polarizacion_consenso),
    semana                = floor_date(fecha, "week"),
    mes                   = floor_date(fecha, "month"),
    fase = case_when(
      fecha <= as.Date("2025-10-31") ~ "Posicionamiento (ago–oct)",
      TRUE                           ~ "Segunda vuelta (nov–dic)"
    )
  )

# Dataset largo: una fila por candidato × comentario
df_long <- df_raw |>
  pivot_longer(
    cols         = starts_with("sent_final_"),
    names_to     = "candidato",
    names_prefix = "sent_final_",
    values_to    = "sentimiento"
  ) |>
  filter(!is.na(sentimiento)) |>
  mutate(candidato = str_to_title(candidato))

# Dataset Prompt B: solo filas con acuerdo en las 4 dimensiones
df_b <- df_raw |>
  filter(
    !marco_final      %in% c("REVISAR", NA),
    !emocion_final    %in% c("REVISAR", NA),
    !estrategia_final %in% c("REVISAR", NA),
    !frontera_final   %in% c("REVISAR", NA)
  )

cat("Corpus total:      ", nrow(df_raw),  "comentarios\n")
cat("Dataset largo:     ", nrow(df_long), "filas candidato-comentario\n")
cat("Prompt B válido:   ", nrow(df_b),    "comentarios\n\n")

# ==============================================================================
# FIG 1 — Sentimiento por candidato
# ==============================================================================
fig1_data <- df_long |>
  filter(sentimiento %in% c("NEGATIVO", "NEUTRO", "POSITIVO")) |>
  count(candidato, sentimiento) |>
  group_by(candidato) |>
  mutate(pct = n / sum(n), total = sum(n)) |>
  ungroup() |>
  mutate(
    sentimiento = factor(sentimiento, levels = c("POSITIVO", "NEUTRO", "NEGATIVO")),
    candidato   = factor(candidato,   levels = c("Kast", "Kaiser", "Matthei", "Jara"))
  )

fig1 <- ggplot(fig1_data, aes(x = candidato, y = pct, fill = sentimiento)) +
  geom_col(width = 0.65) +
  geom_text(
    data     = fig1_data |> filter(pct > 0.08),
    aes(label = percent(pct, accuracy = 1)),
    position = position_stack(vjust = 0.5),
    size = 3.2, color = "white", fontface = "bold"
  ) +
  geom_text(
    data = fig1_data |> distinct(candidato, total),
    aes(x = candidato, y = 1.04, label = paste0("n=", total), fill = NULL),
    size = 3, color = "grey40"
  ) +
  scale_fill_manual(values = COLORES_SENT, name = NULL) +
  scale_y_continuous(
    labels  = percent_format(),
    expand  = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title    = "Sentimiento hacia cada candidato en Reddit Chile 2025",
    subtitle = "Proporción de comentarios con acuerdo entre modelos (excluye REVISAR)",
    x        = NULL,
    y        = "Proporción de comentarios",
    caption  = "Fuente: corpus Reddit r/chile y r/RepublicadeChile, ago–dic 2025.\nClasificación: GPT-4o-mini + DeepSeek Chat."
  )

fig1
#ggsave(file.path(OUT_DIR, "fig1_sentimiento_candidato.png"),
#       fig1, width = 8, height = 5.5, dpi = 300)
#cat("✅ Fig 1 guardada\n")

# ==============================================================================
# FIG 2 — Polarización semanal por candidato
# ==============================================================================
fig2_data <- df_long |>
  filter(!is.na(polarizacion_consenso)) |>
  group_by(semana, candidato) |>
  summarise(
    pol_mean = mean(polarizacion_consenso, na.rm = TRUE),
    pol_se   = sd(polarizacion_consenso,  na.rm = TRUE) / sqrt(n()),
    n        = n(),
    .groups  = "drop"
  ) |>
  filter(n >= 3) |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

# Bloque 1 — preparación de datos (solo dplyr, termina con mutate)
fig2_data <- df_long |>
  filter(!is.na(polarizacion_consenso)) |>
  mutate(polarizacion_consenso = 1 - polarizacion_consenso) |>
  group_by(semana, candidato) |>
  summarise(
    pol_mean = mean(polarizacion_consenso, na.rm = TRUE),
    pol_se   = sd(polarizacion_consenso,  na.rm = TRUE) / sqrt(n()),
    n        = n(),
    .groups  = "drop"
  ) |>
  filter(n >= 3) |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

fig2_data <- df_raw |>
  mutate(polarizacion_consenso = 1 - polarizacion_consenso) |>
  pivot_longer(
    cols         = starts_with("sent_final_"),
    names_to     = "candidato",
    names_prefix = "sent_final_",
    values_to    = "sentimiento"
  ) |>
  filter(!is.na(sentimiento)) |>
  mutate(candidato = str_to_title(candidato)) |>
  filter(!is.na(polarizacion_consenso)) |>
  group_by(semana, candidato) |>
  summarise(
    pol_mean = mean(polarizacion_consenso, na.rm = TRUE),
    pol_se   = sd(polarizacion_consenso,  na.rm = TRUE) / sqrt(n()),
    n        = n(),
    .groups  = "drop"
  ) |>
  filter(n >= 3) |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

# Bloque 2 — gráfico (empieza con ggplot, usa + no |>)
fig2 <- ggplot(fig2_data, aes(x = semana, y = pol_mean, color = candidato)) +
  geom_ribbon(
    aes(ymin = pol_mean - pol_se, ymax = pol_mean + pol_se, fill = candidato),
    alpha = 0.12, color = NA
  ) +
  geom_line(linewidth = 0.8) +
  geom_smooth(method = "loess", se = FALSE, linewidth = 0.4,
              linetype = "dashed", alpha = 0.6) +
  geom_hline(yintercept = 0.5, linetype = "dotted", color = "grey60") +
  annotate("text",
           x = min(fig2_data$semana), y = 0.52,
           label = "punto neutro (0.5)", size = 2.8, color = "grey50", hjust = 0) +
  annotate("rect",
           xmin = as.Date("2025-10-01"), xmax = as.Date("2025-11-01"),
           ymin = -Inf, ymax = Inf, alpha = 0.04, fill = "steelblue") +
  scale_color_manual(values = COLORES_CAND, name = NULL) +
  scale_fill_manual( values = COLORES_CAND, name = NULL) +
  scale_y_continuous(
    limits = c(0.15, 0.80),
    breaks = seq(0.2, 0.8, 0.1),
    labels = function(x) sprintf("%.1f", x)
  ) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") +
  labs(
    title    = "Hostilidad discursiva promedio semanal por candidato",
    subtitle = "Escala 0–1 (0 = neutral, 1 = máxima hostilidad). Banda: ±1 error estándar",
    x        = NULL,
    y        = "Índice de hostilidad",
    caption  = "Línea sólida: promedio semanal. Línea punteada: tendencia LOESS.\nZona sombreada: primera vuelta (oct 2025). Fuente: corpus Reddit Chile 2025."
  )

fig2

#ggsave(file.path(OUT_DIR, "fig2_polarizacion_temporal.png"),
#      fig2, width = 10, height = 5.5, dpi = 300)
#cat("✅ Fig 2 guardada\n")

# ==============================================================================
# FIG 3 — Heatmap marco × candidato
# ==============================================================================
fig3_data <- df_long |>
  select(post_id, comment_author, candidato, sentimiento) |>
  left_join(
    df_raw |> select(post_id, comment_author, marco_final),
    by = c("post_id", "comment_author")
  ) |>
  filter(
    !is.na(marco_final),
    marco_final != "REVISAR",
    sentimiento %in% c("NEGATIVO", "NEUTRO", "POSITIVO")
  ) |>
  count(candidato, marco_final) |>
  group_by(candidato) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    candidato   = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")),
    marco_final = factor(marco_final,
                         levels = c("institucional", "economico", "identitario",
                                    "seguridad", "medioambiental", "otro"),
                         labels = c("Institucional", "Económico", "Identitario",
                                    "Seguridad", "Medioambiental", "Otro"))
  )

fig3 <- ggplot(fig3_data, aes(x = candidato, y = marco_final, fill = pct)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = percent(pct, accuracy = 1)),
            size = 3.2, color = "white", fontface = "bold") +
  scale_fill_viridis_c(
    option = "plasma",
    labels = percent_format(),
    name   = "% del candidato",
    begin  = 0.1, end = 0.9
  ) +
  labs(
    title    = "Marco interpretativo dominante por candidato",
    subtitle = "Proporción de comentarios clasificados por marco (acuerdo entre modelos)",
    x        = NULL,
    y        = NULL,
    caption  = "Categorías basadas en Entman (1993) y Semetko & Valkenburg (2000).\nFuente: corpus Reddit Chile 2025."
  ) +
  theme(
    legend.position = "right",
    axis.text.x     = element_text(face = "bold", size = 10)
  )

fig3
#ggsave(file.path(OUT_DIR, "fig3_marco_candidato.png"),
#       fig3, width = 8, height = 5, dpi = 300)
#cat("✅ Fig 3 guardada\n")

# ==============================================================================
# FIG 4 — Estrategias de adversario por tipo de frontera
# ==============================================================================
fig4_data <- df_b |>
  filter(
    estrategia_final != "ninguna",
    frontera_final   %in% c("inter_bloque", "intra_bloque")
  ) |>
  count(estrategia_final, frontera_final) |>
  group_by(frontera_final) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    estrategia_final = factor(
      estrategia_final,
      levels = c("deslegitimacion", "ridiculizacion", "construccion_amenaza",
                 "atribucion_oculta", "esencializacion"),
      labels = c("Deslegitimación", "Ridiculización", "Construcción\nde amenaza",
                 "Atribución\noculta", "Esencialización")
    ),
    frontera_final = factor(
      frontera_final,
      levels = c("inter_bloque", "intra_bloque"),
      labels = c("Inter-bloque\n(derecha vs izquierda)",
                 "Intra-bloque\n(dentro de la derecha)")
    )
  )

fig4 <- ggplot(fig4_data,
               aes(x = reorder(estrategia_final, pct),
                   y = pct, fill = frontera_final)) +
  geom_col(width = 0.65, show.legend = FALSE) +
  geom_text(aes(label = percent(pct, accuracy = 1)),
            hjust = -0.1, size = 3, color = "grey30") +
  scale_fill_manual(values = COLORES_FRONTERA) +
  scale_y_continuous(
    labels = percent_format(),
    expand = expansion(mult = c(0, 0.15))
  ) +
  coord_flip() +
  facet_wrap(~ frontera_final, ncol = 2) +
  labs(
    title    = "Estrategias de construcción de adversario por tipo de frontera política",
    subtitle = "Distribución relativa dentro de cada tipo de frontera (excluye 'ninguna')",
    x        = NULL,
    y        = "Proporción de comentarios",
    caption  = "Categorías basadas en Mouffe (2005) y van Dijk (2006).\nFuente: corpus Reddit Chile 2025."
  )

fig4
#ggsave(file.path(OUT_DIR, "fig4_adversario_frontera.png"),
#      fig4, width = 10, height = 5.5, dpi = 300)
#cat("✅ Fig 4 guardada\n")

# ==============================================================================
# FIG BONUS — Emoción por candidato
# ==============================================================================
fig_bonus_data <- df_long |>
  select(post_id, comment_author, candidato, sentimiento) |>
  left_join(
    df_raw |> select(post_id, comment_author, emocion_final),
    by = c("post_id", "comment_author")
  ) |>
  filter(
    !is.na(emocion_final),
    emocion_final != "REVISAR",
    emocion_final != "ninguna",
    sentimiento   %in% c("NEGATIVO", "NEUTRO", "POSITIVO")
  ) |>
  count(candidato, emocion_final) |>
  group_by(candidato) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    candidato     = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")),
    emocion_final = factor(emocion_final,
                           levels = c("indignacion", "desprecio", "ira",
                                      "miedo", "esperanza", "alegria"),
                           labels = c("Indignación", "Desprecio", "Ira",
                                      "Miedo", "Esperanza", "Alegría"))
  )

fig_bonus <- ggplot(fig_bonus_data,
                    aes(x = candidato, y = pct, fill = emocion_final)) +
  geom_col(width = 0.65) +
  scale_fill_manual(values = COLORES_EMOCION, name = NULL) +
  scale_y_continuous(
    labels = percent_format(),
    expand = expansion(mult = c(0, 0.05))
  ) +
  labs(
    title    = "Emoción predominante por candidato",
    subtitle = "Repertorio afectivo en la conversación política (excluye 'ninguna' y REVISAR)",
    x        = NULL,
    y        = "Proporción",
    caption  = "Categorías basadas en Marcus (2000) y Jasper (2011).\nFuente: corpus Reddit Chile 2025."
  )

fig_bonus
#ggsave(file.path(OUT_DIR, "fig_bonus_emocion_candidato.png"),
#       fig_bonus, width = 8, height = 5, dpi = 300)
#cat("✅ Fig bonus guardada\n")

# ==============================================================================
# RESUMEN
# ==============================================================================
cat("\n", paste(rep("=", 50), collapse = ""), "\n")
cat("Figuras en:", OUT_DIR, "\n")
cat("  fig1_sentimiento_candidato.png\n")
cat("  fig2_polarizacion_temporal.png\n")
cat("  fig3_marco_candidato.png\n")
cat("  fig4_adversario_frontera.png\n")
cat("  fig_bonus_emocion_candidato.png\n")


