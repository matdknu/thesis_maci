# =============================================================
# Análisis de Texto con Machine Learning
# Word Embeddings, Clasificación (SVM, Random Forest, etc.)
# =============================================================

rm(list = ls())
set.seed(123)

# Setup
pacman::p_load(
  tidyverse, here, readr, tidymodels, textrecipes, 
  word2vec, tidytext, stopwords,
  yardstick, discrim, LiblineaR, ranger,
  ggplot2, caret, e1071
)

# Configuración
OUT_DIR <- here("data", "processed", "analisis_discurso")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# =============================================================
# 1) Cargar datos de análisis de discurso
# =============================================================
cat("=== Cargando datos ===\n")

# Intentar cargar desde test_analisis_discurso primero
test_file <- file.path(OUT_DIR, "test_analisis_discurso.rds")
if (file.exists(test_file)) {
  df <- readRDS(test_file)
  cat("✓ Datos cargados desde test_analisis_discurso.rds\n")
} else {
  # Fallback: cargar desde análisis completo
  completo_file <- file.path(OUT_DIR, "analisis_discurso_completo.rds")
  if (file.exists(completo_file)) {
    df <- readRDS(completo_file)
    cat("✓ Datos cargados desde analisis_discurso_completo.rds\n")
  } else {
    stop("No se encontraron datos de análisis de discurso. Ejecuta primero test_analisis_discurso.R")
  }
}

# Preparar datos para ML
df_ml <- df %>%
  filter(
    procesado == TRUE,
    error == FALSE,
    !is.na(us_vs_them_marker),
    !is.na(texto_completo),
    nchar(texto_completo) > 10
  ) %>%
  mutate(
    # Variable objetivo: us_vs_them_marker (0 o 1)
    target = factor(us_vs_them_marker, levels = c(0, 1), labels = c("No_Polarizado", "Polarizado")),
    # Texto limpio
    text = str_squish(texto_completo),
    text = str_remove_all(text, "<>"),  # Remover separador para embeddings
    text = str_trim(text)
  ) %>%
  filter(nchar(text) > 20) %>%
  select(texto_id, text, target, from_bloc, to_target, discursive_act, 
         frame, emotion, intensity, target_sentiment, us_vs_them_marker)

cat("Total observaciones:", nrow(df_ml), "\n")
cat("Distribución de target:\n")
print(table(df_ml$target))

# =============================================================
# 2) Crear Word Embeddings y representaciones a nivel de documento
# =============================================================
cat("\n=== Creando Word Embeddings ===\n")

# Tokenizar textos
textos_tokenizados <- df_ml %>%
  select(texto_id, text) %>%
  unnest_tokens(word, text, token = "words", to_lower = TRUE) %>%
  anti_join(stop_words, by = "word") %>%
  filter(str_length(word) > 2) %>%
  group_by(texto_id) %>%
  summarise(text_clean = paste(word, collapse = " "), .groups = "drop")

# Guardar textos tokenizados para word2vec
textos_para_w2v <- textos_tokenizados$text_clean
writeLines(textos_para_w2v, file.path(OUT_DIR, "textos_tokenizados.txt"))

# Entrenar modelo Word2Vec
cat("Entrenando modelo Word2Vec...\n")
w2v_model <- word2vec(
  x = file.path(OUT_DIR, "textos_tokenizados.txt"),
  type = "skip-gram",
  dim = 100,
  window = 5,
  iter = 20,
  threads = 4,
  min_count = 2
)

# Guardar modelo
write.word2vec(w2v_model, file.path(OUT_DIR, "word2vec_model.bin"))
cat("✓ Modelo Word2Vec guardado\n")

# Función para obtener embedding de una palabra usando predict
get_word_embedding <- function(word, model) {
  tryCatch({
    # Usar predict para obtener embedding
    emb <- predict(model, word, type = "embedding")
    if (!is.null(emb) && length(emb) > 0) {
      return(as.numeric(emb))
    } else {
      return(NULL)
    }
  }, error = function(e) {
    return(NULL)
  })
}

# Función para crear representación de documento (promedio de embeddings)
# Equivalente a Doc2VecTransformer en Python
create_doc_embedding <- function(text, model, aggregation_func = "mean") {
  words <- str_split(text, "\\s+")[[1]]
  words <- words[words != ""]
  
  embeddings <- list()
  for (word in words) {
    emb <- get_word_embedding(word, model)
    if (!is.null(emb)) {
      embeddings[[length(embeddings) + 1]] <- emb
    }
  }
  
  if (length(embeddings) == 0) {
    # Retornar vector de ceros si no hay embeddings
    # Obtener dimensión del modelo (por defecto 100)
    return(rep(0, 100))
  }
  
  # Agregar embeddings según función especificada
  embeddings_matrix <- do.call(rbind, embeddings)
  
  if (aggregation_func == "mean") {
    return(colMeans(embeddings_matrix))
  } else if (aggregation_func == "max") {
    return(apply(embeddings_matrix, 2, max))
  } else if (aggregation_func == "sum") {
    return(colSums(embeddings_matrix))
  } else {
    return(colMeans(embeddings_matrix))  # default: mean
  }
}

# Crear embeddings para todos los documentos
cat("Creando representaciones de documentos...\n")
doc_embeddings_list <- map(1:nrow(textos_tokenizados), function(i) {
  texto <- textos_tokenizados$text_clean[i]
  emb <- create_doc_embedding(texto, w2v_model, aggregation_func = "mean")
  # Asegurar que no haya NAs o Inf
  emb[is.na(emb)] <- 0
  emb[is.infinite(emb)] <- 0
  # Normalizar para evitar valores extremos
  if (any(emb != 0)) {
    emb <- emb / (max(abs(emb)) + 1e-10)
  }
  return(emb)
})

# Convertir a dataframe
doc_embeddings <- map_dfr(1:length(doc_embeddings_list), function(i) {
  emb <- doc_embeddings_list[[i]]
  emb_df <- as.data.frame(t(emb))
  names(emb_df) <- paste0("V", 1:ncol(emb_df))
  tibble(
    texto_id = textos_tokenizados$texto_id[i],
    emb_df
  )
})

# Verificar variabilidad
cat("Rango de valores en embeddings:\n")
cat("  Min:", min(as.matrix(doc_embeddings %>% select(starts_with("V"))), na.rm = TRUE), "\n")
cat("  Max:", max(as.matrix(doc_embeddings %>% select(starts_with("V"))), na.rm = TRUE), "\n")
cat("  Media:", mean(as.matrix(doc_embeddings %>% select(starts_with("V"))), na.rm = TRUE), "\n")

# Combinar con datos originales
df_ml_embeddings <- df_ml %>%
  inner_join(doc_embeddings, by = "texto_id") %>%
  select(-texto_id)

# Verificar que no haya NAs en los embeddings
embedding_cols <- names(df_ml_embeddings)[grepl("^V\\d+$", names(df_ml_embeddings))]
for (col in embedding_cols) {
  df_ml_embeddings[[col]][is.na(df_ml_embeddings[[col]])] <- 0
  df_ml_embeddings[[col]][is.infinite(df_ml_embeddings[[col]])] <- 0
}

cat("✓ Representaciones de documentos creadas (dimensiones:", length(embedding_cols), ")\n")

# =============================================================
# 3) División train/test
# =============================================================
cat("\n=== División train/test ===\n")

split <- initial_split(df_ml_embeddings, prop = 0.8, strata = target)
train_data <- training(split)
test_data <- testing(split)

cat("Train:", nrow(train_data), "observaciones\n")
cat("Test:", nrow(test_data), "observaciones\n")
cat("Distribución en train:\n")
print(table(train_data$target))
cat("Distribución en test:\n")
print(table(test_data$target))

# =============================================================
# 4) EXPERIMENTO 1: SVM con Word Embeddings
# =============================================================
cat("\n=== EXPERIMENTO 1: SVM con Word Embeddings ===\n")

# Preparar datos (solo embeddings y target)
train_X_df <- train_data %>%
  select(starts_with("V"))

# Filtrar columnas constantes (varianza cero) - usar umbral más bajo
variances <- apply(train_X_df, 2, var, na.rm = TRUE)
non_constant_cols <- names(variances)[variances > 1e-15]

# Si todas las columnas son constantes, usar todas (puede ser problema de escala)
if (length(non_constant_cols) == 0) {
  cat("Advertencia: Todas las columnas tienen varianza muy baja. Usando todas las columnas.\n")
  non_constant_cols <- names(train_X_df)
}

cat("Columnas con varianza > 0:", length(non_constant_cols), "de", ncol(train_X_df), "\n")

train_X <- train_X_df %>%
  select(all_of(non_constant_cols)) %>%
  as.matrix()

# Verificar y limpiar NAs
train_X[is.na(train_X)] <- 0
if (any(is.infinite(train_X))) {
  train_X[is.infinite(train_X)] <- 0
}

train_y <- train_data$target

test_X <- test_data %>%
  select(all_of(non_constant_cols)) %>%
  as.matrix()

# Verificar y limpiar NAs
test_X[is.na(test_X)] <- 0
if (any(is.infinite(test_X))) {
  test_X[is.infinite(test_X)] <- 0
}

test_y <- test_data$target

# Entrenar SVM
cat("Entrenando SVM...\n")
svm_model_1 <- svm(
  x = train_X,
  y = train_y,
  type = "C-classification",
  kernel = "linear",
  cost = 1,
  scale = TRUE
)

# Predicciones
svm_pred_1 <- predict(svm_model_1, test_X)

# Métricas (usar solo funciones de yardstick)
svm_results_1 <- test_data %>%
  mutate(.pred_class = svm_pred_1) %>%
  summarise(
    accuracy = accuracy_vec(truth = target, estimate = .pred_class),
    precision = tryCatch(precision_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_),
    recall = tryCatch(recall_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_),
    f_meas = tryCatch(f_meas_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_)
  ) %>%
  pivot_longer(everything(), names_to = ".metric", values_to = ".estimate")

cat("\n--- Resultados Experimento 1 (SVM Linear) ---\n")
print(svm_results_1)

# Matriz de confusión
svm_cm_1 <- confusionMatrix(svm_pred_1, test_y)
cat("\nMatriz de Confusión:\n")
print(svm_cm_1$table)
cat("\nReporte de Clasificación:\n")
print(svm_cm_1)

# =============================================================
# 5) EXPERIMENTO 2: SVM con kernel RBF (variando hiperparámetros)
# =============================================================
cat("\n=== EXPERIMENTO 2: SVM con kernel RBF ===\n")

# Entrenar SVM con RBF
cat("Entrenando SVM con kernel RBF...\n")
svm_model_2 <- svm(
  x = train_X,
  y = train_y,
  type = "C-classification",
  kernel = "radial",
  cost = 10,
  gamma = 0.01,
  scale = TRUE
)

# Predicciones
svm_pred_2 <- predict(svm_model_2, test_X)

# Métricas
svm_results_2 <- test_data %>%
  mutate(.pred_class = svm_pred_2) %>%
  summarise(
    accuracy = accuracy_vec(truth = target, estimate = .pred_class),
    precision = tryCatch(precision_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_),
    recall = tryCatch(recall_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_),
    f_meas = tryCatch(f_meas_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_)
  ) %>%
  pivot_longer(everything(), names_to = ".metric", values_to = ".estimate")

cat("\n--- Resultados Experimento 2 (SVM RBF) ---\n")
print(svm_results_2)

# Matriz de confusión
svm_cm_2 <- confusionMatrix(svm_pred_2, test_y)
cat("\nMatriz de Confusión:\n")
print(svm_cm_2$table)
cat("\nReporte de Clasificación:\n")
print(svm_cm_2)

# =============================================================
# 6) EXPERIMENTO 3: Random Forest con Word Embeddings
# =============================================================
cat("\n=== EXPERIMENTO 3: Random Forest ===\n")

# Preparar datos para tidymodels (usar solo columnas no constantes)
train_df <- train_data %>%
  select(all_of(non_constant_cols), target)

test_df <- test_data %>%
  select(all_of(non_constant_cols), target)

# Receta
rf_recipe <- recipe(target ~ ., data = train_df)

# Modelo
rf_spec <- rand_forest(
  trees = 500,
  mtry = tune(),
  min_n = tune()
) %>%
  set_engine("ranger") %>%
  set_mode("classification")

# Workflow
rf_workflow <- workflow() %>%
  add_recipe(rf_recipe) %>%
  add_model(rf_spec)

# Validación cruzada (sin estratificación si hay muy pocos casos de una clase)
if (min(table(train_df$target)) >= 2) {
  folds <- vfold_cv(train_df, v = min(5, floor(nrow(train_df) / 3)), strata = target)
} else {
  folds <- vfold_cv(train_df, v = min(5, floor(nrow(train_df) / 3)))
  cat("Advertencia: Muy pocos casos de una clase. CV sin estratificación.\n")
}

# Grid de hiperparámetros
rf_grid <- grid_regular(
  mtry(range = c(10, min(50, ncol(train_df) - 1))),
  min_n(range = c(2, 10)),
  levels = 4
)

# Tuning
cat("Haciendo tuning de hiperparámetros...\n")
rf_tuned <- tune_grid(
  rf_workflow,
  resamples = folds,
  grid = rf_grid,
  metrics = metric_set(accuracy, roc_auc)
)

# Mejor modelo
best_rf <- select_best(rf_tuned, metric = "accuracy")
cat("Mejores hiperparámetros:", paste(names(best_rf), best_rf, collapse = ", "), "\n")

# Entrenar modelo final
rf_final <- finalize_workflow(rf_workflow, best_rf) %>%
  fit(train_df)

# Predicciones
rf_pred <- predict(rf_final, test_df) %>%
  bind_cols(test_df %>% select(target))

# Métricas
rf_results <- rf_pred %>%
  summarise(
    accuracy = accuracy_vec(truth = target, estimate = .pred_class),
    precision = tryCatch(precision_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_),
    recall = tryCatch(recall_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_),
    f_meas = tryCatch(f_meas_vec(truth = target, estimate = .pred_class), error = function(e) NA_real_)
  ) %>%
  pivot_longer(everything(), names_to = ".metric", values_to = ".estimate")

cat("\n--- Resultados Experimento 3 (Random Forest) ---\n")
print(rf_results)

# Matriz de confusión
rf_cm <- confusionMatrix(rf_pred$.pred_class, test_df$target)
cat("\nMatriz de Confusión:\n")
print(rf_cm$table)
cat("\nReporte de Clasificación:\n")
print(rf_cm)

# =============================================================
# 7) Comparación de Experimentos
# =============================================================
cat("\n=== COMPARACIÓN DE EXPERIMENTOS ===\n")

comparison <- bind_rows(
  svm_results_1 %>% mutate(experimento = "SVM Linear"),
  svm_results_2 %>% mutate(experimento = "SVM RBF"),
  rf_results %>% mutate(experimento = "Random Forest")
) %>%
  pivot_wider(names_from = .metric, values_from = .estimate)

cat("\nTabla Comparativa:\n")
print(comparison)

# Visualización
comparison_long <- comparison %>%
  pivot_longer(cols = -experimento, names_to = "metric", values_to = "value")

p_comparison <- ggplot(comparison_long, aes(x = experimento, y = value, fill = experimento)) +
  geom_col(position = "dodge") +
  facet_wrap(~ metric, scales = "free_y") +
  labs(
    title = "Comparación de Modelos de Clasificación",
    x = "Experimento",
    y = "Valor",
    fill = "Modelo"
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(OUT_DIR, "comparacion_modelos.png"), p_comparison, width = 12, height = 8)

# =============================================================
# 8) Análisis de Resultados
# =============================================================
cat("\n=== ANÁLISIS DE RESULTADOS ===\n")

cat("\n1. ¿Por qué estos resultados?\n")
cat("   - Los Word Embeddings capturan relaciones semánticas entre palabras\n")
cat("   - La agregación (promedio) de embeddings a nivel de documento preserva información semántica\n")
cat("   - SVM es efectivo para datos de alta dimensionalidad\n")
cat("   - Random Forest puede capturar interacciones no lineales\n\n")

cat("2. ¿Hubo variación considerable entre experimentos?\n")
best_accuracy <- max(comparison$accuracy, na.rm = TRUE)
worst_accuracy <- min(comparison$accuracy, na.rm = TRUE)
diff_accuracy <- best_accuracy - worst_accuracy
cat("   - Diferencia en accuracy:", round(diff_accuracy, 4), "\n")
if (diff_accuracy > 0.05) {
  cat("   - SÍ hay variación considerable (>5%)\n")
} else {
  cat("   - NO hay variación considerable (<5%)\n")
}

cat("\n3. Justificación:\n")
cat("   - El modelo con mejor rendimiento es:", comparison$experimento[which.max(comparison$accuracy)], "\n")
cat("   - Esto puede deberse a:\n")
cat("     * Capacidad del modelo para capturar patrones complejos\n")
cat("     * Ajuste de hiperparámetros\n")
cat("     * Características del dataset (tamaño, balance de clases)\n")

# Guardar resultados
write_csv(comparison, file.path(OUT_DIR, "resultados_clasificacion.csv"))
write_rds(list(
  svm_model_1 = svm_model_1,
  svm_model_2 = svm_model_2,
  rf_final = rf_final,
  w2v_model = w2v_model,
  comparison = comparison
), file.path(OUT_DIR, "modelos_ml.rds"))

cat("\n✓ Análisis completado. Resultados guardados en:", OUT_DIR, "\n")

