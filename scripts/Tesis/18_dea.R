# =============================================================
# 02) Exploración y Estadísticos Descriptivos
# =============================================================
# Análisis exploratorio de datos filtrados
# Lee de: data/processed/reddit_filtrado.rds
# Guarda en: outputs/exploracion/
# =============================================================

rm(list = ls())
set.seed(123)

# Setup
pacman::p_load(
  tidyverse, lubridate, here, readr, scales, 
  knitr, kableExtra, summarytools, viridis
)

# =============================================================
# CONFIGURACIÓN
# =============================================================
OUT_DIR <- here("outputs", "exploracion")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# =============================================================
# 1) CARGA DE DATOS
# =============================================================
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("🔍 EXPLORACIÓN Y ESTADÍSTICOS DESCRIPTIVOS\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

cat("\n📂 Cargando datos...\n")
df <- readRDS(here("data/processed/reddit_filtrado.rds"))
cat(sprintf("   ✅ Datos cargados: %d filas, %d columnas\n", nrow(df), ncol(df)))

# =============================================================
# 2) RESUMEN GENERAL
# =============================================================
cat("\n📊 RESUMEN GENERAL DEL DATASET\n")
cat(paste0(rep("-", 70), collapse = ""), "\n")

# Dimensiones
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

# =============================================================
# 3) ESTADÍSTICOS DESCRIPTIVOS POR CANDIDATO
# =============================================================
cat("\n📈 ESTADÍSTICOS POR CANDIDATO\n")
cat(paste0(rep("-", 70), collapse = ""), "\n")

# Totales por candidato
menciones_totales <- df %>%
  summarise(
    Kast = sum(kast, na.rm = TRUE),
    Kaiser = sum(kaiser, na.rm = TRUE),
    Matthei = sum(matthei, na.rm = TRUE),
    Jara = sum(jara, na.rm = TRUE),
    Parisi = sum(parisi, na.rm = TRUE),
    Mayne_Nicholls = sum(mayne_nicholls, na.rm = TRUE),
    MEO = sum(meo, na.rm = TRUE),
    Artes = sum(artes, na.rm = TRUE)
  ) %>%
  pivot_longer(everything(), names_to = "candidato", values_to = "menciones") %>%
  arrange(desc(menciones)) %>%
  mutate(
    porcentaje = round(menciones / sum(menciones) * 100, 2),
    ranking = row_number()
  )

print(menciones_totales)

# Guardar tabla
write_csv(menciones_totales, file.path(OUT_DIR, "menciones_totales_por_candidato.csv"))

# Estadísticos por fecha
cat("\n📅 EVOLUCIÓN TEMPORAL\n")
cat(paste0(rep("-", 70), collapse = ""), "\n")

menciones_por_fecha <- df %>%
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
  )

# Estadísticos de series temporales
stats_temporales <- menciones_por_fecha %>%
  select(-fecha, -Total) %>%
  summarise_all(list(
    media = mean,
    mediana = median,
    desv_est = sd,
    min = min,
    max = max
  ), na.rm = TRUE)

cat("\nEstadísticos diarios por candidato:\n")
print(stats_temporales)

# Guardar serie temporal
write_csv(menciones_por_fecha, file.path(OUT_DIR, "menciones_por_fecha.csv"))

# =============================================================
# 4) VISUALIZACIONES TEMPORALES
# =============================================================
cat("\n📊 Generando visualizaciones temporales...\n")

# Preparar datos para visualización (formato long)
menciones_por_fecha_long <- menciones_por_fecha %>%
  select(-Total) %>%
  pivot_longer(-fecha, names_to = "candidato", values_to = "menciones") %>%
  filter(!is.na(fecha))

# Colores por personaje
colores_personajes <- c(
  "Kast" = "#3498db",           # Azul
  "Kaiser" = "#27ae60",         # Verde
  "Matthei" = "#f1c40f",        # Amarillo
  "Jara" = "#e74c3c",           # Rojo
  "Parisi" = "#95a5a6",         # Gris
  "Mayne_Nicholls" = "#9b59b6"  # Morado
)

# Gráfico 1: Menciones separadas (cada personaje en su propia línea)
fig1 <- menciones_por_fecha_long %>%
  ggplot(aes(x = fecha, y = menciones, color = candidato)) +
  geom_line(linewidth = 1.2, alpha = 0.8) +
  scale_color_manual(values = colores_personajes) +
  scale_x_date(date_labels = "%d %b", date_breaks = "1 week") +
  labs(
    title = "Evolución Temporal de Menciones por Candidato",
    subtitle = "Líneas separadas por personaje",
    x = "Fecha",
    y = "Número de Menciones",
    color = "Candidato"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
    plot.subtitle = element_text(hjust = 0.5, color = "grey40"),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom"
  )

fig1

ggsave(file.path(OUT_DIR, "01_menciones_separadas.png"), 
       fig1, width = 25, height = 15, units = "cm", dpi = 300)
cat("   💾 Guardado: 01_menciones_separadas.png\n")

# Gráfico 2: Menciones apiladas (área apilada)
fig2 <- menciones_por_fecha_long %>%
  ggplot(aes(x = fecha, y = menciones, fill = candidato)) +
  geom_area(position = "stack", alpha = 0.7, color = "white", linewidth = 0.3) +
  scale_fill_manual(values = colores_personajes) +
  scale_x_date(date_labels = "%d %b", date_breaks = "1 week") +
  labs(
    title = "Evolución Temporal de Menciones - Apiladas",
    subtitle = "Área apilada mostrando total de menciones",
    x = "Fecha",
    y = "Número de Menciones (Acumulado)",
    fill = "Candidato"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
    plot.subtitle = element_text(hjust = 0.5, color = "grey40"),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom"
  )

fig2

ggsave(file.path(OUT_DIR, "02_menciones_apiladas.png"), 
       fig2, width = 25, height = 15, units = "cm", dpi = 300)
cat("   💾 Guardado: 02_menciones_apiladas.png\n")

# Gráfico 3: Menciones apiladas como líneas (líneas apiladas)
# Calcular valores acumulados para apilar líneas
menciones_apiladas <- menciones_por_fecha_long %>%
  arrange(fecha, candidato) %>%
  group_by(fecha) %>%
  mutate(
    orden = match(candidato, c("Kast", "Kaiser", "Matthei", "Jara", "Parisi", "Mayne_Nicholls")),
    orden = ifelse(is.na(orden), 999, orden)
  ) %>%
  arrange(fecha, orden) %>%
  group_by(fecha) %>%
  mutate(
    menciones_acum = cumsum(menciones),
    menciones_base = lag(menciones_acum, default = 0)
  ) %>%
  ungroup()

fig3 <- menciones_apiladas %>%
  ggplot(aes(x = fecha)) +
  geom_ribbon(aes(ymin = menciones_base, ymax = menciones_acum, fill = candidato), 
              alpha = 0.7, color = "white", linewidth = 0.3) +
  scale_fill_manual(values = colores_personajes) +
  scale_x_date(date_labels = "%d %b", date_breaks = "1 week") +
  labs(
    title = "Evolución Temporal de Menciones - Líneas Apiladas",
    subtitle = "Menciones acumuladas por candidato",
    x = "Fecha",
    y = "Número de Menciones (Acumulado)",
    fill = "Candidato"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
    plot.subtitle = element_text(hjust = 0.5, color = "grey40"),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom"
  )

fig3

ggsave(file.path(OUT_DIR, "03_menciones_lineas_apiladas.png"), 
       fig3, width = 25, height = 15, units = "cm", dpi = 300)
cat("   💾 Guardado: 03_menciones_lineas_apiladas.png\n")

# =============================================================
# 4) ANÁLISIS DE USUARIOS
# =============================================================
cat("\n👥 ANÁLISIS DE USUARIOS\n")
cat(paste0(rep("-", 70), collapse = ""), "\n")

# Distribución de comentarios por usuario
distribucion_usuarios <- df %>%
  filter(comment_author != "[deleted]", !is.na(comment_author)) %>%
  count(comment_author, sort = TRUE) %>%
  summarise(
    usuarios_totales = n(),
    usuarios_1_comentario = sum(n == 1),
    usuarios_2_5_comentarios = sum(n >= 2 & n <= 5),
    usuarios_6_10_comentarios = sum(n >= 6 & n <= 10),
    usuarios_mas_10 = sum(n > 10),
    media_comentarios = mean(n),
    mediana_comentarios = median(n),
    max_comentarios = max(n)
  )

print(distribucion_usuarios)

# Top usuarios
top_usuarios <- df %>%
  filter(comment_author != "[deleted]", !is.na(comment_author)) %>%
  count(comment_author, sort = TRUE) %>%
  head(20)

cat("\nTop 20 usuarios por número de comentarios:\n")
print(top_usuarios)

write_csv(top_usuarios, file.path(OUT_DIR, "top_20_usuarios.csv"))

# =============================================================
# 5) ANÁLISIS DE LONGITUD DE COMENTARIOS
# =============================================================
cat("\n📏 ANÁLISIS DE LONGITUD DE TEXTOS\n")
cat(paste0(rep("-", 70), collapse = ""), "\n")

df_longitud <- df %>%
  mutate(
    longitud_comentario = str_count(comment_body, "\\S+"),
    longitud_titulo = str_count(post_title, "\\S+"),
    longitud_selftext = str_count(post_selftext, "\\S+")
  )

stats_longitud <- df_longitud %>%
  summarise(
    comentario_media = mean(longitud_comentario, na.rm = TRUE),
    comentario_mediana = median(longitud_comentario, na.rm = TRUE),
    comentario_min = min(longitud_comentario, na.rm = TRUE),
    comentario_max = max(longitud_comentario, na.rm = TRUE),
    titulo_media = mean(longitud_titulo, na.rm = TRUE),
    selftext_media = mean(longitud_selftext, na.rm = TRUE)
  )

print(stats_longitud)

write_csv(stats_longitud, file.path(OUT_DIR, "estadisticos_longitud_textos.csv"))

# =============================================================
# 6) RESUMEN FINAL
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("✅ EXPLORACIÓN COMPLETADA\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat(sprintf("\n💾 Resultados guardados en: %s\n", OUT_DIR))
cat("\nArchivos generados:\n")
cat("  - menciones_totales_por_candidato.csv\n")
cat("  - menciones_por_fecha.csv\n")
cat("  - top_20_usuarios.csv\n")
cat("  - estadisticos_longitud_textos.csv\n")
cat("  - 01_menciones_separadas.png\n")
cat("  - 02_menciones_apiladas.png\n")
cat("  - 03_menciones_lineas_apiladas.png\n")

