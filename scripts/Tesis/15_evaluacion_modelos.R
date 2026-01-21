# =============================================================
# 08) Evaluación de Modelos - Métricas y Diagnósticos
# =============================================================
# Evalúa los modelos de ML entrenados con métricas detalladas,
# validación cruzada, análisis de residuos, etc.
# Lee de: outputs/ml_ideologia/
# Guarda en: outputs/evaluacion_modelos/
# =============================================================

# rm(list = ls())  # Comentado para no perder objetos
set.seed(123)

# Setup
pacman::p_load(
  tidyverse, lubridate, here, readr, scales, 
  ggtext, patchwork, RColorBrewer, viridis,
  e1071,        # SVM
  randomForest, # Random Forest
  caret,        # Machine learning utilities y métricas
  pROC,         # Curvas ROC
  yardstick,    # Métricas adicionales
  vip           # Variable importance plots
)

# =============================================================
# CONFIGURACIÓN
# =============================================================
ML_DIR <- here("outputs", "ml_ideologia")
BASE_DIR <- here("data", "processed", "imputacion_ideologia")
OUT_DIR <- here("outputs", "evaluacion_modelos")
if (!dir.exists(OUT_DIR)) dir.create(OUT_DIR, recursive = TRUE)

# Encontrar el directorio más reciente de datos
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
theme_eval <- function(base_size = 12, legend.pos = "bottom") {
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
# 1) CARGA DE DATOS Y MODELOS
# =============================================================
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("📊 EVALUACIÓN DE MODELOS - MÉTRICAS Y DIAGNÓSTICOS\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Cargar datos
rds_file <- file.path(DATA_DIR, "resultados_completos.rds")
csv_files <- list.files(DATA_DIR, pattern = "imputacion.*\\.csv$", full.names = TRUE)

if (file.exists(rds_file)) {
  cat(sprintf("\n📂 Cargando datos desde RDS: %s\n", basename(rds_file)))
  datos_completos <- readRDS(rds_file)
  df <- datos_completos$df_resultados
} else if (length(csv_files) > 0) {
  csv_resultados <- csv_files[1]
  cat(sprintf("\n📂 Cargando datos desde CSV: %s\n", basename(csv_resultados)))
  df <- read_csv(csv_resultados, show_col_types = FALSE)
} else {
  stop("No se encontró archivo de resultados")
}

# Preparar datos
df_ml <- df %>%
  filter(
    !is.na(left_right_score),
    !is.na(confidence),
    !is.na(left_right_label)
  ) %>%
  mutate(
    left_right_score = as.numeric(left_right_score),
    confidence = as.numeric(confidence),
    rhetorical_mode_num = as.numeric(factor(rhetorical_mode)),
    main_target_num = as.numeric(factor(main_target)),
    stance_num = as.numeric(factor(stance_toward_target)),
    label_factor = factor(left_right_label),
    label_binary = factor(ifelse(left_right_score < 0, "Left", 
                                 ifelse(left_right_score > 0, "Right", "Center"))),
    comment_length = if("comment_body" %in% names(.)) nchar(comment_body) else NA_real_
  ) %>%
  filter(!is.na(left_right_score), !is.na(confidence)) %>%
  select(left_right_score, confidence, rhetorical_mode_num, 
         main_target_num, stance_num, label_binary, label_factor) %>%
  na.omit()

cat(sprintf("   ✅ Datos preparados: %d filas\n", nrow(df_ml)))

# Cargar modelos si existen
svm_model <- NULL
rf_model <- NULL

if (file.exists(file.path(ML_DIR, "svm_model.rds"))) {
  svm_model <- readRDS(file.path(ML_DIR, "svm_model.rds"))
  cat("   ✅ Modelo SVM cargado\n")
}

if (file.exists(file.path(ML_DIR, "rf_model.rds"))) {
  rf_model <- readRDS(file.path(ML_DIR, "rf_model.rds"))
  cat("   ✅ Modelo Random Forest cargado\n")
}

if (is.null(svm_model) && is.null(rf_model)) {
  cat("   ⚠️ No se encontraron modelos. Entrenando nuevos modelos...\n")
  
  # Dividir datos
  train_idx <- sample(1:nrow(df_ml), size = floor(0.7 * nrow(df_ml)))
  train_data <- df_ml[train_idx, ]
  test_data <- df_ml[-train_idx, ]
  
  # Entrenar SVM
  if (nrow(train_data) > 50 && length(unique(train_data$label_binary)) >= 2) {
    svm_model <- svm(
      label_binary ~ left_right_score + confidence + rhetorical_mode_num + 
                     main_target_num + stance_num,
      data = train_data,
      kernel = "radial",
      cost = 1,
      gamma = 0.1,
      probability = TRUE
    )
    cat("   ✅ SVM entrenado\n")
  }
  
  # Entrenar Random Forest
  if (nrow(train_data) > 50 && length(unique(train_data$label_binary)) >= 2) {
    rf_model <- randomForest(
      label_binary ~ left_right_score + confidence + rhetorical_mode_num + 
                     main_target_num + stance_num,
      data = train_data,
      ntree = 500,
      mtry = 3,
      importance = TRUE
    )
    cat("   ✅ Random Forest entrenado\n")
  }
} else {
  # Dividir datos para evaluación
  train_idx <- sample(1:nrow(df_ml), size = floor(0.7 * nrow(df_ml)))
  train_data <- df_ml[train_idx, ]
  test_data <- df_ml[-train_idx, ]
}

# =============================================================
# 2) MÉTRICAS DETALLADAS POR MODELO
# =============================================================
cat("\n📊 Calculando métricas detalladas...\n")

metricas_completas <- list()

# Función para calcular métricas completas
calcular_metricas <- function(actual, predicted, modelo_nombre) {
  # Matriz de confusión
  actual_f <- factor(actual)
  predicted_f <- factor(predicted, levels = levels(actual_f))
  cm <- confusionMatrix(predicted_f, actual_f)
  
  # Métricas básicas
  accuracy <- as.numeric(cm$overall["Accuracy"])
  kappa <- as.numeric(cm$overall["Kappa"])
  
  # Métricas por clase - manejar diferentes estructuras
  cm_table <- cm$table
  n_classes <- nrow(cm_table)
  
  # Intentar obtener métricas de byClass
  sensitivity <- NA_real_
  specificity <- NA_real_
  precision <- NA_real_
  recall <- NA_real_
  f1 <- NA_real_
  
  if (!is.null(cm$byClass)) {
    # Si byClass es una matriz (múltiples clases)
    if (is.matrix(cm$byClass) || is.data.frame(cm$byClass)) {
      if ("Sensitivity" %in% colnames(cm$byClass)) {
        sensitivity <- mean(cm$byClass[, "Sensitivity"], na.rm = TRUE)
      }
      if ("Specificity" %in% colnames(cm$byClass)) {
        specificity <- mean(cm$byClass[, "Specificity"], na.rm = TRUE)
      }
      if ("Precision" %in% colnames(cm$byClass)) {
        precision <- mean(cm$byClass[, "Precision"], na.rm = TRUE)
      }
      if ("Recall" %in% colnames(cm$byClass)) {
        recall <- mean(cm$byClass[, "Recall"], na.rm = TRUE)
      }
      if ("F1" %in% colnames(cm$byClass)) {
        f1 <- mean(cm$byClass[, "F1"], na.rm = TRUE)
      }
    } else if (is.vector(cm$byClass) || is.numeric(cm$byClass)) {
      # Si byClass es un vector con nombres
      if ("Sensitivity" %in% names(cm$byClass)) {
        sensitivity <- as.numeric(cm$byClass["Sensitivity"])
      }
      if ("Specificity" %in% names(cm$byClass)) {
        specificity <- as.numeric(cm$byClass["Specificity"])
      }
      if ("Precision" %in% names(cm$byClass)) {
        precision <- as.numeric(cm$byClass["Precision"])
      }
      if ("Recall" %in% names(cm$byClass)) {
        recall <- as.numeric(cm$byClass["Recall"])
      }
      if ("F1" %in% names(cm$byClass)) {
        f1 <- as.numeric(cm$byClass["F1"])
      }
    }
  }
  
  # Si no se obtuvieron métricas, calcular manualmente desde la matriz
  if (is.na(sensitivity) || is.na(specificity) || is.na(f1)) {
    # Calcular métricas por clase y promediar (macro-averaging)
    sensitivities <- c()
    specificities <- c()
    precisions <- c()
    recalls <- c()
    f1s <- c()
    
    for (i in 1:n_classes) {
      clase <- rownames(cm_table)[i]
      TP <- cm_table[i, i]
      FN <- sum(cm_table[i, -i], na.rm = TRUE)
      FP <- sum(cm_table[-i, i], na.rm = TRUE)
      TN <- sum(cm_table[-i, -i], na.rm = TRUE)
      
      if ((TP + FN) > 0) {
        sens <- TP / (TP + FN)
        sensitivities <- c(sensitivities, sens)
        recalls <- c(recalls, sens)
      }
      
      if ((TN + FP) > 0) {
        spec <- TN / (TN + FP)
        specificities <- c(specificities, spec)
      }
      
      if ((TP + FP) > 0) {
        prec <- TP / (TP + FP)
        precisions <- c(precisions, prec)
      }
    }
    
    # Promediar (macro-averaging)
    if (length(sensitivities) > 0) {
      sensitivity <- mean(sensitivities, na.rm = TRUE)
      recall <- mean(recalls, na.rm = TRUE)
    }
    if (length(specificities) > 0) {
      specificity <- mean(specificities, na.rm = TRUE)
    }
    if (length(precisions) > 0) {
      precision <- mean(precisions, na.rm = TRUE)
    }
    
    # Calcular F1
    if (!is.na(precision) && !is.na(recall) && (precision + recall) > 0) {
      f1 <- 2 * (precision * recall) / (precision + recall)
    }
  }
  
  # Balanced accuracy
  if (!is.na(sensitivity) && !is.na(specificity)) {
    balanced_accuracy <- mean(c(sensitivity, specificity), na.rm = TRUE)
  } else {
    balanced_accuracy <- NA_real_
  }
  
  return(list(
    modelo = modelo_nombre,
    accuracy = accuracy,
    kappa = kappa,
    sensitivity = sensitivity,
    specificity = specificity,
    precision = precision,
    recall = recall,
    f1 = f1,
    balanced_accuracy = balanced_accuracy,
    confusion_matrix = cm$table
  ))
}

# Evaluar SVM
if (!is.null(svm_model)) {
  cat("\n🎯 Evaluando SVM...\n")
  
  # Predicciones
  svm_train_pred <- predict(svm_model, train_data)
  svm_test_pred <- predict(svm_model, test_data)
  
  # Métricas train
  metricas_svm_train <- calcular_metricas(train_data$label_binary, svm_train_pred, "SVM_Train")
  metricas_completas[["SVM_Train"]] <- metricas_svm_train
  
  # Métricas test
  metricas_svm_test <- calcular_metricas(test_data$label_binary, svm_test_pred, "SVM_Test")
  metricas_completas[["SVM_Test"]] <- metricas_svm_test
  
  cat(sprintf("   Accuracy (train): %.3f\n", metricas_svm_train$accuracy))
  cat(sprintf("   Accuracy (test): %.3f\n", metricas_svm_test$accuracy))
  cat(sprintf("   Kappa (test): %.3f\n", metricas_svm_test$kappa))
  cat(sprintf("   F1 (test): %.3f\n", metricas_svm_test$f1))
  
  # Curva ROC (si hay probabilidades)
  tryCatch({
    svm_probs <- attr(predict(svm_model, test_data, probability = TRUE), "probabilities")
    
    if (!is.null(svm_probs) && ncol(svm_probs) > 0) {
      
      # Para cada clase
      roc_data <- list()
      for (clase in levels(test_data$label_binary)) {
        if (clase %in% colnames(svm_probs)) {
          actual_binary <- as.numeric(test_data$label_binary == clase)
          prob_clase <- svm_probs[, clase]
          
          if (length(unique(actual_binary)) > 1 && sum(actual_binary) > 0) {
            roc_obj <- roc(actual_binary, prob_clase, quiet = TRUE)
            roc_data[[clase]] <- list(
              fpr = 1 - roc_obj$specificities,
              tpr = roc_obj$sensitivities,
              auc = as.numeric(auc(roc_obj))
            )
          }
        }
      }
      
      # Visualizar ROC
      if (length(roc_data) > 0) {
        df_roc <- map_dfr(names(roc_data), function(clase) {
          tibble(
            clase = clase,
            fpr = roc_data[[clase]]$fpr,
            tpr = roc_data[[clase]]$tpr,
            auc = roc_data[[clase]]$auc
          )
        })
        
        fig_roc_svm <- df_roc %>%
          ggplot(aes(x = fpr, y = tpr, color = clase)) +
          geom_line(linewidth = 1.2) +
          geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "grey50") +
          scale_color_viridis_d(option = "plasma") +
          labs(
            title = "Curva ROC - SVM",
            x = "Tasa de Falsos Positivos (1 - Especificidad)",
            y = "Tasa de Verdaderos Positivos (Sensibilidad)",
            color = "Clase"
          ) +
          theme_eval()
        
        # Agregar AUC al subtítulo
        auc_text <- paste(sprintf("%s: AUC=%.3f", names(roc_data), 
                                  map_dbl(roc_data, ~.x$auc)), collapse = " | ")
        fig_roc_svm <- fig_roc_svm + 
          labs(subtitle = auc_text)
        
        print(fig_roc_svm)
        save_fig(fig_roc_svm, "01_roc_svm.png")
      } else {
        cat("   ⚠️ No se pudieron calcular curvas ROC (insuficientes clases o datos)\n")
      }
    } else {
      cat("   ⚠️ No se encontraron probabilidades en el modelo SVM\n")
    }
  }, error = function(e) {
    cat(sprintf("   ⚠️ No se pudo calcular ROC: %s\n", e$message))
  })
}

# Evaluar Random Forest
if (!is.null(rf_model)) {
  cat("\n🌲 Evaluando Random Forest...\n")
  
  # Predicciones
  rf_train_pred <- predict(rf_model, train_data)
  rf_test_pred <- predict(rf_model, test_data)
  
  # Métricas train
  metricas_rf_train <- calcular_metricas(train_data$label_binary, rf_train_pred, "RF_Train")
  metricas_completas[["RF_Train"]] <- metricas_rf_train
  
  # Métricas test
  metricas_rf_test <- calcular_metricas(test_data$label_binary, rf_test_pred, "RF_Test")
  metricas_completas[["RF_Test"]] <- metricas_rf_test
  
  cat(sprintf("   Accuracy (train): %.3f\n", metricas_rf_train$accuracy))
  cat(sprintf("   Accuracy (test): %.3f\n", metricas_rf_test$accuracy))
  cat(sprintf("   Kappa (test): %.3f\n", metricas_rf_test$kappa))
  cat(sprintf("   F1 (test): %.3f\n", metricas_rf_test$f1))
  
  # Curva ROC
  tryCatch({
    rf_probs <- predict(rf_model, test_data, type = "prob")
    
    roc_data_rf <- list()
    for (clase in levels(test_data$label_binary)) {
      actual_binary <- as.numeric(test_data$label_binary == clase)
      prob_clase <- rf_probs[, clase]
      
      if (length(unique(actual_binary)) > 1) {
        roc_obj <- roc(actual_binary, prob_clase, quiet = TRUE)
        roc_data_rf[[clase]] <- list(
          fpr = 1 - roc_obj$specificities,
          tpr = roc_obj$sensitivities,
          auc = as.numeric(auc(roc_obj))
        )
      }
    }
    
    if (length(roc_data_rf) > 0) {
      df_roc_rf <- map_dfr(names(roc_data_rf), function(clase) {
        tibble(
          clase = clase,
          fpr = roc_data_rf[[clase]]$fpr,
          tpr = roc_data_rf[[clase]]$tpr,
          auc = roc_data_rf[[clase]]$auc
        )
      })
      
      fig_roc_rf <- df_roc_rf %>%
        ggplot(aes(x = fpr, y = tpr, color = clase)) +
        geom_line(linewidth = 1.2) +
        geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "grey50") +
        scale_color_viridis_d(option = "viridis") +
        labs(
          title = "Curva ROC - Random Forest",
          x = "Tasa de Falsos Positivos (1 - Especificidad)",
          y = "Tasa de Verdaderos Positivos (Sensibilidad)",
          color = "Clase"
        ) +
        theme_eval()
      
      auc_text <- paste(sprintf("%s: AUC=%.3f", names(roc_data_rf), 
                                map_dbl(roc_data_rf, ~.x$auc)), collapse = " | ")
      fig_roc_rf <- fig_roc_rf + 
        labs(subtitle = auc_text)
      
      print(fig_roc_rf)
      save_fig(fig_roc_rf, "02_roc_rf.png")
    }
  }, error = function(e) {
    cat(sprintf("   ⚠️ No se pudo calcular ROC: %s\n", e$message))
  })
}

# =============================================================
# 3) VALIDACIÓN CRUZADA
# =============================================================
cat("\n🔄 Realizando validación cruzada...\n")

if (nrow(df_ml) > 50 && length(unique(df_ml$label_binary)) >= 2) {
  # Configurar control de validación cruzada
  ctrl <- trainControl(
    method = "cv",
    number = 5,
    summaryFunction = multiClassSummary,
    classProbs = TRUE,
    savePredictions = "final"
  )
  
  # Validación cruzada para SVM
  if (!is.null(svm_model)) {
    tryCatch({
      cat("   🔄 CV para SVM...\n")
      svm_cv <- train(
        label_binary ~ left_right_score + confidence + rhetorical_mode_num + 
                       main_target_num + stance_num,
        data = df_ml,
        method = "svmRadial",
        trControl = ctrl,
        tuneGrid = expand.grid(sigma = 0.1, C = 1),
        metric = "Accuracy"
      )
      
      cv_results_svm <- svm_cv$results
      write_csv(cv_results_svm, file.path(OUT_DIR, "03_cv_svm_results.csv"))
      
      cat(sprintf("      Accuracy promedio (CV): %.3f (SD: %.3f)\n", 
                  mean(svm_cv$resample$Accuracy),
                  sd(svm_cv$resample$Accuracy)))
    }, error = function(e) {
      cat(sprintf("   ⚠️ Error en CV SVM: %s\n", e$message))
    })
  }
  
  # Validación cruzada para Random Forest
  if (!is.null(rf_model)) {
    tryCatch({
      cat("   🔄 CV para Random Forest...\n")
      rf_cv <- train(
        label_binary ~ left_right_score + confidence + rhetorical_mode_num + 
                       main_target_num + stance_num,
        data = df_ml,
        method = "rf",
        trControl = ctrl,
        ntree = 500,
        metric = "Accuracy"
      )
      
      cv_results_rf <- rf_cv$results
      write_csv(cv_results_rf, file.path(OUT_DIR, "03_cv_rf_results.csv"))
      
      cat(sprintf("      Accuracy promedio (CV): %.3f (SD: %.3f)\n", 
                  mean(rf_cv$resample$Accuracy),
                  sd(rf_cv$resample$Accuracy)))
    }, error = function(e) {
      cat(sprintf("   ⚠️ Error en CV RF: %s\n", e$message))
    })
  }
}

# =============================================================
# 4) COMPARACIÓN DE MODELOS
# =============================================================
cat("\n📊 Comparando modelos...\n")

# Crear tabla comparativa
if (length(metricas_completas) > 0) {
  comparacion <- map_dfr(metricas_completas, function(m) {
    tibble(
      Modelo = m$modelo,
      Accuracy = m$accuracy,
      Kappa = m$kappa,
      Sensitivity = m$sensitivity,
      Specificity = m$specificity,
      Precision = m$precision,
      Recall = m$recall,
      F1 = m$f1,
      Balanced_Accuracy = m$balanced_accuracy
    )
  })
  
  write_csv(comparacion, file.path(OUT_DIR, "04_comparacion_modelos.csv"))
  
  # Visualizar comparación
  comparacion_long <- comparacion %>%
    pivot_longer(-Modelo, names_to = "Metrica", values_to = "Valor") %>%
    filter(!is.na(Valor))
  
  fig_comparacion <- comparacion_long %>%
    ggplot(aes(x = Metrica, y = Valor, fill = Modelo)) +
    geom_col(position = "dodge", alpha = 0.8, color = "black", linewidth = 0.3) +
    scale_fill_viridis_d(option = "plasma") +
    labs(
      title = "Comparación de Métricas entre Modelos",
      x = "Métrica",
      y = "Valor"
    ) +
    theme_eval() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  print(fig_comparacion)
  save_fig(fig_comparacion, "04_comparacion_modelos.png")
  
  # Imprimir tabla
  cat("\n📊 Tabla Comparativa:\n")
  print(comparacion)
}

# =============================================================
# 5) ANÁLISIS DE ERRORES
# =============================================================
cat("\n🔍 Analizando errores de predicción...\n")

if (!is.null(svm_model)) {
  svm_test_pred <- predict(svm_model, test_data)
  errores_svm <- test_data %>%
    mutate(
      predicted = svm_test_pred,
      error = label_binary != predicted,
      tipo_error = case_when(
        label_binary == "Left" & predicted == "Right" ~ "Left→Right",
        label_binary == "Right" & predicted == "Left" ~ "Right→Left",
        label_binary == "Center" & predicted != "Center" ~ "Center→Other",
        TRUE ~ "Correcto"
      )
    )
  
  # Análisis de errores
  analisis_errores <- errores_svm %>%
    filter(error) %>%
    summarise(
      n_errores = n(),
      score_medio = mean(left_right_score, na.rm = TRUE),
      confidence_medio = mean(confidence, na.rm = TRUE),
      .groups = "drop"
    )
  
  write_csv(analisis_errores, file.path(OUT_DIR, "05_analisis_errores_svm.csv"))
  
  # Visualizar distribución de errores
  if (nrow(errores_svm %>% filter(error)) > 0) {
    fig_errores <- errores_svm %>%
      filter(error) %>%
      ggplot(aes(x = left_right_score, y = confidence, color = tipo_error)) +
      geom_point(alpha = 0.6, size = 2) +
      scale_color_viridis_d(option = "magma") +
      labs(
        title = "Análisis de Errores - SVM",
        x = "Left-Right Score",
        y = "Confidence",
        color = "Tipo de Error"
      ) +
      theme_eval()
    
    print(fig_errores)
    save_fig(fig_errores, "05_errores_svm.png")
  }
}

# =============================================================
# 6) RESUMEN FINAL
# =============================================================
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("✅ EVALUACIÓN DE MODELOS COMPLETADA\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat(sprintf("\n💾 Resultados guardados en: %s\n", OUT_DIR))
cat(sprintf("📊 Total de figuras generadas: %d\n", 
            length(list.files(OUT_DIR, pattern = "\\.png$"))))

# Guardar resumen de métricas
if (length(metricas_completas) > 0) {
  resumen_final <- map_dfr(metricas_completas, function(m) {
    tibble(
      Modelo = m$modelo,
      Accuracy = m$accuracy,
      Kappa = m$kappa,
      F1 = m$f1,
      Balanced_Accuracy = m$balanced_accuracy
    )
  })
  
  write_csv(resumen_final, file.path(OUT_DIR, "resumen_metricas.csv"))
  cat("\n📊 Resumen de Métricas:\n")
  print(resumen_final)
}

