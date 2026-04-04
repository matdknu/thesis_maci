# =============================================================
# 05) Topic Modeling
# LDA, STM, and other topic modeling approaches
# Reads from: data/processed/
# =============================================================

rm(list = ls())
set.seed(123)

# Setup
pacman::p_load(
  tidyverse, tidytext, tm, SnowballC, 
  topicmodels, stm, textmineR,
  here, readr
)

# Paths
OUT_DIR <- here("outputs", "modelos")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# Load processed data
df <- readRDS(here("data/processed/reddit_filtrado.rds"))

# =============================================================
# 1) Text Preparation
# =============================================================
cat("\n=== PREPARING TEXT FOR TOPIC MODELING ===\n")

# Prepare text corpus
df_texto <- df %>%
  mutate(
    texto_completo = paste(
      coalesce(post_title, ""),
      coalesce(post_selftext, ""),
      coalesce(comment_body, ""),
      sep = " "
    ) %>%
      str_trim() %>%
      str_squish(),
    texto_id = row_number(),
    n_palabras = str_count(texto_completo, "\\S+"),
    n_caracteres = nchar(texto_completo)
  ) %>%
  filter(
    !is.na(texto_completo),
    texto_completo != "",
    texto_completo != " ",
    n_caracteres >= 20,
    n_palabras >= 3
  )

cat("Total texts prepared:", nrow(df_texto), "\n")

# =============================================================
# 2) LDA Topic Modeling
# =============================================================
cat("\n=== LDA TOPIC MODELING ===\n")

# Tokenize and create document-term matrix
tokens <- df_texto %>%
  unnest_tokens(word, texto_completo) %>%
  anti_join(stop_words, by = "word") %>%
  filter(str_length(word) > 2) %>%
  count(texto_id, word, sort = TRUE)

# Create DTM
dtm <- tokens %>%
  cast_dtm(texto_id, word, n)

# Fit LDA model (example with 6 topics)
# Adjust K based on your analysis
lda_model <- LDA(dtm, k = 6, control = list(seed = 123))

# Extract topics
lda_topics <- tidy(lda_model, matrix = "beta")
lda_documents <- tidy(lda_model, matrix = "gamma")

# Save results
write_csv(lda_topics, here(OUT_DIR, "lda_topics.csv"))
write_csv(lda_documents, here(OUT_DIR, "lda_documents.csv"))

cat("LDA model completed. Results saved.\n")

# =============================================================
# 3) STM (Structural Topic Model)
# =============================================================
cat("\n=== STM TOPIC MODELING ===\n")

# Prepare for STM
processed <- textProcessor(
  documents = df_texto$texto_completo,
  metadata = df_texto %>% select(texto_id, fecha, kast, kaiser, matthei, jara, parisi),
  lowercase = TRUE,
  removestopwords = TRUE,
  removenumbers = TRUE,
  removepunctuation = TRUE,
  stem = TRUE
)

# Prepare documents
prep <- prepDocuments(
  processed$documents,
  processed$vocab,
  processed$meta
)

# Fit STM model (example with 6 topics)
# Adjust K and covariates based on your research questions
stm_model <- stm(
  documents = prep$documents,
  vocab = prep$vocab,
  K = 6,
  data = prep$meta,
  max.em.its = 75,
  init.type = "Spectral"
)

# Extract topics and effects
stm_topics <- labelTopics(stm_model, n = 10)
stm_effects <- estimateEffect(
  1:6 ~ fecha + kast + kaiser + matthei,
  stm_model,
  metadata = prep$meta
)

# Save results
saveRDS(stm_model, here(OUT_DIR, "stm_model.rds"))
saveRDS(stm_effects, here(OUT_DIR, "stm_effects.rds"))

cat("STM model completed. Results saved.\n")

# =============================================================
# 4) Topic Interpretation
# =============================================================
cat("\n=== TOPIC INTERPRETATION ===\n")

# Top terms per topic (LDA)
lda_top_terms <- lda_topics %>%
  group_by(topic) %>%
  slice_max(beta, n = 10) %>%
  ungroup() %>%
  arrange(topic, -beta)

print(lda_top_terms)

# Save top terms
write_csv(lda_top_terms, here(OUT_DIR, "lda_top_terms.csv"))

cat("\nTopic modeling completed.\n")
cat("Results saved to:", OUT_DIR, "\n")



















