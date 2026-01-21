# =============================================================
# 07) Machine Learning - Análisis de Ideología
# =============================================================
# Aplica técnicas de ML: SVM, Clustering, Random Forest, etc.
# sobre los datos de imputación de ideología
# Lee de: data/processed/imputacion_ideologia/[fecha_ejecucion]/
# Guarda en: outputs/ml_ideologia/
# =============================================================

# rm(list = ls())  # Comentado para no perder objetos
set.seed(123)

# Setup
pacman::p_load(
  tidyverse, lubridate, here, readr, scales, 
  ggtext, patchwork, RColorBrewer, viridis,
  e1071,        # SVM
  randomForest, # Random Forest
  cluster,      # Clustering (kmeans, pam, etc.)
  factoextra,   # Visualización de clustering
  caret,        # Machine learning utilities
  corrplot,     # Correlaciones
  Rtsne         # t-SNE para reducción de dimensionalidad
)

# =============================================================
# CONFIGURACIÓN
# =============================================================
BASE_DIR <- here("data", "processed", "imputacion_ideologia")
OUT_DIR <- here("outputs", "ml_ideologia")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# Encontrar el directorio más reciente
if (dir.exists(BASE_DIR)) {
  dirs <- list.dirs(BASE_DIR, full.names = TRUE, recursive = FALSE)
  if (length(dirs) > 0) {
    dirs_info <- file.info(dirs)
    dir_mas_reciente <- rownames(dirs_info)[which.max(dirs_info$mtime)]
    DATA_DIR <- dir_mas_reciente
    cat(sprintf("\n📂 Usando datos de: %s\n", basename(DATA_DIR)))
  } else {
    stop("No se encontraron directorios de imputación")
  }
} else {
  stop("No existe el directorio base de imputación")
}

# Tema para visualizaciones
theme_ml <- function(base_size = 12, legend.pos = "bottom") {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = base_size + 2),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40", size = base_size),
      plot.caption = element_text(hjust = 0, color = "grey50", size = base_size - 2),
      legend.position = legend.pos,
      legend.title = element_blank(),
      panel.grid.minor = element_blank()
    )
}

save_fig <- function(plot, filename, width_cm = 20, height_cm = 15, dpi = 300) {
  ggsave(file.path(OUT_DIR, filename), plot, 
         width = width_cm, height = height_cm, units = "cm", dpi = dpi)
  cat(sprintf("   💾 Guardado: %s\n", filename))
}

# =============================================================
# 1) CARGA Y PREPARACIÓN DE DATOS
# =============================================================
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("🤖 MACHINE LEARNING - ANÁLISIS DE IDEOLOGÍA\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Cargar datos
rds_file <- file.path(DATA_DIR, "resultados_completos.rds")
csv_files <- list.files(DATA_DIR, pattern = "imputacion.*\\.csv$", full.names = TRUE)

if (file.exists(rds_file)) {
  cat(sprintf("\n📂 Cargando desde RDS: %s\n", basename(rds_file)))
  datos_completos <- readRDS(rds_file)
  df <- datos_completos$df_resultados
} else if (length(csv_files) > 0) {
  csv_resultados <- csv_files[1]
  cat(sprintf("\n📂 Cargando desde CSV: %s\n", basename(csv_resultados)))
  df <- read_csv(csv_resultados, show_col_types = FALSE)
} else {
  stop("No se encontró archivo de resultados")
}

cat(sprintf("   ✅ Datos cargados: %d filas\n", nrow(df)))

# Preparar datos para ML
df_ml <- df %>%
  filter(
    !is.na(left_right_score),
    !is.na(confidence),
    !is.na(left_right_label)
  ) %>%
  mutate(
    # Variables numéricas
    left_right_score = as.numeric(left_right_score),
    confidence = as.numeric(confidence),
    
    # Variables categóricas codificadas
    rhetorical_mode_num = as.numeric(factor(rhetorical_mode)),
    main_target_num = as.numeric(factor(main_target)),
    stance_num = as.numeric(factor(stance_toward_target)),
    
    # Label como factor para clasificación
    label_factor = factor(left_right_label),
    
    # Binarizar label (Left vs Right)
    label_binary = factor(ifelse(left_right_score < 0, "Left", 
                                 ifelse(left_right_score > 0, "Right", "Center"))),
    
    # Longitud del comentario (si existe)
    comment_length = if("comment_body" %in% names(.)) nchar(comment_body) else NA_real_
  )

cat(sprintf("   ✅ Datos preparados para ML: %d filas\n", nrow(df_ml)))

# =============================================================
# 2) ANÁLISIS DE CORRELACIONES
# =============================================================
cat("\n📊 Analizando correlaciones...\n")

# Seleccionar variables numéricas
vars_numericas <- df_ml %>%
  select(where(is.numeric)) %>%
  select(-contains("id"), -contains("token")) %>%
  na.omit()

if (ncol(vars_numericas) > 1) {
  cor_matrix <- cor(vars_numericas)
  
  # Guardar matriz de correlación
  write_csv(as_tibble(cor_matrix, rownames = "variable"), 
            file.path(OUT_DIR, "matriz_correlacion.csv"))
  
  # Visualizar correlaciones
  png(file.path(OUT_DIR, "01_matriz_correlacion.png"), 
      width = 20, height = 20, units = "cm", res = 300)
  corrplot(cor_matrix, method = "color", type = "upper", 
           order = "hclust", tl.cex = 0.8, tl.col = "black")
  dev.off()
  cat("   💾 Guardado: 01_matriz_correlacion.png\n")
}

# =============================================================
# 3) CLUSTERING - K-MEANS
# =============================================================
cat("\n🔍 Aplicando K-Means Clustering...\n")

# Preparar datos para clustering (solo variables numéricas relevantes)
df_cluster <- df_ml %>%
  select(left_right_score, confidence, rhetorical_mode_num, 
         main_target_num, stance_num, comment_length) %>%
  na.omit() %>%
  scale()  # Normalizar

if (nrow(df_cluster) > 10) {
  # Determinar número óptimo de clusters (método del codo)
  wss <- function(k) {
    kmeans(df_cluster, k, nstart = 10, iter.max = 100)$tot.withinss
  }
  
  k_values <- 2:min(10, nrow(df_cluster) - 1)
  wss_values <- map_dbl(k_values, wss)
  
  # Gráfico del codo
  fig_elbow <- tibble(k = k_values, wss = wss_values) %>%
    ggplot(aes(x = k, y = wss)) +
    geom_line(color = "steelblue", linewidth = 1.2) +
    geom_point(color = "steelblue", size = 3) +
    labs(
      title = "Método del Codo para K-Means",
      subtitle = "Determinación del número óptimo de clusters",
      x = "Número de Clusters (k)",
      y = "Within Sum of Squares (WSS)"
    ) +
    theme_ml()
  
  print(fig_elbow)
  save_fig(fig_elbow, "02_elbow_method.png")
  
  # Aplicar K-Means con k=3, 4, 5
  for (k in c(3, 4, 5)) {
    if (k <= nrow(df_cluster)) {
      kmeans_result <- kmeans(df_cluster, centers = k, nstart = 25, iter.max = 100)
      
      # Agregar clusters al dataframe original
      df_ml_clustered <- df_ml %>%
        filter(!is.na(left_right_score), !is.na(confidence)) %>%
        na.omit() %>%
        mutate(cluster_kmeans = as.factor(kmeans_result$cluster))
      
      # Visualizar clusters (usando las dos primeras dimensiones principales)
      if (ncol(df_cluster) >= 2) {
        pca <- prcomp(df_cluster, scale. = FALSE)
        df_pca <- as_tibble(pca$x[, 1:2]) %>%
          mutate(cluster = as.factor(kmeans_result$cluster),
                 label = df_ml_clustered$left_right_label)
        
        fig_cluster <- df_pca %>%
          ggplot(aes(x = PC1, y = PC2, color = cluster, shape = label)) +
          geom_point(alpha = 0.6, size = 2) +
          scale_color_viridis_d(option = "plasma") +
          labs(
            title = sprintf("K-Means Clustering (k=%d)", k),
            subtitle = "Visualización en espacio PCA (2D)",
            x = "Primera Componente Principal",
            y = "Segunda Componente Principal"
          ) +
          theme_ml()
        
        print(fig_cluster)
        save_fig(fig_cluster, sprintf("03_kmeans_k%d.png", k))
        
        # Análisis de clusters
        cluster_analysis <- df_ml_clustered %>%
          group_by(cluster_kmeans) %>%
          summarise(
            n = n(),
            score_medio = mean(left_right_score, na.rm = TRUE),
            confidence_medio = mean(confidence, na.rm = TRUE),
            .groups = "drop"
          )
        
        write_csv(cluster_analysis, 
                  file.path(OUT_DIR, sprintf("03_kmeans_k%d_analysis.csv", k)))
      }
    }
  }
}

# =============================================================
# 4) CLUSTERING JERÁRQUICO
# =============================================================
cat("\n🌳 Aplicando Clustering Jerárquico...\n")

if (nrow(df_cluster) > 2 && nrow(df_cluster) <= 1000) {
  # Calcular matriz de distancias
  dist_matrix <- dist(df_cluster, method = "euclidean")
  
  # Clustering jerárquico
  hclust_result <- hclust(dist_matrix, method = "ward.D2")
  
  # Visualizar dendrograma
  png(file.path(OUT_DIR, "04_dendrograma.png"), 
      width = 30, height = 20, units = "cm", res = 300)
  plot(hclust_result, labels = FALSE, main = "Dendrograma - Clustering Jerárquico",
       xlab = "Observaciones", sub = "Método: Ward.D2")
  dev.off()
  cat("   💾 Guardado: 04_dendrograma.png\n")
  
  # Cortar árbol en k=3, 4, 5 clusters
  for (k in c(3, 4, 5)) {
    clusters_hier <- cutree(hclust_result, k = k)
    
    # Visualizar
    if (ncol(df_cluster) >= 2) {
      pca <- prcomp(df_cluster, scale. = FALSE)
      df_pca_hier <- as_tibble(pca$x[, 1:2]) %>%
        mutate(cluster = as.factor(clusters_hier),
               label = df_ml %>%
                 filter(!is.na(left_right_score), !is.na(confidence)) %>%
                 na.omit() %>%
                 pull(left_right_label))
      
      fig_hier <- df_pca_hier %>%
        ggplot(aes(x = PC1, y = PC2, color = cluster, shape = label)) +
        geom_point(alpha = 0.6, size = 2) +
        scale_color_viridis_d(option = "viridis") +
        labs(
          title = sprintf("Clustering Jerárquico (k=%d)", k),
          subtitle = "Método: Ward.D2",
          x = "Primera Componente Principal",
          y = "Segunda Componente Principal"
        ) +
        theme_ml()
      
      print(fig_hier)
      save_fig(fig_hier, sprintf("05_hierarchical_k%d.png", k))
    }
  }
}

# =============================================================
# 5) SVM - SUPPORT VECTOR MACHINE
# =============================================================
cat("\n🎯 Entrenando SVM para clasificación...\n")

# Preparar datos para SVM
df_svm <- df_ml %>%
  filter(!is.na(left_right_score), !is.na(confidence)) %>%
  select(left_right_score, confidence, rhetorical_mode_num, 
         main_target_num, stance_num, label_binary) %>%
  na.omit()

if (nrow(df_svm) > 50 && length(unique(df_svm$label_binary)) >= 2) {
  # Dividir en train/test (70/30)
  train_idx <- sample(1:nrow(df_svm), size = floor(0.7 * nrow(df_svm)))
  train_data <- df_svm[train_idx, ]
  test_data <- df_svm[-train_idx, ]
  
  # Entrenar SVM
  svm_model <- svm(
    label_binary ~ left_right_score + confidence + rhetorical_mode_num + 
                   main_target_num + stance_num,
    data = train_data,
    kernel = "radial",
    cost = 1,
    gamma = 0.1,
    probability = TRUE
  )
  
  # Predicciones
  train_pred <- predict(svm_model, train_data)
  test_pred <- predict(svm_model, test_data)
  
  # Matriz de confusión
  cm_train <- table(Actual = train_data$label_binary, Predicted = train_pred)
  cm_test <- table(Actual = test_data$label_binary, Predicted = test_pred)
  
  # Calcular accuracy
  accuracy_train <- sum(diag(cm_train)) / sum(cm_train)
  accuracy_test <- sum(diag(cm_test)) / sum(cm_test)
  
  cat(sprintf("   📊 Accuracy (train): %.3f\n", accuracy_train))
  cat(sprintf("   📊 Accuracy (test): %.3f\n", accuracy_test))
  
  # Guardar matrices de confusión
  write_csv(as_tibble(cm_train, rownames = "Actual"), 
            file.path(OUT_DIR, "06_svm_confusion_train.csv"))
  write_csv(as_tibble(cm_test, rownames = "Actual"), 
            file.path(OUT_DIR, "06_svm_confusion_test.csv"))
  
  # Visualizar predicciones vs reales
  df_svm_results <- test_data %>%
    mutate(
      predicted = test_pred,
      correct = label_binary == predicted
    )
  
  fig_svm <- df_svm_results %>%
    ggplot(aes(x = left_right_score, y = confidence, 
               color = label_binary, shape = predicted)) +
    geom_point(alpha = 0.6, size = 2) +
    scale_color_viridis_d(option = "plasma") +
    labs(
      title = "SVM - Predicciones vs Reales",
      subtitle = sprintf("Accuracy: %.1f%%", accuracy_test * 100),
      x = "Left-Right Score",
      y = "Confidence",
      color = "Real",
      shape = "Predicción"
    ) +
    theme_ml()
  
  print(fig_svm)
  save_fig(fig_svm, "06_svm_predictions.png")
  
  # Guardar modelo
  saveRDS(svm_model, file.path(OUT_DIR, "svm_model.rds"))
  cat("   💾 Modelo SVM guardado\n")
}

# =============================================================
# 6) RANDOM FOREST
# =============================================================
cat("\n🌲 Entrenando Random Forest...\n")

if (nrow(df_svm) > 50 && length(unique(df_svm$label_binary)) >= 2) {
  # Usar los mismos datos train/test que SVM
  rf_model <- randomForest(
    label_binary ~ left_right_score + confidence + rhetorical_mode_num + 
                   main_target_num + stance_num,
    data = train_data,
    ntree = 500,
    mtry = 3,
    importance = TRUE
  )
  
  # Predicciones
  rf_train_pred <- predict(rf_model, train_data)
  rf_test_pred <- predict(rf_model, test_data)
  
  # Accuracy
  rf_accuracy_train <- sum(rf_train_pred == train_data$label_binary) / nrow(train_data)
  rf_accuracy_test <- sum(rf_test_pred == test_data$label_binary) / nrow(test_data)
  
  cat(sprintf("   📊 Accuracy (train): %.3f\n", rf_accuracy_train))
  cat(sprintf("   📊 Accuracy (test): %.3f\n", rf_accuracy_test))
  
  # Importancia de variables
  importance_df <- as_tibble(importance(rf_model), rownames = "variable")
  
  fig_importance <- importance_df %>%
    pivot_longer(-variable, names_to = "metric", values_to = "importance") %>%
    ggplot(aes(x = reorder(variable, importance), y = importance, fill = metric)) +
    geom_col(position = "dodge", alpha = 0.8) +
    coord_flip() +
    scale_fill_viridis_d(option = "magma") +
    labs(
      title = "Importancia de Variables - Random Forest",
      x = "Variable",
      y = "Importancia",
      fill = "Métrica"
    ) +
    theme_ml()
  
  print(fig_importance)
  save_fig(fig_importance, "07_rf_importance.png")
  write_csv(importance_df, file.path(OUT_DIR, "07_rf_importance.csv"))
  
  # Guardar modelo
  saveRDS(rf_model, file.path(OUT_DIR, "rf_model.rds"))
  cat("   💾 Modelo Random Forest guardado\n")
}

# =============================================================
# 7) t-SNE - REDUCCIÓN DE DIMENSIONALIDAD
# =============================================================
cat("\n🎨 Aplicando t-SNE para visualización...\n")

if (nrow(df_cluster) > 10 && nrow(df_cluster) <= 1000) {
  # Aplicar t-SNE
  tsne_result <- Rtsne(df_cluster, dims = 2, perplexity = min(30, (nrow(df_cluster) - 1) / 4),
                       verbose = FALSE, max_iter = 1000)
  
  df_tsne <- as_tibble(tsne_result$Y) %>%
    set_names(c("tSNE1", "tSNE2")) %>%
    mutate(
      label = df_ml %>%
        filter(!is.na(left_right_score), !is.na(confidence)) %>%
        na.omit() %>%
        pull(left_right_label),
      score = df_ml %>%
        filter(!is.na(left_right_score), !is.na(confidence)) %>%
        na.omit() %>%
        pull(left_right_score)
    )
  
  # Visualizar por label
  fig_tsne_label <- df_tsne %>%
    ggplot(aes(x = tSNE1, y = tSNE2, color = label)) +
    geom_point(alpha = 0.6, size = 2) +
    scale_color_viridis_d(option = "plasma") +
    labs(
      title = "t-SNE - Visualización por Label de Ideología",
      x = "t-SNE Dimensión 1",
      y = "t-SNE Dimensión 2",
      color = "Label"
    ) +
    theme_ml()
  
  print(fig_tsne_label)
  save_fig(fig_tsne_label, "08_tsne_by_label.png")
  
  # Visualizar por score (gradiente)
  fig_tsne_score <- df_tsne %>%
    ggplot(aes(x = tSNE1, y = tSNE2, color = score)) +
    geom_point(alpha = 0.6, size = 2) +
    scale_color_gradient2(low = "blue", mid = "white", high = "red", midpoint = 0) +
    labs(
      title = "t-SNE - Visualización por Score Left-Right",
      x = "t-SNE Dimensión 1",
      y = "t-SNE Dimensión 2",
      color = "Score"
    ) +
    theme_ml()
  
  print(fig_tsne_score)
  save_fig(fig_tsne_score, "08_tsne_by_score.png")
}

# =============================================================
# 8) RESUMEN DE MODELOS
# =============================================================
cat("\n📊 Generando resumen de modelos...\n")

resumen_ml <- list(
  fecha_analisis = Sys.time(),
  n_observaciones = nrow(df_ml),
  n_variables = ncol(df_ml),
  modelos_entrenados = c()
)

if (exists("svm_model")) {
  resumen_ml$svm_accuracy_train <- accuracy_train
  resumen_ml$svm_accuracy_test <- accuracy_test
  resumen_ml$modelos_entrenados <- c(resumen_ml$modelos_entrenados, "SVM")
}

if (exists("rf_model")) {
  resumen_ml$rf_accuracy_train <- rf_accuracy_train
  resumen_ml$rf_accuracy_test <- rf_accuracy_test
  resumen_ml$modelos_entrenados <- c(resumen_ml$modelos_entrenados, "Random Forest")
}

write_csv(as_tibble(resumen_ml), file.path(OUT_DIR, "resumen_ml.csv"))

cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("✅ ANÁLISIS DE MACHINE LEARNING COMPLETADO\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat(sprintf("\n💾 Resultados guardados en: %s\n", OUT_DIR))
cat(sprintf("📊 Total de figuras generadas: %d\n", 
            length(list.files(OUT_DIR, pattern = "\\.png$"))))
cat(sprintf("🤖 Modelos entrenados: %s\n", 
            paste(resumen_ml$modelos_entrenados, collapse = ", ")))











