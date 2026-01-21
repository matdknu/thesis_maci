# =============================================================
# 03) Análisis Textual de Posts - Visualizaciones
# Topic Modeling, Análisis de Emociones y Visualizaciones Descriptivas
# Enfoque: SOLO POSTS (no comentarios)
# Usa: quanteda, tidytext, topicmodels, stm, sentiment analysis
# =============================================================

# Setup
pacman::p_load(
  tidyverse, tidytext, quanteda, quanteda.textstats, quanteda.textplots,
  topicmodels, stm, tm, SnowballC,
  here, readr, scales, ggtext, patchwork, jtools,
  wordcloud, RColorBrewer, viridis, widyr
)

set.seed(123)

# Rutas
OUT_DIR <- here("outputs", "analisis_textual_posts")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

FIG_DIR <- file.path(OUT_DIR, "figuras")
if (!dir.exists(FIG_DIR)) dir.create(FIG_DIR, recursive = TRUE)

# Base theme para visualizaciones
theme_thesis <- function(legend.pos = "bottom", ...) {
  theme_apa(
    legend.pos = legend.pos,
    legend.use.title = FALSE,
    legend.font.size = 11,
    x.font.size = 11,
    y.font.size = 11,
    facet.title.size = 11,
    remove.y.gridlines = TRUE,
    remove.x.gridlines = TRUE,
    ...
  ) +
    theme(
      plot.title = element_text(hjust = 0.5, margin = margin(b = 8), size = 13),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40", margin = margin(b = 12), size = 11),
      plot.caption = element_text(hjust = 0, color = "grey50", margin = margin(t = 8), size = 9),
      axis.text.x = element_text(angle = 45, hjust = 1),
      plot.margin = margin(10, 15, 10, 15)
    )
}

# Función para guardar figuras
save_fig <- function(plot, filename, width_cm = 16, height_cm = 12, dpi = 300) {
  ggsave(
    filename = file.path(FIG_DIR, filename),
    plot = plot,
    width = width_cm,
    height = height_cm,
    units = "cm",
    dpi = dpi
  )
}

# =============================================================
# 1) Carga y Preparación de Datos - SOLO POSTS
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📂 CARGA Y PREPARACIÓN DE DATOS - POSTS\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

df_raw <- readRDS(here("data/processed/reddit_filtrado.rds"))
cat(sprintf("   ✅ Datos cargados: %d filas\n", nrow(df_raw)))

# Extraer SOLO POSTS únicos (no comentarios)
df_posts <- df_raw %>%
  select(post_id, post_title, post_selftext, post_created, post_author, fecha,
         kast, kaiser, matthei, jara) %>%
  distinct(post_id, .keep_all = TRUE) %>%
  mutate(
    # Combinar título y texto del post
    texto_post = paste(
      coalesce(post_title, ""),
      coalesce(post_selftext, ""),
      sep = " "
    ) %>%
      str_trim() %>%
      str_squish(),
    # Longitud del texto
    n_palabras = str_count(texto_post, "\\S+"),
    n_caracteres = nchar(texto_post),
    # Candidato mencionado
    candidato_mencionado = case_when(
      kast == 1 ~ "Kast",
      kaiser == 1 ~ "Kaiser",
      matthei == 1 ~ "Matthei",
      jara == 1 ~ "Jara",
      TRUE ~ "Otro"
    )
  ) %>%
  filter(
    !is.na(texto_post),
    texto_post != "",
    texto_post != " ",
    n_caracteres >= 20,
    n_palabras >= 5  # Mínimo de palabras para análisis
  )

cat(sprintf("   ✅ Posts únicos: %d\n", nrow(df_posts)))
cat(sprintf("   📊 Posts por candidato:\n"))
print(table(df_posts$candidato_mencionado))

# =============================================================
# 2) Procesamiento con Tidytext
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📝 PROCESAMIENTO DE TEXTO - TIDYTEXT\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Tokenización
tokens_posts <- df_posts %>%
  unnest_tokens(word, texto_post) %>%
  anti_join(stop_words, by = "word") %>%
  filter(
    str_length(word) > 2,
    !str_detect(word, "^\\d+$"),  # Eliminar solo números
    !str_detect(word, "^http"),   # Eliminar URLs
    !str_detect(word, "^www\\.")
  ) %>%
  count(post_id, word, sort = TRUE)

cat(sprintf("   ✅ Tokens únicos: %d\n", n_distinct(tokens_posts$word)))
cat(sprintf("   📊 Total de tokens: %d\n", sum(tokens_posts$n)))

# Análisis de frecuencia de palabras
word_freq <- tokens_posts %>%
  count(word, sort = TRUE) %>%
  filter(n >= 10)  # Palabras que aparecen al menos 10 veces

cat(sprintf("   📊 Palabras con frecuencia >= 10: %d\n", nrow(word_freq)))

# Guardar frecuencia de palabras
write_csv(word_freq, file.path(OUT_DIR, "frecuencia_palabras.csv"))

# =============================================================
# 3) Visualizaciones Básicas de Texto
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📊 VISUALIZACIONES BÁSICAS\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# 3.1) Top 20 palabras más frecuentes
fig_top_words <- word_freq %>%
  slice_head(n = 20) %>%
  mutate(word = fct_reorder(word, n)) %>%
  ggplot(aes(x = n, y = word)) +
  geom_col(fill = "grey50", alpha = 0.8, color = "black", linewidth = 0.3) +
  scale_x_continuous(labels = label_number(), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Top 20 palabras más frecuentes en posts",
    subtitle = "Frecuencia de palabras después de eliminar stopwords",
    x = "Frecuencia",
    y = NULL,
    caption = "Fuente: Elaboración propia a partir de posts de Reddit."
  ) +
  theme_thesis()

save_fig(fig_top_words, "01_top_palabras_frecuentes.png", width_cm = 18, height_cm = 14)

# 3.2) Top palabras por candidato
word_by_candidate <- tokens_posts %>%
  left_join(df_posts %>% select(post_id, candidato_mencionado), by = "post_id") %>%
  filter(candidato_mencionado != "Otro") %>%
  count(candidato_mencionado, word, sort = TRUE) %>%
  group_by(candidato_mencionado) %>%
  slice_head(n = 15) %>%
  ungroup() %>%
  mutate(word = fct_reorder(word, n))

fig_words_by_candidate <- word_by_candidate %>%
  ggplot(aes(x = n, y = word, fill = candidato_mencionado)) +
  geom_col(alpha = 0.8, color = "black", linewidth = 0.3) +
  facet_wrap(~ candidato_mencionado, scales = "free_y", ncol = 2) +
  scale_fill_grey(start = 0.3, end = 0.9, guide = "none") +
  scale_x_continuous(labels = label_number(), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Top 15 palabras por candidato mencionado",
    subtitle = "Palabras más frecuentes en posts que mencionan a cada candidato",
    x = "Frecuencia",
    y = NULL,
    caption = "Fuente: Elaboración propia a partir de posts de Reddit."
  ) +
  theme_thesis() +
  theme(
    strip.background = element_rect(fill = "grey95", color = NA),
    strip.text = element_text(margin = margin(5, 0, 5, 0))
  )

save_fig(fig_words_by_candidate, "02_palabras_por_candidato.png", width_cm = 20, height_cm = 16)

# 3.3) Distribución de longitud de posts
fig_longitud_posts <- df_posts %>%
  ggplot(aes(x = n_palabras)) +
  geom_histogram(bins = 50, fill = "grey50", alpha = 0.7, color = "black", linewidth = 0.2) +
  scale_x_continuous(labels = label_number(), expand = expansion(mult = c(0, 0.02))) +
  scale_y_continuous(labels = label_number(), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Distribución de longitud de posts (palabras)",
    subtitle = "Histograma de número de palabras por post",
    x = "Número de palabras",
    y = "Frecuencia",
    caption = "Fuente: Elaboración propia a partir de posts de Reddit."
  ) +
  theme_thesis()

save_fig(fig_longitud_posts, "03_distribucion_longitud_posts.png", width_cm = 18, height_cm = 12)

# =============================================================
# 4) Análisis con Quanteda
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("🔍 ANÁLISIS CON QUANTEDA\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Crear corpus quanteda
corpus_posts <- corpus(df_posts, text_field = "texto_post")

# Crear Document-Feature Matrix
dfm_posts <- corpus_posts %>%
  tokens(
    remove_punct = TRUE,
    remove_numbers = TRUE,
    remove_symbols = TRUE,
    remove_url = TRUE
  ) %>%
  tokens_remove(pattern = stopwords("spanish")) %>%
  tokens_remove(pattern = stopwords("english")) %>%
  tokens_wordstem(language = "spanish") %>%
  tokens_select(min_nchar = 3) %>%
  dfm()

# Limpiar DFM (remover términos muy raros)
dfm_posts <- dfm_trim(dfm_posts, min_termfreq = 5)

cat(sprintf("   ✅ DFM creado: %d documentos, %d términos\n", 
            nrow(dfm_posts), ncol(dfm_posts)))

# Estadísticas del texto
text_stats <- textstat_summary(dfm_posts)
write_csv(text_stats, file.path(OUT_DIR, "estadisticas_texto_quanteda.csv"))

# 4.1) Wordcloud global
png(file.path(FIG_DIR, "04_wordcloud_global.png"), 
    width = 20, height = 20, units = "cm", res = 300)
textplot_wordcloud(dfm_posts, max_words = 100, random_order = FALSE,
                   rotation = 0.25, color = RColorBrewer::brewer.pal(8, "Dark2"))
dev.off()

# 4.2) Wordclouds por candidato
for (cand in c("Kast", "Kaiser", "Matthei", "Jara")) {
  dfm_cand <- dfm_subset(dfm_posts, 
                         df_posts[docnames(dfm_posts), "candidato_mencionado"] == cand)
  
  if (nrow(dfm_cand) > 0) {
    png(file.path(FIG_DIR, sprintf("05_wordcloud_%s.png", tolower(cand))), 
        width = 20, height = 20, units = "cm", res = 300)
    textplot_wordcloud(dfm_cand, max_words = 80, random_order = FALSE,
                       rotation = 0.25, color = RColorBrewer::brewer.pal(8, "Dark2"))
    dev.off()
  }
}

# =============================================================
# 5) Topic Modeling - LDA
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📚 TOPIC MODELING - LDA\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Convertir DFM a formato topicmodels
dtm_posts <- convert(dfm_posts, to = "topicmodels")

# Determinar número óptimo de topics (prueba con varios K)
K_values <- c(4, 6, 8, 10)
lda_models <- list()

for (K in K_values) {
  cat(sprintf("\n   Ajustando LDA con K=%d topics...\n", K))
  lda_models[[as.character(K)]] <- LDA(
    dtm_posts, 
    k = K, 
    method = "Gibbs",
    control = list(seed = 123, burnin = 1000, iter = 2000, keep = 50)
  )
}

lda_models


# Usar modelo con K=6 (ajustar según necesidad)
K_selected <- 8
lda_model <- lda_models[[as.character(K_selected)]]

# Guardar modelo
saveRDS(lda_model, file.path(OUT_DIR, "lda_model_k6.rds"))

# Extraer topics y términos
lda_topics <- tidy(lda_model, matrix = "beta")
lda_documents <- tidy(lda_model, matrix = "gamma")

# Guardar resultados
write_csv(lda_topics, file.path(OUT_DIR, "lda_topics_beta.csv"))
write_csv(lda_documents, file.path(OUT_DIR, "lda_documents_gamma.csv"))

cat(sprintf("   ✅ Modelo LDA con K=%d topics completado\n", K_selected))

# 5.1) Top términos por topic
top_terms_lda <- lda_topics %>%
  group_by(topic) %>%
  slice_max(beta, n = 10) %>%
  ungroup() %>%
  arrange(topic, -beta)

write_csv(top_terms_lda, file.path(OUT_DIR, "lda_top_terms.csv"))

# Visualización: Top términos por topic
fig_lda_topics <- top_terms_lda %>%
  mutate(
    topic_label = paste("Topic", topic),
    term = reorder(term, beta)
  ) %>%
  ggplot(aes(x = beta, y = term, fill = factor(topic))) +
  geom_col(alpha = 0.8, color = "black", linewidth = 0.2, show.legend = FALSE) +
  facet_wrap(~ topic_label, scales = "free_y", ncol = 3) +
  scale_fill_grey(start = 0.2, end = 0.9) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Top 10 términos por topic (LDA)",
    subtitle = sprintf("Modelo LDA con K=%d topics", K_selected),
    x = "Probabilidad (beta)",
    y = NULL,
    caption = "Fuente: Elaboración propia. Modelo LDA aplicado a posts de Reddit."
  ) +
  theme_thesis() +
  theme(
    strip.background = element_rect(fill = "grey95", color = NA),
    strip.text = element_text(margin = margin(5, 0, 5, 0))
  )

save_fig(fig_lda_topics, "06_lda_top_terms.png", width_cm = 24, height_cm = 18)

# 5.2) Distribución de topics por post
top_topic_per_doc <- lda_documents %>%
  group_by(document) %>%
  slice_max(gamma, n = 1) %>%
  ungroup() %>%
  mutate(document = as.integer(document))

topic_dist <- top_topic_per_doc %>%
  count(topic, sort = TRUE) %>%
  mutate(
    topic_label = paste("Topic", topic),
    pct = n / sum(n) * 100
  )

fig_topic_dist <- topic_dist %>%
  ggplot(aes(x = reorder(topic_label, n), y = n)) +
  geom_col(fill = "grey50", alpha = 0.8, color = "black", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%d\n(%.1f%%)", n, pct)), 
            hjust = -0.1, size = 3.5) +
  scale_y_continuous(labels = label_number(), expand = expansion(mult = c(0, 0.15))) +
  coord_flip() +
  labs(
    title = "Distribución de topics en posts",
    subtitle = "Número de posts asignados a cada topic",
    x = NULL,
    y = "Número de posts",
    caption = "Fuente: Elaboración propia. Modelo LDA."
  ) +
  theme_thesis()

save_fig(fig_topic_dist, "07_distribucion_topics.png", width_cm = 18, height_cm = 12)

# =============================================================
# 6) Topic Modeling - STM (Structural Topic Model)
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📚 TOPIC MODELING - STM\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Preparar datos para STM
processed_stm <- textProcessor(
  documents = df_posts$texto_post,
  metadata = df_posts %>% 
    select(post_id, fecha, candidato_mencionado, kast, kaiser, matthei, jara),
  lowercase = TRUE,
  removestopwords = TRUE,
  removenumbers = TRUE,
  removepunctuation = TRUE,
  stem = TRUE,
  customstopwords = c("reddit", "chile", "chileno", "chilena")
)

prep_stm <- prepDocuments(
  processed_stm$documents,
  processed_stm$vocab,
  processed_stm$meta,
  lower.thresh = 5  # Términos que aparecen en al menos 5 documentos
)

cat(sprintf("   ✅ STM preparado: %d documentos, %d términos\n", 
            prep_stm$meta$N, length(prep_stm$vocab)))

# Ajustar modelo STM (K=6 topics)
K_stm <- 6
stm_model <- stm(
  documents = prep_stm$documents,
  vocab = prep_stm$vocab,
  K = K_stm,
  data = prep_stm$meta,
  prevalence = ~ candidato_mencionado + s(fecha),
  max.em.its = 75,
  init.type = "Spectral",
  seed = 123
)

# Guardar modelo STM
saveRDS(stm_model, file.path(OUT_DIR, "stm_model_k6.rds"))

# Extraer términos principales por topic
stm_labels <- labelTopics(stm_model, n = 15)
stm_top_terms <- stm_labels$frex %>%
  as.data.frame() %>%
  rownames_to_column(var = "rank") %>%
  pivot_longer(-rank, names_to = "topic", values_to = "term") %>%
  mutate(
    topic = as.integer(str_remove(topic, "V")),
    rank = as.integer(rank)
  )

write_csv(stm_top_terms, file.path(OUT_DIR, "stm_top_terms.csv"))

# Visualización: Top términos STM
fig_stm_topics <- stm_top_terms %>%
  filter(rank <= 10) %>%
  mutate(
    topic_label = paste("Topic", topic),
    rank = factor(rank)
  ) %>%
  ggplot(aes(x = rank, y = term, fill = factor(topic))) +
  geom_tile(alpha = 0.7, color = "white", linewidth = 0.5) +
  facet_wrap(~ topic_label, scales = "free", ncol = 3) +
  scale_fill_grey(start = 0.2, end = 0.9, guide = "none") +
  labs(
    title = "Top 10 términos por topic (STM)",
    subtitle = sprintf("Modelo STM con K=%d topics, controlado por candidato y fecha", K_stm),
    x = "Ranking",
    y = "Término",
    caption = "Fuente: Elaboración propia. Modelo STM aplicado a posts de Reddit."
  ) +
  theme_thesis() +
  theme(
    strip.background = element_rect(fill = "grey95", color = NA),
    strip.text = element_text(margin = margin(5, 0, 5, 0)),
    axis.text.y = element_text(size = 8)
  )

save_fig(fig_stm_topics, "08_stm_top_terms.png", width_cm = 24, height_cm = 18)

cat(sprintf("   ✅ Modelo STM con K=%d topics completado\n", K_stm))

# =============================================================
# 7) Análisis de Emociones
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("😊 ANÁLISIS DE EMOCIONES\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Usar diccionario NRC para emociones (si está disponible)
# Alternativamente, usar análisis de sentimiento básico

# Análisis de sentimiento con tidytext (Bing lexicon)
sentiment_bing <- tokens_posts %>%
  inner_join(get_sentiments("bing"), by = "word") %>%
  count(post_id, sentiment) %>%
  pivot_wider(names_from = sentiment, values_from = n, values_fill = 0) %>%
  mutate(sentiment_score = positive - negative)

# Unir con datos de posts
df_posts_sentiment <- df_posts %>%
  left_join(sentiment_bing, by = "post_id") %>%
  mutate(
    sentiment_score = coalesce(sentiment_score, 0),
    positive = coalesce(positive, 0),
    negative = coalesce(negative, 0),
    sentiment_label = case_when(
      sentiment_score > 0 ~ "Positivo",
      sentiment_score < 0 ~ "Negativo",
      TRUE ~ "Neutral"
    )
  )

write_csv(df_posts_sentiment, file.path(OUT_DIR, "posts_con_sentimiento.csv"))

# 7.1) Distribución de sentimiento
fig_sentiment_dist <- df_posts_sentiment %>%
  count(sentiment_label) %>%
  mutate(
    pct = n / sum(n) * 100,
    sentiment_label = factor(sentiment_label, levels = c("Negativo", "Neutral", "Positivo"))
  ) %>%
  ggplot(aes(x = sentiment_label, y = n, fill = sentiment_label)) +
  geom_col(alpha = 0.8, color = "black", linewidth = 0.3, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%d\n(%.1f%%)", n, pct)), 
            vjust = -0.3, size = 4) +
  scale_fill_grey(start = 0.3, end = 0.8) +
  scale_y_continuous(labels = label_number(), expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Distribución de sentimiento en posts",
    subtitle = "Clasificación usando diccionario Bing",
    x = NULL,
    y = "Número de posts",
    caption = "Fuente: Elaboración propia. Análisis de sentimiento con tidytext."
  ) +
  theme_thesis()

save_fig(fig_sentiment_dist, "09_distribucion_sentimiento.png", width_cm = 16, height_cm = 12)

# 7.2) Sentimiento por candidato
sentiment_by_candidate <- df_posts_sentiment %>%
  filter(candidato_mencionado != "Otro") %>%
  count(candidato_mencionado, sentiment_label) %>%
  group_by(candidato_mencionado) %>%
  mutate(pct = n / sum(n) * 100) %>%
  ungroup()

fig_sentiment_candidate <- sentiment_by_candidate %>%
  mutate(sentiment_label = factor(sentiment_label, levels = c("Negativo", "Neutral", "Positivo"))) %>%
  ggplot(aes(x = candidato_mencionado, y = pct, fill = sentiment_label)) +
  geom_col(position = "stack", alpha = 0.8, color = "black", linewidth = 0.3) +
  scale_fill_grey(start = 0.2, end = 0.9, name = "Sentimiento") +
  scale_y_continuous(labels = label_number(suffix = "%"), expand = expansion(mult = c(0, 0.02))) +
  labs(
    title = "Distribución de sentimiento por candidato",
    subtitle = "Porcentaje de posts positivos, neutrales y negativos",
    x = NULL,
    y = "Porcentaje",
    caption = "Fuente: Elaboración propia."
  ) +
  theme_thesis(legend.pos = "right")

save_fig(fig_sentiment_candidate, "10_sentimiento_por_candidato.png", width_cm = 18, height_cm = 12)

# 7.3) Sentimiento por topic (LDA)
df_posts_with_topics <- df_posts_sentiment %>%
  mutate(post_id_char = as.character(post_id)) %>%
  left_join(
    top_topic_per_doc %>% mutate(document = as.character(document)),
    by = c("post_id_char" = "document")
  )

sentiment_by_topic <- df_posts_with_topics %>%
  filter(!is.na(topic)) %>%
  count(topic, sentiment_label) %>%
  group_by(topic) %>%
  mutate(pct = n / sum(n) * 100) %>%
  ungroup() %>%
  mutate(
    topic_label = paste("Topic", topic),
    sentiment_label = factor(sentiment_label, levels = c("Negativo", "Neutral", "Positivo"))
  )

fig_sentiment_topic <- sentiment_by_topic %>%
  ggplot(aes(x = factor(topic), y = pct, fill = sentiment_label)) +
  geom_col(position = "stack", alpha = 0.8, color = "black", linewidth = 0.3) +
  scale_fill_grey(start = 0.2, end = 0.9, name = "Sentimiento") +
  scale_y_continuous(labels = label_number(suffix = "%"), expand = expansion(mult = c(0, 0.02))) +
  labs(
    title = "Distribución de sentimiento por topic (LDA)",
    subtitle = "Porcentaje de posts por sentimiento en cada topic",
    x = "Topic",
    y = "Porcentaje",
    caption = "Fuente: Elaboración propia. Análisis combinado LDA + sentimiento."
  ) +
  theme_thesis(legend.pos = "right")

save_fig(fig_sentiment_topic, "11_sentimiento_por_topic.png", width_cm = 20, height_cm = 12)

# 7.4) Palabras emocionales más frecuentes
emotion_words <- tokens_posts %>%
  inner_join(get_sentiments("bing"), by = "word") %>%
  count(word, sentiment, sort = TRUE) %>%
  group_by(sentiment) %>%
  slice_head(n = 15) %>%
  ungroup()

fig_emotion_words <- emotion_words %>%
  mutate(word = reorder(word, n)) %>%
  ggplot(aes(x = n, y = word, fill = sentiment)) +
  geom_col(alpha = 0.8, color = "black", linewidth = 0.2) +
  facet_wrap(~ sentiment, scales = "free_y") +
  scale_fill_grey(start = 0.3, end = 0.8, guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Top 15 palabras emocionales más frecuentes",
    subtitle = "Palabras positivas y negativas en posts",
    x = "Frecuencia",
    y = NULL,
    caption = "Fuente: Elaboración propia. Diccionario Bing."
  ) +
  theme_thesis() +
  theme(
    strip.background = element_rect(fill = "grey95", color = NA),
    strip.text = element_text(margin = margin(5, 0, 5, 0))
  )

save_fig(fig_emotion_words, "12_palabras_emocionales.png", width_cm = 18, height_cm = 14)

# =============================================================
# 8) Análisis Temporal de Topics y Emociones
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📅 ANÁLISIS TEMPORAL\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# 8.1) Evolución de topics en el tiempo
topic_temporal <- df_posts_with_topics %>%
  filter(!is.na(topic), !is.na(fecha)) %>%
  count(fecha, topic) %>%
  group_by(fecha) %>%
  mutate(pct = n / sum(n) * 100) %>%
  ungroup() %>%
  mutate(topic_label = paste("Topic", topic))

fig_topic_temporal <- topic_temporal %>%
  ggplot(aes(x = fecha, y = pct, fill = factor(topic))) +
  geom_area(position = "stack", alpha = 0.7, color = "black", linewidth = 0.2) +
  scale_fill_grey(start = 0.2, end = 0.9, name = "Topic") +
  scale_x_date(date_breaks = "2 weeks", date_labels = "%d %b", expand = expansion(mult = 0.02)) +
  scale_y_continuous(labels = label_number(suffix = "%"), expand = expansion(mult = c(0, 0.02))) +
  labs(
    title = "Evolución temporal de topics",
    subtitle = "Distribución de topics a lo largo del tiempo (área apilada)",
    x = "Fecha",
    y = "Porcentaje",
    caption = "Fuente: Elaboración propia."
  ) +
  theme_thesis(legend.pos = "right")

save_fig(fig_topic_temporal, "13_evolucion_temporal_topics.png", width_cm = 22, height_cm = 14)

# 8.2) Evolución de sentimiento en el tiempo
sentiment_temporal <- df_posts_sentiment %>%
  filter(!is.na(fecha)) %>%
  count(fecha, sentiment_label) %>%
  group_by(fecha) %>%
  mutate(pct = n / sum(n) * 100) %>%
  ungroup() %>%
  mutate(sentiment_label = factor(sentiment_label, levels = c("Negativo", "Neutral", "Positivo")))

fig_sentiment_temporal <- sentiment_temporal %>%
  ggplot(aes(x = fecha, y = pct, fill = sentiment_label)) +
  geom_area(position = "stack", alpha = 0.7, color = "black", linewidth = 0.2) +
  scale_fill_grey(start = 0.2, end = 0.9, name = "Sentimiento") +
  scale_x_date(date_breaks = "2 weeks", date_labels = "%d %b", expand = expansion(mult = 0.02)) +
  scale_y_continuous(labels = label_number(suffix = "%"), expand = expansion(mult = c(0, 0.02))) +
  labs(
    title = "Evolución temporal de sentimiento",
    subtitle = "Distribución de sentimiento a lo largo del tiempo",
    x = "Fecha",
    y = "Porcentaje",
    caption = "Fuente: Elaboración propia."
  ) +
  theme_thesis(legend.pos = "right")

save_fig(fig_sentiment_temporal, "14_evolucion_temporal_sentimiento.png", width_cm = 22, height_cm = 14)

# =============================================================
# 9) Análisis de Correlaciones y Co-ocurrencias
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("🔗 ANÁLISIS DE CO-OCURRENCIAS\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# 9.1) Co-ocurrencia de palabras (bigramas)
bigrams <- df_posts %>%
  unnest_tokens(bigram, texto_post, token = "ngrams", n = 2) %>%
  separate(bigram, c("word1", "word2"), sep = " ") %>%
  filter(
    !word1 %in% stop_words$word,
    !word2 %in% stop_words$word,
    str_length(word1) > 2,
    str_length(word2) > 2
  ) %>%
  count(word1, word2, sort = TRUE) %>%
  filter(n >= 5)

write_csv(bigrams, file.path(OUT_DIR, "bigramas_coocurrencia.csv"))

# Visualización de bigramas más frecuentes
fig_bigrams <- bigrams %>%
  slice_head(n = 20) %>%
  mutate(bigram = paste(word1, word2)) %>%
  mutate(bigram = fct_reorder(bigram, n)) %>%
  ggplot(aes(x = n, y = bigram)) +
  geom_col(fill = "grey50", alpha = 0.8, color = "black", linewidth = 0.3) +
  scale_x_continuous(labels = label_number(), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Top 20 bigramas más frecuentes",
    subtitle = "Pares de palabras que aparecen juntas",
    x = "Frecuencia",
    y = NULL,
    caption = "Fuente: Elaboración propia."
  ) +
  theme_thesis()

save_fig(fig_bigrams, "15_bigramas_coocurrencia.png", width_cm = 18, height_cm = 14)

# =============================================================
# 10) Resumen y Estadísticas Finales
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📊 RESUMEN FINAL\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

resumen_analisis <- list(
  total_posts = nrow(df_posts),
  total_palabras_unicas = n_distinct(tokens_posts$word),
  promedio_palabras_por_post = mean(df_posts$n_palabras),
  mediana_palabras_por_post = median(df_posts$n_palabras),
  topics_lda = K_selected,
  topics_stm = K_stm,
  posts_positivos = sum(df_posts_sentiment$sentiment_label == "Positivo", na.rm = TRUE),
  posts_negativos = sum(df_posts_sentiment$sentiment_label == "Negativo", na.rm = TRUE),
  posts_neutrales = sum(df_posts_sentiment$sentiment_label == "Neutral", na.rm = TRUE)
)

cat("\nEstadísticas del análisis:\n")
print(resumen_analisis)

# Guardar resumen
write_lines(
  paste(names(resumen_analisis), resumen_analisis, sep = ": "),
  file.path(OUT_DIR, "resumen_analisis.txt")
)

cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("✅ ANÁLISIS TEXTUAL COMPLETADO\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat(sprintf("\n📁 Resultados guardados en: %s\n", OUT_DIR))
cat(sprintf("📊 Figuras guardadas en: %s\n", FIG_DIR))
cat(sprintf("📈 Total de figuras generadas: %d\n", length(list.files(FIG_DIR, pattern = "\\.png$"))))
cat("\n")

