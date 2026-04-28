# ==============================================================================
# VISUALIZACIONES TESIS — REDDIT CHILE 2025
# Script completo — todas las figuras para tesis de máster
# ==============================================================================

library(tidyverse)
library(viridis)
library(lubridate)
library(here)
library(scales)
library(tidygraph)
library(ggraph)
library(patchwork)
library(ggridges)

OUT_DIR <- here("outputs", "figuras")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# PALETAS Y TEMA
# ==============================================================================
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
  "Alegría"     = "#F39C12",
  "Ironía"      = "#16A085"
)

MARCOS_LEVELS <- c("conflicto", "moral", "diagnostico", "pronostico",
                   "identitario", "economico", "motivacional", "otro")
MARCOS_LABELS <- c("Conflicto", "Moral", "Diagnóstico", "Pronóstico",
                   "Identitario", "Económico", "Motivacional", "Otro")

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
    hostilidad            = 1 - polarizacion_consenso,
    semana                = floor_date(fecha, "week"),
    mes                   = floor_date(fecha, "month"),
    fase = case_when(
      fecha <= as.Date("2025-10-31") ~ "Posicionamiento\n(ago–oct)",
      TRUE                           ~ "Segunda vuelta\n(nov–dic)"
    )
  )

df <- readRDS(here("data/processed/reddit_filtrado.rds"))

df |> 
  group_by(fecha, post_id) |> 
  count() |> 
  ggplot(aes(x = fecha)) +
  geom_density(fill = "steelblue", alpha = 0.5) +
  labs(
    title = "Densidad de la frecuencia de publicaciones",
    x = "Número de ocurrencias (n)",
    y = "Densidad"
  ) +
  theme_minimal()


df_raw |> 
  group_by(fecha, post_id) |> 
  count() |> 
  ggplot(aes(x = fecha)) +
  geom_density(fill = "steelblue", alpha = 0.5) +
  labs(
    title = "Densidad de la frecuencia de publicaciones",
    x = "Número de ocurrencias (n)",
    y = "Densidad"
  ) +
  theme_minimal()

df_long <- df_raw |>
  pivot_longer(
    cols         = starts_with("sent_final_"),
    names_to     = "candidato",
    names_prefix = "sent_final_",
    values_to    = "sentimiento"
  ) |>
  filter(!is.na(sentimiento)) |>
  mutate(candidato = str_to_title(candidato))

cat("Corpus:", nrow(df_raw), "comentarios\n")
cat("Long:  ", nrow(df_long), "filas candidato-comentario\n\n")

# ==============================================================================
# FIG 1 — Sentimiento por candidato (barras apiladas)
# ==============================================================================
fig1_data <- df_long |>
  filter(sentimiento %in% c("NEGATIVO", "NEUTRO", "POSITIVO")) |>
  count(candidato, sentimiento) |>
  group_by(candidato) |>
  mutate(pct = n / sum(n), total = sum(n)) |>
  ungroup() |>
  mutate(
    sentimiento = factor(sentimiento, levels = c("POSITIVO", "NEUTRO", "NEGATIVO")),
    candidato   = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara"))
  )

fig1 <- ggplot(fig1_data, aes(x = candidato, y = pct, fill = sentimiento)) +
  geom_col(width = 0.65) +
  geom_text(
    data = fig1_data |> filter(pct > 0.06),
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
  scale_y_continuous(labels = percent_format(), expand = expansion(mult = c(0, 0.08))) +
  labs(
    title    = "Sentimiento hacia cada candidato en Reddit Chile 2025",
    subtitle = "Proporción de comentarios por candidato",
    x = NULL, y = "Proporción",
    caption  = "Fuente: r/chile y r/RepublicadeChile, ago–dic 2025. GPT-4o-mini + DeepSeek Chat."
  )

fig1
ggsave(file.path(OUT_DIR, "fig1_sentimiento_candidato.png"), fig1, width = 8, height = 5.5, dpi = 300)
cat("✅ Fig 1\n")

# ==============================================================================
# FIG 2 — Hostilidad por fase × candidato (barras + IC 95%)
# ==============================================================================
fig2_data <- df_raw |>
  pivot_longer(cols = starts_with("sent_final_"), names_to = "candidato",
               names_prefix = "sent_final_", values_to = "sentimiento") |>
  filter(!is.na(sentimiento), !is.na(hostilidad)) |>
  mutate(candidato = str_to_title(candidato)) |>
  group_by(fase, candidato) |>
  summarise(
    media   = mean(hostilidad, na.rm = TRUE),
    se      = sd(hostilidad, na.rm = TRUE) / sqrt(n()),
    n       = n(),
    ci_low  = pmax(media - 1.96 * se, 0),
    ci_high = pmin(media + 1.96 * se, 1),
    .groups = "drop"
  ) |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

fig2 <- ggplot(fig2_data, aes(x = candidato, y = media, fill = candidato, alpha = fase)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.65) +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high),
                position = position_dodge(width = 0.75), width = 0.15, color = "grey30") +
  geom_text(aes(label = paste0("n=", n), y = ci_high + 0.02),
            position = position_dodge(width = 0.75), size = 2.8, color = "grey40") +
  scale_fill_manual(values = COLORES_CAND, guide = "none") +
  scale_alpha_manual(values = c(0.55, 1.0), name = "Fase electoral") +
  scale_y_continuous(limits = c(0, 1), labels = number_format(accuracy = 0.1),
                     expand = expansion(mult = c(0, 0.08))) +
  labs(
    title    = "Hostilidad discursiva por candidato y fase electoral",
    subtitle = "Promedio con IC 95% (hostilidad = 1 − polarización)",
    x = NULL, y = "Índice de hostilidad (0–1)",
    caption  = "Fase 1: ago–oct 2025. Fase 2: nov–dic 2025. Fuente: corpus Reddit Chile 2025."
  )

fig2
ggsave(file.path(OUT_DIR, "fig2_hostilidad_fase_candidato.png"), fig2, width = 9, height = 5.5, dpi = 300)
cat("✅ Fig 2\n")

# ==============================================================================
# FIG 3 — Heatmap marco × candidato (Entman 1993)
# ==============================================================================
fig3_data <- df_long |>
  select(post_id, comment_author, candidato) |>
  left_join(df_raw |> select(post_id, comment_author, marco_final),
            by = c("post_id", "comment_author")) |>
  filter(!is.na(marco_final), marco_final != "REVISAR") |>
  count(candidato, marco_final) |>
  group_by(candidato) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    candidato   = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")),
    marco_final = factor(marco_final, levels = MARCOS_LEVELS, labels = MARCOS_LABELS)
  ) |>
  filter(!is.na(marco_final))

fig3 <- ggplot(fig3_data, aes(x = candidato, y = marco_final, fill = pct)) +
  geom_tile(color = "white", linewidth = 0.6) +
  geom_text(aes(label = percent(pct, accuracy = 1)),
            size = 3.2, color = "white", fontface = "bold") +
  scale_fill_viridis_c(option = "plasma", labels = percent_format(),
                       name = "% dentro\ndel candidato", begin = 0.1, end = 0.95) +
  labs(
    title    = "Marco interpretativo dominante por candidato (Entman 1993)",
    subtitle = "Proporción de comentarios por marco y candidato",
    x = NULL, y = NULL,
    caption  = "Marcos basados en Entman (1993). Fuente: corpus Reddit Chile 2025."
  ) +
  theme(legend.position = "right", axis.text.x = element_text(face = "bold", size = 11))

fig3
ggsave(file.path(OUT_DIR, "fig3_marco_candidato.png"), fig3, width = 8, height = 5.5, dpi = 300)
cat("✅ Fig 3\n")

# ==============================================================================
# FIG 4 — Estrategias × frontera política (barras horizontales faceteadas)
# ==============================================================================
fig4_data <- df_raw |>
  filter(estrategia_final != "ninguna", frontera_final %in% c("inter_bloque", "intra_bloque")) |>
  count(estrategia_final, frontera_final) |>
  group_by(frontera_final) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    estrategia_final = factor(estrategia_final,
                              levels = c("deslegitimacion", "ridiculizacion", "construccion_amenaza",
                                         "atribucion_oculta", "esencializacion"),
                              labels = c("Deslegitimación", "Ridiculización", "Construcción\nde amenaza",
                                         "Atribución\noculta", "Esencialización")),
    frontera_final = factor(frontera_final,
                            levels = c("inter_bloque", "intra_bloque"),
                            labels = c("Inter-bloque\n(derecha vs izquierda)", "Intra-bloque\n(dentro de la derecha)"))
  )

fig4 <- ggplot(fig4_data, aes(x = reorder(estrategia_final, pct), y = pct, fill = frontera_final)) +
  geom_col(width = 0.65, show.legend = FALSE) +
  geom_text(aes(label = percent(pct, accuracy = 1)), hjust = -0.1, size = 3, color = "grey30") +
  scale_fill_manual(values = COLORES_FRONTERA) +
  scale_y_continuous(labels = percent_format(), expand = expansion(mult = c(0, 0.18))) +
  coord_flip() +
  facet_wrap(~ frontera_final, ncol = 2) +
  labs(
    title    = "Estrategias de construcción del adversario por tipo de frontera política",
    subtitle = "Distribución relativa dentro de cada tipo de frontera (excluye 'ninguna')",
    x = NULL, y = "Proporción",
    caption  = "Basado en Mouffe (2005) y van Dijk (2006). Fuente: corpus Reddit Chile 2025."
  )

fig4
ggsave(file.path(OUT_DIR, "fig4_estrategia_frontera.png"), fig4, width = 10, height = 5.5, dpi = 300)
cat("✅ Fig 4\n")

# ==============================================================================
# FIG 5 — Mapa de estilos discursivos (scatter hostilidad × inter-bloque)
# ==============================================================================
fig5_data <- df_long |>
  select(post_id, comment_author, candidato) |>
  left_join(df_raw |> select(post_id, comment_author, hostilidad, frontera_final),
            by = c("post_id", "comment_author")) |>
  mutate(inter = if_else(frontera_final == "inter_bloque", 1, 0, missing = 0)) |>
  group_by(candidato) |>
  summarise(
    hostilidad_media = mean(hostilidad, na.rm = TRUE),
    inter_pct        = mean(inter, na.rm = TRUE),
    n                = n(), .groups = "drop"
  ) |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

fig5 <- ggplot(fig5_data, aes(x = hostilidad_media, y = inter_pct, color = candidato, size = n)) +
  geom_point(alpha = 0.85) +
  geom_text(aes(label = candidato), nudge_y = 0.025, size = 4.5,
            fontface = "bold", show.legend = FALSE) +
  scale_color_manual(values = COLORES_CAND, guide = "none") +
  scale_size_continuous(range = c(6, 14), guide = "none") +
  scale_x_continuous(labels = number_format(accuracy = 0.01)) +
  scale_y_continuous(labels = percent_format()) +
  labs(
    title    = "Mapa de estilos discursivos por candidato",
    subtitle = "Hostilidad media vs. proporción de confrontación inter-bloque",
    x = "Hostilidad discursiva media (0–1)", y = "% comentarios inter-bloque",
    caption  = "Tamaño proporcional al n de comentarios. Fuente: corpus Reddit Chile 2025."
  )

fig5
ggsave(file.path(OUT_DIR, "fig5_mapa_estilos.png"), fig5, width = 8, height = 6, dpi = 300)
cat("✅ Fig 5\n")

# ==============================================================================
# FIG 6 — Red de co-menciones entre candidatos
# ==============================================================================
comenciones <- df_raw |>
  filter(n_candidatos > 1) |>
  select(post_id, candidatos) |>
  distinct() |>
  mutate(lista = str_split(candidatos, ", ")) |>
  rowwise() |>
  mutate(pares = list(as.data.frame(t(combn(sort(lista), 2)), stringsAsFactors = FALSE))) |>
  ungroup() |>
  select(pares) |>
  unnest(pares) |>
  rename(from = V1, to = V2) |>
  count(from, to, name = "peso") |>
  mutate(from = str_to_title(from), to = str_to_title(to))

nodos <- df_long |>
  count(candidato, name = "menciones") |>
  rename(name = candidato)

grafo <- tbl_graph(nodes = nodos, edges = comenciones, directed = FALSE)

fig6 <- ggraph(grafo, layout = "circle") +
  geom_edge_link(aes(width = peso, alpha = peso), color = "#34495E") +
  geom_node_point(aes(size = menciones, color = name), show.legend = FALSE) +
  geom_node_label(aes(label = name, color = name), fontface = "bold",
                  size = 4.5, show.legend = FALSE, nudge_y = 0.15) +
  scale_color_manual(values = COLORES_CAND) +
  scale_edge_width(range = c(0.5, 6), name = "Co-menciones") +
  scale_edge_alpha(range = c(0.3, 0.9), guide = "none") +
  scale_size_continuous(range = c(8, 18), guide = "none") +
  labs(
    title    = "Red de co-menciones entre candidatos",
    subtitle = "Aristas ponderadas por frecuencia de aparición conjunta en el mismo hilo",
    caption  = "Solo hilos con 2+ candidatos. Fuente: corpus Reddit Chile 2025."
  ) +
  theme_graph(base_family = "sans") +
  theme(plot.title = element_text(size = 14, face = "bold"),
        plot.subtitle = element_text(size = 11, color = "grey40"),
        plot.caption  = element_text(size = 9, color = "grey50"),
        legend.position = "bottom")

fig6
ggsave(file.path(OUT_DIR, "fig6_red_comenciones.png"), fig6, width = 8, height = 7, dpi = 300)
cat("✅ Fig 6\n")

# ==============================================================================
# FIG 7 — Densidad de polarización por candidato (ridgeline)
# ==============================================================================
fig7_data <- df_long |>
  select(post_id, comment_author, candidato) |>
  left_join(df_raw |> select(post_id, comment_author, polarizacion_consenso),
            by = c("post_id", "comment_author")) |>
  filter(!is.na(polarizacion_consenso)) |>
  mutate(candidato = factor(candidato, levels = rev(c("Kast", "Kaiser", "Matthei", "Jara"))))

fig7 <- ggplot(fig7_data, aes(x = polarizacion_consenso, y = candidato, fill = candidato)) +
  geom_density_ridges(alpha = 0.75, scale = 1.2, bandwidth = 0.04,
                      quantile_lines = TRUE, quantiles = 2) +
  scale_fill_manual(values = COLORES_CAND, guide = "none") +
  scale_x_continuous(limits = c(0, 1), labels = number_format(accuracy = 0.1)) +
  labs(
    title    = "Distribución de polarización afectiva por candidato",
    subtitle = "Densidad de kernel con mediana (línea vertical). Escala 0=neutral, 1=máxima hostilidad",
    x = "Polarización afectiva (consenso modelos)", y = NULL,
    caption  = "Fuente: corpus Reddit Chile 2025."
  )

fig7 
ggsave(file.path(OUT_DIR, "fig7_densidad_polarizacion.png"), fig7, width = 9, height = 5.5, dpi = 300)
cat("✅ Fig 7\n")

# ==============================================================================
# FIG 8 — Volumen de menciones semanal por candidato (área apilada)
# ==============================================================================
fig8_data <- df_long |>
  count(semana, candidato) |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

fig8 <- ggplot(fig8_data, aes(x = semana, y = n, fill = candidato)) +
  geom_area(alpha = 0.8, position = "stack") +
  geom_vline(xintercept = as.Date("2025-10-31"), linetype = "dashed", color = "white", linewidth = 0.8) +
  annotate("text", x = as.Date("2025-10-31"), y = Inf,
           label = "2ª vuelta →", vjust = 1.5, hjust = -0.1,
           size = 3.2, color = "white", fontface = "bold") +
  scale_fill_manual(values = COLORES_CAND, name = NULL) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(
    title    = "Volumen semanal de menciones por candidato",
    subtitle = "Número de comentarios clasificados por semana y candidato",
    x = NULL, y = "N comentarios",
    caption  = "Fuente: corpus Reddit Chile 2025."
  )

fig8
ggsave(file.path(OUT_DIR, "fig8_volumen_menciones.png"), fig8, width = 10, height = 5.5, dpi = 300)
cat("✅ Fig 8\n")

# ==============================================================================
# FIG 9 — Heatmap polarización media por candidato × semana (calendario)
# ==============================================================================
fig9_data <- df_long |>
  select(post_id, comment_author, candidato, semana) |>
  left_join(df_raw |> select(post_id, comment_author, hostilidad),
            by = c("post_id", "comment_author")) |>
  filter(!is.na(hostilidad)) |>
  group_by(semana, candidato) |>
  summarise(host_mean = mean(hostilidad, na.rm = TRUE), n = n(), .groups = "drop") |>
  filter(n >= 3) |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

fig9 <- ggplot(fig9_data, aes(x = semana, y = candidato, fill = host_mean)) +
  geom_tile(color = "white", linewidth = 0.4) +
  scale_fill_viridis_c(option = "inferno", name = "Hostilidad\nmedia",
                       limits = c(0, 1), labels = number_format(accuracy = 0.1)) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") +
  geom_vline(xintercept = as.Date("2025-10-31"), linetype = "dashed", color = "white") +
  labs(
    title    = "Calendario de hostilidad discursiva por candidato",
    subtitle = "Intensidad de hostilidad por semana (solo semanas con n ≥ 3)",
    x = NULL, y = NULL,
    caption  = "Fuente: corpus Reddit Chile 2025."
  ) +
  theme(legend.position = "right",
        axis.text.y = element_text(face = "bold", size = 11))

fig9
ggsave(file.path(OUT_DIR, "fig9_calendario_hostilidad.png"), fig9, width = 11, height = 4.5, dpi = 300)
cat("✅ Fig 9\n")

# ==============================================================================
# FIG 10 — Heatmap emoción × marco (qué emociones activa cada marco)
# ==============================================================================
fig10_data <- df_raw |>
  filter(!is.na(emocion_final), !is.na(marco_final),
         emocion_final != "ninguna", marco_final != "otro") |>
  count(marco_final, emocion_final) |>
  group_by(marco_final) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    marco_final   = factor(marco_final, levels = MARCOS_LEVELS, labels = MARCOS_LABELS),
    emocion_final = factor(emocion_final,
                           levels = c("indignacion", "ira", "desprecio", "miedo", "esperanza", "alegria", "ironia"),
                           labels = c("Indignación", "Ira", "Desprecio", "Miedo", "Esperanza", "Alegría", "Ironía"))
  ) |>
  filter(!is.na(marco_final), !is.na(emocion_final))

fig10 <- ggplot(fig10_data, aes(x = emocion_final, y = marco_final, fill = pct)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = percent(pct, accuracy = 1)),
            color = "white", fontface = "bold", size = 3) +
  scale_fill_viridis_c(option = "magma", labels = percent_format(),
                       name = "% dentro\ndel marco", begin = 0.05, end = 0.95) +
  labs(
    title    = "Activación emocional por marco interpretativo",
    subtitle = "Distribución de emociones dentro de cada marco (excluye 'ninguna')",
    x = "Emoción predominante", y = "Marco interpretativo",
    caption  = "Marcos: Entman (1993). Emociones: Marcus (2000). Fuente: corpus Reddit Chile 2025."
  ) +
  theme(legend.position = "right",
        axis.text.x = element_text(angle = 30, hjust = 1))

fig10
ggsave(file.path(OUT_DIR, "fig10_emocion_marco.png"), fig10, width = 10, height = 6, dpi = 300)
cat("✅ Fig 10\n")

# ==============================================================================
# FIG 11 — Scatter polarización × karma (con LOESS por candidato)
# ==============================================================================
fig11_data <- df_long |>
  select(post_id, comment_author, candidato) |>
  left_join(df_raw |> select(post_id, comment_author, polarizacion_consenso, comment_score),
            by = c("post_id", "comment_author")) |>
  filter(!is.na(polarizacion_consenso), !is.na(comment_score)) |>
  mutate(
    score_clamp = pmax(pmin(comment_score, 200), -50),
    candidato   = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara"))
  )

fig11 <- ggplot(fig11_data, aes(x = polarizacion_consenso, y = score_clamp, color = candidato)) +
  geom_point(alpha = 0.08, size = 0.8) +
  geom_smooth(method = "loess", se = TRUE, linewidth = 1.2, alpha = 0.2) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  scale_color_manual(values = COLORES_CAND, name = NULL) +
  scale_x_continuous(limits = c(0, 1), labels = number_format(accuracy = 0.1)) +
  facet_wrap(~ candidato, nrow = 1) +
  labs(
    title    = "Relación entre polarización afectiva y validación comunitaria (karma)",
    subtitle = "Tendencia LOESS con banda de confianza. Score truncado en [-50, 200] para legibilidad",
    x = "Polarización afectiva (0–1)", y = "Karma del comentario",
    caption  = "Karma = validación colectiva de la comunidad Reddit. Fuente: corpus Reddit Chile 2025."
  ) +
  theme(legend.position = "none")

fig11
ggsave(file.path(OUT_DIR, "fig11_polarizacion_karma.png"), fig11, width = 12, height = 5, dpi = 300)
cat("✅ Fig 11\n")

# ==============================================================================
# FIG 12 — Violin plot hostilidad × estrategia adversarial
# ==============================================================================
fig12_data <- df_long |>
  select(post_id, comment_author, candidato) |>
  left_join(df_raw |> select(post_id, comment_author, hostilidad, estrategia_final),
            by = c("post_id", "comment_author")) |>
  filter(!is.na(hostilidad), estrategia_final != "ninguna") |>
  mutate(
    estrategia_final = factor(estrategia_final,
                              levels = c("esencializacion", "construccion_amenaza", "atribucion_oculta",
                                         "deslegitimacion", "ridiculizacion"),
                              labels = c("Esencialización", "Construcción\nde amenaza", "Atribución\noculta",
                                         "Deslegitimación", "Ridiculización"))
  )

fig12 <- ggplot(fig12_data, aes(x = estrategia_final, y = hostilidad, fill = estrategia_final)) +
  geom_violin(alpha = 0.7, trim = TRUE, scale = "width") +
  geom_boxplot(width = 0.1, outlier.shape = NA, color = "white") +
  stat_summary(fun = mean, geom = "point", color = "white", size = 2) +
  scale_fill_viridis_d(option = "plasma", guide = "none") +
  scale_y_continuous(limits = c(0, 1), labels = number_format(accuracy = 0.1)) +
  labs(
    title    = "Distribución de hostilidad según estrategia adversarial",
    subtitle = "Violin + boxplot. Punto blanco = media. ¿Qué estrategias generan más hostilidad?",
    x = NULL, y = "Hostilidad discursiva (0–1)",
    caption  = "Fuente: corpus Reddit Chile 2025."
  )

fig12
ggsave(file.path(OUT_DIR, "fig12_hostilidad_estrategia.png"), fig12, width = 10, height = 6, dpi = 300)
cat("✅ Fig 12\n")

# ==============================================================================
# FIG 13 — Evolución de marcos por fase (lollipop chart)
# ==============================================================================
fig13_data <- df_raw |>
  filter(!is.na(marco_final), marco_final != "otro") |>
  count(fase, marco_final) |>
  group_by(fase) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(marco_final = factor(marco_final, levels = MARCOS_LEVELS, labels = MARCOS_LABELS)) |>
  filter(!is.na(marco_final)) |>
  pivot_wider(names_from = fase, values_from = pct, values_fill = 0) |>
  rename(fase1 = `Posicionamiento\n(ago–oct)`, fase2 = `Segunda vuelta\n(nov–dic)`) |>
  mutate(
    cambio = fase2 - fase1,
    direccion = if_else(cambio >= 0, "Aumenta", "Disminuye")
  )

fig13 <- ggplot(fig13_data, aes(y = reorder(marco_final, cambio))) +
  geom_segment(aes(x = fase1, xend = fase2, yend = marco_final,
                   color = direccion), linewidth = 1.5) +
  geom_point(aes(x = fase1), color = "grey60", size = 3.5) +
  geom_point(aes(x = fase2, color = direccion), size = 3.5) +
  scale_color_manual(values = c("Aumenta" = "#27AE60", "Disminuye" = "#C0392B"),
                     name = "Cambio en 2ª vuelta") +
  scale_x_continuous(labels = percent_format()) +
  labs(
    title    = "Cambio en el peso de los marcos entre fases electorales",
    subtitle = "Gris = posicionamiento (ago–oct) | Color = segunda vuelta (nov–dic)",
    x = "Proporción dentro de la fase", y = NULL,
    caption  = "Marcos: Entman (1993). Fuente: corpus Reddit Chile 2025."
  )

fig13
ggsave(file.path(OUT_DIR, "fig13_marcos_por_fase.png"), fig13, width = 9, height = 6, dpi = 300)
cat("✅ Fig 13\n")

# ==============================================================================
# FIG 14 — Cuadrante discursivo 2×2 por candidato
#   Alta/baja hostilidad × inter/intra-bloque
# ==============================================================================
fig14_data <- df_long |>
  select(post_id, comment_author, candidato) |>
  left_join(df_raw |> select(post_id, comment_author, hostilidad, frontera_final),
            by = c("post_id", "comment_author")) |>
  filter(!is.na(hostilidad), frontera_final %in% c("inter_bloque", "intra_bloque", "ninguna")) |>
  mutate(
    cuadrante_host = if_else(hostilidad >= 0.5, "Alta hostilidad", "Baja hostilidad"),
    cuadrante_front = case_when(
      frontera_final == "inter_bloque" ~ "Inter-bloque",
      frontera_final == "intra_bloque" ~ "Intra-bloque",
      TRUE ~ "Sin frontera"
    )
  ) |>
  count(candidato, cuadrante_host, cuadrante_front) |>
  group_by(candidato) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

fig14 <- ggplot(fig14_data, aes(x = cuadrante_front, y = pct, fill = candidato)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.65) +
  geom_text(aes(label = percent(pct, accuracy = 1), y = pct + 0.01),
            position = position_dodge(width = 0.75), size = 2.5, color = "grey30") +
  scale_fill_manual(values = COLORES_CAND, name = NULL) +
  scale_y_continuous(labels = percent_format(), expand = expansion(mult = c(0, 0.1))) +
  facet_wrap(~ cuadrante_host, ncol = 2) +
  labs(
    title    = "Cuadrante discursivo: hostilidad × tipo de frontera política",
    subtitle = "Proporción de comentarios por candidato en cada cuadrante",
    x = NULL, y = "Proporción",
    caption  = "Fuente: corpus Reddit Chile 2025."
  ) +
  theme(axis.text.x = element_text(angle = 15, hjust = 1))

fig14
ggsave(file.path(OUT_DIR, "fig14_cuadrante_discursivo.png"), fig14, width = 10, height = 6, dpi = 300)
cat("✅ Fig 14\n")

# ==============================================================================
# FIG 15 — Emoción predominante por candidato (barras apiladas)
# ==============================================================================
fig15_data <- df_long |>
  select(post_id, comment_author, candidato) |>
  left_join(df_raw |> select(post_id, comment_author, emocion_final),
            by = c("post_id", "comment_author")) |>
  filter(!is.na(emocion_final), emocion_final != "ninguna") |>
  count(candidato, emocion_final) |>
  group_by(candidato) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    candidato     = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")),
    emocion_final = factor(emocion_final,
                           levels = c("indignacion", "ira", "desprecio", "miedo", "esperanza", "alegria", "ironia"),
                           labels = c("Indignación", "Ira", "Desprecio", "Miedo", "Esperanza", "Alegría", "Ironía"))
  )

fig15 <- ggplot(fig15_data, aes(x = candidato, y = pct, fill = emocion_final)) +
  geom_col(width = 0.65) +
  geom_text(data = fig15_data |> filter(pct > 0.07),
            aes(label = percent(pct, accuracy = 1)),
            position = position_stack(vjust = 0.5),
            size = 3, color = "white", fontface = "bold") +
  scale_fill_manual(values = COLORES_EMOCION, name = NULL) +
  scale_y_continuous(labels = percent_format(), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title    = "Repertorio emocional por candidato",
    subtitle = "Proporción de emociones predominantes (excluye 'ninguna')",
    x = NULL, y = "Proporción",
    caption  = "Emociones: Marcus (2000) y Jasper (2011). Fuente: corpus Reddit Chile 2025."
  )

fig15
ggsave(file.path(OUT_DIR, "fig15_emocion_candidato.png"), fig15, width = 9, height = 6, dpi = 300)
cat("✅ Fig 15\n")

# ==============================================================================
# FIG 16 — Hostilidad media por decil de karma
# ==============================================================================
fig16_data <- df_raw |>
  filter(!is.na(comment_score), !is.na(hostilidad)) |>
  mutate(decil_karma = ntile(comment_score, 10)) |>
  group_by(decil_karma) |>
  summarise(
    host_mean   = mean(hostilidad, na.rm = TRUE),
    score_medio = median(comment_score, na.rm = TRUE),
    n           = n(),
    se          = sd(hostilidad, na.rm = TRUE) / sqrt(n),
    .groups     = "drop"
  )

fig16 <- ggplot(fig16_data, aes(x = decil_karma, y = host_mean)) +
  geom_ribbon(aes(ymin = host_mean - se, ymax = host_mean + se), alpha = 0.2, fill = "#2C3E50") +
  geom_line(color = "#2C3E50", linewidth = 1.2) +
  geom_point(aes(size = n), color = "#2C3E50", alpha = 0.8) +
  geom_text(aes(label = score_medio, y = host_mean + se + 0.015),
            size = 2.8, color = "grey50") +
  scale_x_continuous(breaks = 1:10, labels = paste0("D", 1:10)) +
  scale_y_continuous(limits = c(0.2, 0.8), labels = number_format(accuracy = 0.1)) +
  scale_size_continuous(range = c(2, 6), guide = "none") +
  labs(
    title    = "Hostilidad discursiva por decil de karma",
    subtitle = "¿Los comentarios más hostiles reciben más o menos validación comunitaria?\nNúmero sobre punto = karma mediano del decil",
    x = "Decil de karma (D1=más negativo, D10=más positivo)", y = "Hostilidad media",
    caption  = "Fuente: corpus Reddit Chile 2025."
  )

fig16
ggsave(file.path(OUT_DIR, "fig16_hostilidad_decil_karma.png"), fig16, width = 9, height = 5.5, dpi = 300)
cat("✅ Fig 16\n")

# ==============================================================================
# FIG 17 — Proporción de co-menciones por candidato (quién aparece con quién)
# ==============================================================================
fig17_data <- df_raw |>
  filter(n_candidatos > 1) |>
  mutate(lista = str_split(candidatos, ", ")) |>
  unnest(lista) |>
  rename(candidato_focal = lista) |>
  left_join(
    df_raw |> filter(n_candidatos > 1) |>
      mutate(lista = str_split(candidatos, ", ")) |>
      unnest(lista) |>
      rename(candidato_cooc = lista),
    by = "post_id"
  ) |>
  filter(candidato_focal != candidato_cooc) |>
  count(candidato_focal, candidato_cooc) |>
  group_by(candidato_focal) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    candidato_focal = str_to_title(candidato_focal),
    candidato_cooc  = str_to_title(candidato_cooc)
  )

fig17 <- ggplot(fig17_data, aes(x = candidato_cooc, y = pct, fill = candidato_cooc)) +
  geom_col(width = 0.65) +
  geom_text(aes(label = percent(pct, accuracy = 1)), vjust = -0.4, size = 3, color = "grey30") +
  scale_fill_manual(values = COLORES_CAND, guide = "none") +
  scale_y_continuous(labels = percent_format(), expand = expansion(mult = c(0, 0.15))) +
  facet_wrap(~ candidato_focal, nrow = 1) +
  labs(
    title    = "Co-ocurrencia de candidatos en el mismo hilo",
    subtitle = "Para cada candidato focal, ¿con quién aparece más frecuentemente?",
    x = NULL, y = "Proporción de co-menciones",
    caption  = "Solo hilos con 2+ candidatos. Fuente: corpus Reddit Chile 2025."
  )

fig17
ggsave(file.path(OUT_DIR, "fig17_comenciones_pct.png"), fig17, width = 11, height = 5.5, dpi = 300)
cat("✅ Fig 17\n")

# ==============================================================================
# FIG 18 — Evolución de emociones por semana (líneas)
# ==============================================================================
fig18_data <- df_raw |>
  filter(!is.na(emocion_final), emocion_final != "ninguna") |>
  count(semana, emocion_final) |>
  group_by(semana) |>
  mutate(pct = n / sum(n)) |>
  ungroup() |>
  mutate(
    emocion_final = factor(emocion_final,
                           levels = c("indignacion", "ira", "desprecio", "miedo", "esperanza", "alegria", "ironia"),
                           labels = c("Indignación", "Ira", "Desprecio", "Miedo", "Esperanza", "Alegría", "Ironía"))
  )

fig18 <- ggplot(fig18_data, aes(x = semana, y = pct, color = emocion_final)) +
  geom_line(linewidth = 0.9) +
  geom_smooth(method = "loess", se = FALSE, linewidth = 0.4, linetype = "dashed", alpha = 0.5) +
  geom_vline(xintercept = as.Date("2025-10-31"), linetype = "dotted", color = "grey40") +
  scale_color_manual(values = c(COLORES_EMOCION), name = NULL) +
  scale_y_continuous(labels = percent_format()) +
  scale_x_date(date_labels = "%b", date_breaks = "1 month") +
  labs(
    title    = "Evolución semanal del repertorio emocional",
    subtitle = "Peso relativo de cada emoción en la conversación política por semana",
    x = NULL, y = "Proporción semanal",
    caption  = "Fuente: corpus Reddit Chile 2025."
  )

fig18
ggsave(file.path(OUT_DIR, "fig18_evolucion_emociones.png"), fig18, width = 11, height = 6, dpi = 300)
cat("✅ Fig 18\n")

# ==============================================================================
# FIG 19 — Pendiente temporal de hostilidad por candidato (modelo lineal)
# ==============================================================================
library(broom)

df_slopes <- df_raw |>
  mutate(semana_num = as.numeric(semana - min(semana, na.rm = TRUE))) |>
  pivot_longer(cols = starts_with("sent_final_"), names_to = "candidato",
               names_prefix = "sent_final_", values_to = "sentimiento") |>
  filter(!is.na(sentimiento), !is.na(hostilidad)) |>
  mutate(candidato = str_to_title(candidato)) |>
  group_by(candidato) |>
  do(tidy(lm(hostilidad ~ semana_num, data = .))) |>
  ungroup() |>
  filter(term == "semana_num") |>
  mutate(
    candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")),
    ci_low  = estimate - 1.96 * std.error,
    ci_high = estimate + 1.96 * std.error,
    sig     = p.value < 0.05
  )

fig19 <- ggplot(df_slopes, aes(x = candidato, y = estimate, color = candidato)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey60") +
  geom_pointrange(aes(ymin = ci_low, ymax = ci_high), linewidth = 1) +
  geom_text(aes(label = if_else(sig, "p<.05", "n.s."), y = ci_high + 0.0005),
            size = 3, color = "grey40") +
  scale_color_manual(values = COLORES_CAND, guide = "none") +
  labs(
    title    = "Pendiente temporal de la hostilidad por candidato",
    subtitle = "Coeficiente lineal semanal con IC 95%. Valores positivos = hostilidad creciente",
    x = NULL, y = "Pendiente estimada (por semana)",
    caption  = "Fuente: corpus Reddit Chile 2025."
  )

fig19
ggsave(file.path(OUT_DIR, "fig19_pendiente_hostilidad.png"), fig19, width = 8, height = 5, dpi = 300)
cat("✅ Fig 19\n")

# ==============================================================================
# FIG 20 — Panel resumen 2×2 (figura compuesta para presentación)
#   Combina fig1 + fig2 + fig3 + fig5 con patchwork
# ==============================================================================
fig20 <- (fig1 + fig2) / (fig3 + fig5) +
  plot_annotation(
    title    = "Conversación política en Reddit Chile 2025: resumen analítico",
    subtitle = "Sentimiento, hostilidad por fase, marcos interpretativos y estilos discursivos",
    caption  = "Fuente: corpus Reddit r/chile y r/RepublicadeChile, ago–dic 2025.\nClasificación: GPT-4o-mini + DeepSeek Chat con desempate por karma.",
    theme    = theme(
      plot.title    = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 12, color = "grey40")
    )
  )

fig20
ggsave(file.path(OUT_DIR, "fig20_panel_resumen.png"), fig20, width = 16, height = 12, dpi = 300)
cat("✅ Fig 20 (panel resumen)\n")

# ==============================================================================
# RESUMEN FINAL
# ==============================================================================
cat("\n", paste(rep("=", 60), collapse = ""), "\n")
cat("✅ 20 figuras guardadas en:", OUT_DIR, "\n\n")
cat("FIGURAS PRINCIPALES (tesis):\n")
cat("  fig1  — Sentimiento por candidato\n")
cat("  fig2  — Hostilidad por fase y candidato\n")
cat("  fig3  — Heatmap marco × candidato\n")
cat("  fig4  — Estrategias × frontera\n")
cat("  fig5  — Mapa de estilos discursivos\n")
cat("  fig6  — Red de co-menciones\n\n")
cat("FIGURAS COMPLEMENTARIAS (resultados/anexo):\n")
cat("  fig7  — Densidad de polarización (ridgeline)\n")
cat("  fig8  — Volumen de menciones semanal\n")
cat("  fig9  — Calendario de hostilidad\n")
cat("  fig10 — Emoción × marco (heatmap)\n")
cat("  fig11 — Polarización × karma (scatter LOESS)\n")
cat("  fig12 — Hostilidad × estrategia (violin)\n")
cat("  fig13 — Cambio de marcos entre fases\n")
cat("  fig14 — Cuadrante discursivo\n")
cat("  fig15 — Repertorio emocional por candidato\n")
cat("  fig16 — Hostilidad por decil de karma\n")
cat("  fig17 — Co-menciones proporcionales\n")
cat("  fig18 — Evolución semanal de emociones\n")
cat("  fig19 — Pendiente temporal de hostilidad\n")
cat("  fig20 — Panel resumen 2×2\n")
cat(paste(rep("=", 60), collapse = ""), "\n")




# ==============================================================================
# DIAGNÓSTICO Y VERIFICACIÓN DE CLASIFICACIÓN — REDDIT CHILE 2025
# Verifica: cobertura, distribuciones, acuerdo entre modelos,
#           consistencia interna, casos extremos, calidad general
# ==============================================================================

library(tidyverse)
library(scales)
library(here)

# ==============================================================================
# 1. CARGA
# ==============================================================================
df <- read_csv(
  here("data", "processed", "analisis_API.csv"),
  show_col_types = FALSE
) |>
  filter(post_id != "post_id") |>
  mutate(
    fecha                 = as.Date(fecha),
    polarizacion_consenso = as.numeric(polarizacion_consenso),
    oa_polarizacion       = as.numeric(oa_polarizacion),
    ds_polarizacion       = as.numeric(ds_polarizacion),
    comment_score         = as.numeric(comment_score)
  )

cat("=" , strrep("=", 60), "\n")
cat("DIAGNÓSTICO DE CLASIFICACIÓN — REDDIT CHILE 2025\n")
cat("=" , strrep("=", 60), "\n\n")

# ==============================================================================
# 2. COBERTURA BÁSICA
# ==============================================================================
cat("── 1. COBERTURA ─────────────────────────────────────────\n")
cat("Total comentarios clasificados:", nrow(df), "\n")
cat("Rango de fechas:", format(min(df$fecha, na.rm=TRUE)), "→",
    format(max(df$fecha, na.rm=TRUE)), "\n")
cat("Errores OA/A:", sum(df$error_oa_a, na.rm=TRUE),
    "| OA/B:", sum(df$error_oa_b, na.rm=TRUE),
    "| DS/A:", sum(df$error_ds_a, na.rm=TRUE),
    "| DS/B:", sum(df$error_ds_b, na.rm=TRUE), "\n")
cat("Tasa de error total:",
    round(mean(df$error_oa_a | df$error_ds_a | df$error_oa_b | df$error_ds_b,
               na.rm=TRUE) * 100, 2), "%\n\n")

cat("Distribución por candidato:\n")
df |>
  separate_rows(candidatos, sep = ", ") |>
  count(candidatos, name = "n") |>
  mutate(pct = percent(n / nrow(df))) |>
  print()

cat("\nDistribución por tipo de hilo:\n")
df |> count(tipo_hilo) |> mutate(pct = percent(n / sum(n))) |> print()

cat("\nDistribución por fase:\n")
df |>
  mutate(fase = if_else(fecha <= as.Date("2025-10-31"),
                        "Posicionamiento (ago–oct)",
                        "Segunda vuelta (nov–dic)")) |>
  count(fase) |>
  mutate(pct = percent(n / sum(n))) |>
  print()

# ==============================================================================
# 3. POLARIZACIÓN — DISTRIBUCIÓN Y RANGO
# ==============================================================================
cat("\n── 2. POLARIZACIÓN ──────────────────────────────────────\n")
pol <- df$polarizacion_consenso
cat("Media:", round(mean(pol, na.rm=TRUE), 3),
    "| SD:", round(sd(pol, na.rm=TRUE), 3),
    "| Min:", min(pol, na.rm=TRUE),
    "| Max:", max(pol, na.rm=TRUE), "\n")

cat("\nDistribución por rango:\n")
df |>
  mutate(rango = case_when(
    polarizacion_consenso <= 0.1 ~ "0.0–0.1 (neutral)",
    polarizacion_consenso <= 0.3 ~ "0.2–0.3 (moderado)",
    polarizacion_consenso <= 0.5 ~ "0.4–0.5 (crítica)",
    polarizacion_consenso <= 0.7 ~ "0.6–0.7 (ataque)",
    polarizacion_consenso <= 0.9 ~ "0.8–0.9 (insulto)",
    TRUE                         ~ "1.0 (extremo)"
  )) |>
  count(rango) |>
  mutate(pct = percent(n / sum(n))) |>
  print()

cat("\n⚠️  Casos con polarización = 0.0 (¿informativo o error?):\n")
cat("   n =", sum(pol == 0.0, na.rm=TRUE), "\n")
cat("⚠️  Casos con polarización = 1.0 (violencia verbal):\n")
cat("   n =", sum(pol == 1.0, na.rm=TRUE), "\n")

# ==============================================================================
# 4. ACUERDO ENTRE MODELOS (OA vs DS)
# ==============================================================================
cat("\n── 3. ACUERDO ENTRE MODELOS ─────────────────────────────\n")

# Acuerdo en polarización
dif_pol <- abs(df$oa_polarizacion - df$ds_polarizacion)
cat("Diferencia absoluta OA vs DS en polarización:\n")
cat("  Media:", round(mean(dif_pol, na.rm=TRUE), 3),
    "| SD:", round(sd(dif_pol, na.rm=TRUE), 3),
    "| Max:", max(dif_pol, na.rm=TRUE), "\n")
cat("  Acuerdo exacto (dif=0):",
    percent(mean(dif_pol == 0, na.rm=TRUE)), "\n")
cat("  Discrepancia alta (dif>=0.4):",
    percent(mean(dif_pol >= 0.4, na.rm=TRUE)), "\n")

# Acuerdo en variables categóricas
cat("\nAcuerdo exacto OA vs DS por dimensión:\n")
tibble(
  dimension  = c("Marco", "Emoción", "Estrategia", "Frontera"),
  acuerdo    = c(
    mean(df$oa_marco      == df$ds_marco,      na.rm=TRUE),
    mean(df$oa_emocion    == df$ds_emocion,    na.rm=TRUE),
    mean(df$oa_estrategia == df$ds_estrategia, na.rm=TRUE),
    mean(df$oa_frontera   == df$ds_frontera,   na.rm=TRUE)
  )
) |>
  mutate(
    acuerdo_pct = percent(acuerdo),
    interpretacion = case_when(
      acuerdo >= 0.8 ~ "✅ Bueno",
      acuerdo >= 0.6 ~ "⚠️  Moderado",
      TRUE           ~ "❌ Débil"
    )
  ) |>
  select(dimension, acuerdo_pct, interpretacion) |>
  print()

# ==============================================================================
# 5. DISTRIBUCIÓN DE CATEGORÍAS
# ==============================================================================
cat("\n── 4. DISTRIBUCIÓN DE CATEGORÍAS ───────────────────────\n")

cat("\nMarco final:\n")
df |> count(marco_final) |>
  mutate(pct = percent(n / sum(n))) |>
  arrange(desc(n)) |> print()

cat("\nEmoción final:\n")
df |> count(emocion_final) |>
  mutate(pct = percent(n / sum(n))) |>
  arrange(desc(n)) |> print()

cat("\nEstrategia final:\n")
df |> count(estrategia_final) |>
  mutate(pct = percent(n / sum(n))) |>
  arrange(desc(n)) |> print()

cat("\nFrontera final:\n")
df |> count(frontera_final) |>
  mutate(pct = percent(n / sum(n))) |>
  arrange(desc(n)) |> print()

# ==============================================================================
# 6. SENTIMIENTO POR CANDIDATO
# ==============================================================================
cat("\n── 5. SENTIMIENTO POR CANDIDATO ─────────────────────────\n")
for (cand in c("kast", "kaiser", "matthei", "jara")) {
  col <- paste0("sent_final_", cand)
  if (col %in% names(df)) {
    sub <- df |> filter(!is.na(.data[[col]]))
    if (nrow(sub) > 0) {
      cat(sprintf("\n%s (n=%d):\n", toupper(cand), nrow(sub)))
      sub |> count(.data[[col]]) |>
        mutate(pct = percent(n / sum(n))) |>
        rename(sentimiento = 1) |>
        print()
    }
  }
}

# ==============================================================================
# 7. CONSISTENCIA INTERNA — TESTS LÓGICOS
# ==============================================================================
cat("\n── 6. CONSISTENCIA INTERNA ──────────────────────────────\n")

# Test 1: frontera inter_bloque en hilos solo_derecha (debería ser raro)
n_error_frontera <- df |>
  filter(tipo_hilo %in% c("solo_derecha", "solo_derecha_multiple"),
         frontera_final == "inter_bloque") |>
  nrow()
cat("⚠️  inter_bloque en hilos solo_derecha:", n_error_frontera,
    sprintf("(%.1f%% del total)", n_error_frontera/nrow(df)*100), "\n")

# Test 2: alta polarización + ninguna emoción (posible inconsistencia)
n_pol_sin_emocion <- df |>
  filter(polarizacion_consenso >= 0.7, emocion_final == "ninguna") |>
  nrow()
cat("⚠️  Pol>=0.7 + emoción=ninguna:", n_pol_sin_emocion,
    sprintf("(%.1f%%)", n_pol_sin_emocion/nrow(df)*100), "\n")

# Test 3: estrategia adversarial + frontera=ninguna
n_est_sin_frontera <- df |>
  filter(estrategia_final != "ninguna", frontera_final == "ninguna") |>
  nrow()
cat("⚠️  Estrategia + frontera=ninguna:", n_est_sin_frontera,
    sprintf("(%.1f%%)", n_est_sin_frontera/nrow(df)*100), "\n")

# Test 4: comentarios con score muy negativo y polarización baja
n_score_neg_pol_baja <- df |>
  filter(comment_score <= -10, polarizacion_consenso <= 0.2) |>
  nrow()
cat("⚠️  Score<=-10 + pol<=0.2:", n_score_neg_pol_baja,
    sprintf("(%.1f%%)", n_score_neg_pol_baja/nrow(df)*100), "\n")

# ==============================================================================
# 8. CORRELACIÓN KARMA × POLARIZACIÓN
# ==============================================================================
cat("\n── 7. CORRELACIÓN KARMA × POLARIZACIÓN ─────────────────\n")
df_cor <- df |> filter(!is.na(comment_score), !is.na(polarizacion_consenso))
r <- cor(df_cor$comment_score, df_cor$polarizacion_consenso, use = "complete.obs")
cat("Correlación Pearson (karma × polarización):", round(r, 3), "\n")
cat("Interpretación:",
    if (abs(r) < 0.1) "prácticamente nula"
    else if (abs(r) < 0.3) "débil"
    else if (abs(r) < 0.5) "moderada"
    else "fuerte", "\n")

# Deciles de karma
cat("\nPolarización media por decil de karma:\n")
df |>
  filter(!is.na(comment_score), !is.na(polarizacion_consenso)) |>
  mutate(decil_karma = ntile(comment_score, 10)) |>
  group_by(decil_karma) |>
  summarise(
    karma_medio = round(mean(comment_score), 1),
    pol_media   = round(mean(polarizacion_consenso), 3),
    n           = n(),
    .groups = "drop"
  ) |>
  print()

# ==============================================================================
# 9. MUESTRA DE CASOS EXTREMOS PARA REVISIÓN MANUAL
# ==============================================================================
cat("\n── 8. CASOS EXTREMOS PARA REVISIÓN MANUAL ───────────────\n")

cat("\n🔴 Top 5 comentarios más hostiles (pol >= 0.9):\n")
df |>
  filter(polarizacion_consenso >= 0.9) |>
  select(fecha, candidatos, polarizacion_consenso,
         emocion_final, estrategia_final, comentario_texto) |>
  mutate(comentario_texto = str_trunc(comentario_texto, 120)) |>
  arrange(desc(polarizacion_consenso)) |>
  slice_head(n = 5) |>
  print(width = 120)

cat("\n🟢 Top 5 comentarios más neutrales (pol <= 0.1):\n")
df |>
  filter(polarizacion_consenso <= 0.1) |>
  select(fecha, candidatos, polarizacion_consenso,
         marco_final, emocion_final, comentario_texto) |>
  mutate(comentario_texto = str_trunc(comentario_texto, 120)) |>
  slice_head(n = 5) |>
  print(width = 120)

cat("\n⚠️  Top 5 discrepancias OA vs DS en polarización:\n")
df |>
  mutate(dif = abs(oa_polarizacion - ds_polarizacion)) |>
  filter(!is.na(dif)) |>
  select(fecha, candidatos, oa_polarizacion, ds_polarizacion,
         polarizacion_consenso, dif, comentario_texto) |>
  mutate(comentario_texto = str_trunc(comentario_texto, 100)) |>
  arrange(desc(dif)) |>
  slice_head(n = 5) |>
  print(width = 120)

# ==============================================================================
# 10. RESUMEN EJECUTIVO
# ==============================================================================
cat("\n", strrep("=", 62), "\n")
cat("RESUMEN EJECUTIVO\n")
cat(strrep("=", 62), "\n")
cat(sprintf("Total clasificados:        %d comentarios\n", nrow(df)))
cat(sprintf("Tasa de error API:         %.2f%%\n",
            mean(df$error_oa_a | df$error_ds_a | df$error_oa_b | df$error_ds_b,
                 na.rm=TRUE) * 100))
cat(sprintf("Polarización media:        %.3f (SD=%.3f)\n",
            mean(pol, na.rm=TRUE), sd(pol, na.rm=TRUE)))
cat(sprintf("Acuerdo marco OA/DS:       %s\n",
            percent(mean(df$oa_marco == df$ds_marco, na.rm=TRUE))))
cat(sprintf("Acuerdo emoción OA/DS:     %s\n",
            percent(mean(df$oa_emocion == df$ds_emocion, na.rm=TRUE))))
cat(sprintf("Acuerdo frontera OA/DS:    %s\n",
            percent(mean(df$oa_frontera == df$ds_frontera, na.rm=TRUE))))
cat(sprintf("Error frontera (inter en solo_derecha): %d casos (%.1f%%)\n",
            n_error_frontera, n_error_frontera/nrow(df)*100))
cat(sprintf("Correlación karma×pol:     r = %.3f\n", r))
cat(strrep("=", 62), "\n")


library(tidyverse)
library(scales)
library(lubridate)
library(here)
library(zoo)

COLORES_CAND <- c(
  "Kast"    = "#C0392B",
  "Kaiser"  = "#E67E22",
  "Matthei" = "#2980B9",
  "Jara"    = "#27AE60"
)

df <- read_csv(
  here("data", "processed", "analisis_API.csv"),
  show_col_types = FALSE
) |>
  filter(post_id != "post_id") |>
  mutate(
    fecha                 = as.Date(fecha),
    polarizacion_consenso = as.numeric(polarizacion_consenso),
    # 0 = neutral, 1 = máxima hostilidad
    hostilidad            = polarizacion_consenso,
    semana                = floor_date(fecha, "week")
  )

# Dataset largo por candidato
fig_data <- df |>
  pivot_longer(
    cols         = starts_with("sent_final_"),
    names_to     = "candidato",
    names_prefix = "sent_final_",
    values_to    = "sentimiento"
  ) |>
  filter(!is.na(sentimiento), !is.na(hostilidad)) |>
  mutate(candidato = str_to_title(candidato)) |>
  group_by(semana, candidato) |>
  summarise(
    host_mean = mean(hostilidad, na.rm = TRUE),
    se        = sd(hostilidad, na.rm = TRUE) / sqrt(n()),
    n         = n(),
    ci_low    = pmax(host_mean - 1.96 * se, 0),
    ci_high   = pmin(host_mean + 1.96 * se, 1),
    .groups   = "drop"
  ) |>
  filter(n >= 5, host_mean > 0.1) |>   # ← aquí el filtro
  arrange(candidato, semana) |>
  group_by(candidato) |>
  mutate(ma3 = rollmean(host_mean, k = 3, fill = NA, align = "center")) |>
  ungroup() |>
  mutate(candidato = factor(candidato, levels = c("Kast", "Kaiser", "Matthei", "Jara")))

fig <- ggplot(fig_data, aes(x = semana, color = candidato, fill = candidato)) +
  # Banda IC 95%
  geom_ribbon(
    aes(ymin = ci_low, ymax = ci_high),
    alpha = 0.10, color = NA
  ) +
  # Línea semanal punteada
  geom_line(aes(y = host_mean), linewidth = 0.5, linetype = "dotted", alpha = 0.6) +
  # Media móvil 3 semanas — línea principal
  geom_line(aes(y = ma3), linewidth = 1.1, na.rm = TRUE) +
  # Línea de referencia neutra
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  annotate("text",
           x = as.Date("2025-08-10"), y = 0.52,
           label = "punto medio (0.5)", size = 2.8, color = "grey50", hjust = 0) +
  # Separador de fases
  geom_vline(xintercept = as.Date("2025-10-31"),
             linetype = "dashed", color = "#C0392B", linewidth = 0.5) +
  annotate("text",
           x = as.Date("2025-10-31"), y = 0.72,
           label = "1ª vuelta", angle = 90,
           vjust = -0.4, size = 2.8, color = "#C0392B") +
  scale_color_manual(values = COLORES_CAND, name = NULL) +
  scale_fill_manual(values  = COLORES_CAND, name = NULL) +
  scale_y_continuous(
    limits = c(0.1, 0.8),
    breaks = seq(0.1, 0.8, 0.1),
    labels = number_format(accuracy = 0.1)
  ) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") +
  labs(
    title    = "Evolución de la hostilidad discursiva por candidato",
    subtitle = "0 = neutral | 1 = máxima hostilidad. Línea gruesa = media móvil 3 semanas. Banda = IC 95%.",
    x        = NULL,
    y        = "Índice de hostilidad",
    caption  = "Solo semanas con n ≥ 5 comentarios por candidato.\nFuente: corpus Reddit Chile 2025."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title      = element_text(size = 14, face = "bold"),
    plot.subtitle   = element_text(size = 10, color = "grey40"),
    plot.caption    = element_text(size = 8,  color = "grey50"),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

fig

# ggsave(here("outputs", "figuras", "fig_hostilidad_tendencial.png"),
#        fig, width = 11, height = 6, dpi = 300)


