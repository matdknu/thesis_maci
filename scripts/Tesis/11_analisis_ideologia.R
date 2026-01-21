# =============================================================
# 06) Análisis de Resultados de Imputación de Ideología
# =============================================================
# Analiza y visualiza los resultados de la imputación de ideología
# Lee de: data/processed/imputacion_ideologia/[fecha_ejecucion]/
# Guarda en: outputs/analisis_ideologia/
# =============================================================

# rm(list = ls())  # Comentado para no perder objetos
set.seed(123)

# Setup
pacman::p_load(
  tidyverse, lubridate, here, readr, scales, 
  ggtext, patchwork, RColorBrewer, viridis
)

# =============================================================
# CONFIGURACIÓN
# =============================================================
# Seleccionar el directorio más reciente de imputación
BASE_DIR <- here("data", "processed", "imputacion_ideologia")
OUT_DIR <- here("outputs", "analisis_ideologia")
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
theme_ideologia <- function(base_size = 12, legend.pos = "bottom") {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = base_size + 2),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40", size = base_size),
      plot.caption = element_text(hjust = 0, color = "grey50", size = base_size - 2),
      legend.position = legend.pos,
      legend.title = element_blank(),
      panel.grid.minor = element_blank(),
      axis.text.x = element_text(angle = 45, hjust = 1)
    )
}

save_fig <- function(plot, filename, width_cm = 20, height_cm = 15, dpi = 300) {
  ggsave(file.path(OUT_DIR, filename), plot, 
         width = width_cm, height = height_cm, units = "cm", dpi = dpi)
  cat(sprintf("   💾 Guardado: %s\n", filename))
}

# =============================================================
# 1) CARGA DE DATOS
# =============================================================
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("📊 ANÁLISIS DE RESULTADOS DE IMPUTACIÓN DE IDEOLOGÍA\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# Intentar cargar desde RDS primero (más completo)
rds_file <- file.path(DATA_DIR, "resultados_completos.rds")
csv_files <- list.files(DATA_DIR, pattern = "imputacion.*\\.csv$", full.names = TRUE)

if (file.exists(rds_file)) {
  cat(sprintf("\n📂 Cargando desde RDS: %s\n", basename(rds_file)))
  datos_completos <- readRDS(rds_file)
  df <- datos_completos$df_resultados
  cat(sprintf("   ✅ Datos cargados: %d filas\n", nrow(df)))
  
  # Cargar también metadatos si existen
  if (!is.null(datos_completos$info_sample)) {
    cat(sprintf("   📊 Metadatos disponibles: %d comentarios, costo: $%.2f\n", 
                datos_completos$info_sample$n_comentarios,
                datos_completos$info_sample$costo_total))
  }
} else if (length(csv_files) > 0) {
  csv_resultados <- csv_files[1]
  cat(sprintf("\n📂 Cargando desde CSV: %s\n", basename(csv_resultados)))
  df <- read_csv(csv_resultados, show_col_types = FALSE)
  cat(sprintf("   ✅ Datos cargados: %d filas\n", nrow(df)))
} else {
  stop("No se encontró archivo de resultados (RDS o CSV)")
}

# Limpiar y preparar datos
df <- df %>%
  mutate(
    # Asegurar que las fechas sean Date si existen
    fecha = if("fecha" %in% names(.)) as.Date(fecha) else NA_Date_,
    # Asegurar tipos numéricos
    left_right_score = as.numeric(left_right_score),
    confidence = as.numeric(confidence)
  )

cat(sprintf("   📋 Columnas: %s\n", paste(names(df), collapse = ", ")))

# =============================================================
# 2) DISTRIBUCIÓN DE IDEOLOGÍAS
# =============================================================
cat("\n📈 Generando análisis de distribución...\n")

# Distribución de labels
if ("left_right_label" %in% names(df)) {
  distribucion_labels <- df %>%
    filter(!is.na(left_right_label)) %>%
    count(left_right_label, sort = TRUE) %>%
    mutate(
      pct = n / sum(n) * 100,
      label_ordenado = factor(left_right_label, levels = left_right_label[order(n, decreasing = TRUE)])
    )
  
  fig1 <- distribucion_labels %>%
    ggplot(aes(x = label_ordenado, y = n, fill = label_ordenado)) +
    geom_col(alpha = 0.8, show.legend = FALSE, color = "black", linewidth = 0.3) +
    geom_text(aes(label = paste0(n, "\n(", round(pct, 1), "%)")), 
              vjust = -0.3, size = 3.5) +
    scale_fill_viridis_d(option = "plasma") +
    labs(
      title = "Distribución de Ideologías Left-Right",
      subtitle = paste("Total de comentarios analizados:", sum(distribucion_labels$n)),
      x = "Label de Ideología",
      y = "Frecuencia",
      caption = "Nota. Porcentajes entre paréntesis."
    ) +
    theme_ideologia()
  
  print(fig1)
  save_fig(fig1, "01_distribucion_labels.png")
  
  # Guardar tabla
  write_csv(distribucion_labels, file.path(OUT_DIR, "01_distribucion_labels.csv"))
}

# =============================================================
# 3) DISTRIBUCIÓN DE SCORES
# =============================================================
if ("left_right_score" %in% names(df)) {
  scores_validos <- df$left_right_score[!is.na(df$left_right_score)]
  
  if (length(scores_validos) > 0) {
    # Histograma general
    fig2 <- df %>%
      filter(!is.na(left_right_score)) %>%
      ggplot(aes(x = left_right_score)) +
      geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7, color = "black", linewidth = 0.3) +
      geom_vline(aes(xintercept = mean(left_right_score, na.rm = TRUE)), 
                 linetype = "dashed", color = "red", linewidth = 1.2) +
      geom_vline(aes(xintercept = median(left_right_score, na.rm = TRUE)), 
                 linetype = "dotted", color = "orange", linewidth = 1) +
      geom_vline(aes(xintercept = 0), linetype = "solid", color = "grey50", linewidth = 0.5) +
      labs(
        title = "Distribución de Scores Left-Right",
        subtitle = paste("Media:", round(mean(scores_validos), 3), 
                        "| Mediana:", round(median(scores_validos), 3),
                        "| SD:", round(sd(scores_validos), 3)),
        x = "Left-Right Score (-1 = Left, +1 = Right)",
        y = "Frecuencia",
        caption = "Nota. Línea roja = media, línea naranja = mediana, línea gris = centro (0)."
      ) +
      theme_ideologia()
    
    print(fig2)
    save_fig(fig2, "02_distribucion_scores.png")
    
    # Boxplot por label
    if ("left_right_label" %in% names(df)) {
      fig3 <- df %>%
        filter(!is.na(left_right_score), !is.na(left_right_label)) %>%
        ggplot(aes(x = reorder(left_right_label, left_right_score, median), 
                   y = left_right_score, fill = left_right_label)) +
        geom_boxplot(alpha = 0.7, show.legend = FALSE, outlier.alpha = 0.3) +
        geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
        scale_fill_viridis_d(option = "plasma") +
        labs(
          title = "Distribución de Scores por Label de Ideología",
          x = "Label",
          y = "Left-Right Score"
        ) +
        theme_ideologia()
      
      print(fig3)
      save_fig(fig3, "03_scores_por_label.png")
    }
  }
}

# =============================================================
# 4) ANÁLISIS DE CONFIDENCE
# =============================================================
if ("confidence" %in% names(df)) {
  conf_validos <- df$confidence[!is.na(df$confidence)]
  
  if (length(conf_validos) > 0) {
    fig4 <- df %>%
      filter(!is.na(confidence)) %>%
      ggplot(aes(x = confidence)) +
      geom_histogram(bins = 30, fill = "orange", alpha = 0.7, color = "black", linewidth = 0.3) +
      geom_vline(aes(xintercept = mean(confidence, na.rm = TRUE)), 
                 linetype = "dashed", color = "red", linewidth = 1.2) +
      labs(
        title = "Distribución de Confidence Scores",
        subtitle = paste("Media:", round(mean(conf_validos), 3),
                        "| Mediana:", round(median(conf_validos), 3)),
        x = "Confidence (0-1)",
        y = "Frecuencia"
      ) +
      theme_ideologia()
    
    print(fig4)
    save_fig(fig4, "04_distribucion_confidence.png")
    
    # Confidence por label
    if ("left_right_label" %in% names(df)) {
      fig5 <- df %>%
        filter(!is.na(confidence), !is.na(left_right_label)) %>%
        ggplot(aes(x = reorder(left_right_label, confidence, median), 
                   y = confidence, fill = left_right_label)) +
        geom_boxplot(alpha = 0.7, show.legend = FALSE) +
        scale_fill_viridis_d(option = "plasma") +
        labs(
          title = "Confidence por Label de Ideología",
          x = "Label",
          y = "Confidence"
        ) +
        theme_ideologia()
      
      print(fig5)
      save_fig(fig5, "05_confidence_por_label.png")
    }
  }
}

# =============================================================
# 5) ANÁLISIS DE INTERPRETACIÓN (Rhetorical Mode, Targets, Frames)
# =============================================================
cat("\n📊 Analizando interpretaciones (rhetorical mode, targets, frames)...\n")

# Rhetorical Mode
if ("rhetorical_mode" %in% names(df)) {
  modos <- df %>%
    filter(!is.na(rhetorical_mode)) %>%
    count(rhetorical_mode, sort = TRUE) %>%
    mutate(pct = n / sum(n) * 100)
  
  if (nrow(modos) > 0) {
    fig6 <- modos %>%
      ggplot(aes(x = reorder(rhetorical_mode, n), y = n, fill = rhetorical_mode)) +
      geom_col(alpha = 0.8, show.legend = FALSE, color = "black", linewidth = 0.3) +
      coord_flip() +
      scale_fill_viridis_d(option = "viridis") +
      labs(
        title = "Distribución de Modos Retóricos",
        x = "Modo Retórico",
        y = "Frecuencia"
      ) +
      theme_ideologia(legend.pos = "none")
    
    print(fig6)
    save_fig(fig6, "06_rhetorical_mode.png")
    write_csv(modos, file.path(OUT_DIR, "06_rhetorical_mode.csv"))
  }
}

# Main Target
if ("main_target" %in% names(df)) {
  targets <- df %>%
    filter(!is.na(main_target)) %>%
    count(main_target, sort = TRUE) %>%
    mutate(pct = n / sum(n) * 100) %>%
    head(15)  # Top 15
    
  if (nrow(targets) > 0) {
    fig7 <- targets %>%
      ggplot(aes(x = reorder(main_target, n), y = n, fill = main_target)) +
      geom_col(alpha = 0.8, show.legend = FALSE, color = "black", linewidth = 0.3) +
      coord_flip() +
      scale_fill_viridis_d(option = "cividis") +
      labs(
        title = "Top 15 Targets Principales",
        x = "Target",
        y = "Frecuencia"
      ) +
      theme_ideologia(legend.pos = "none")
    
    print(fig7)
    save_fig(fig7, "07_main_targets.png")
    write_csv(targets, file.path(OUT_DIR, "07_main_targets.csv"))
  }
}

# Key Frames
if ("key_frames" %in% names(df)) {
  # Separar frames (pueden estar separados por "; ")
  frames_expandidos <- df %>%
    filter(!is.na(key_frames)) %>%
    separate_rows(key_frames, sep = "; ") %>%
    filter(str_trim(key_frames) != "") %>%
    count(key_frames, sort = TRUE) %>%
    mutate(pct = n / sum(n) * 100)
  
  if (nrow(frames_expandidos) > 0) {
    fig8 <- frames_expandidos %>%
      head(12) %>%  # Top 12
      ggplot(aes(x = reorder(key_frames, n), y = n, fill = key_frames)) +
      geom_col(alpha = 0.8, show.legend = FALSE, color = "black", linewidth = 0.3) +
      coord_flip() +
      scale_fill_viridis_d(option = "magma") +
      labs(
        title = "Top 12 Key Frames Discursivos",
        x = "Frame",
        y = "Frecuencia"
      ) +
      theme_ideologia(legend.pos = "none")
    
    print(fig8)
    save_fig(fig8, "08_key_frames.png")
    write_csv(frames_expandidos, file.path(OUT_DIR, "08_key_frames.csv"))
  }
}

# =============================================================
# 6) ANÁLISIS TEMPORAL (si hay fechas)
# =============================================================
if ("fecha" %in% names(df) && sum(!is.na(df$fecha)) > 0) {
  cat("\n📅 Analizando evolución temporal...\n")
  
  df_temporal <- df %>%
    filter(!is.na(fecha)) %>%
    mutate(
      semana = floor_date(fecha, "week"),
      mes = floor_date(fecha, "month")
    )
  
  # Evolución de scores por semana
  if ("left_right_score" %in% names(df_temporal)) {
    evolucion_semana <- df_temporal %>%
      filter(!is.na(left_right_score)) %>%
      group_by(semana) %>%
      summarise(
        score_medio = mean(left_right_score, na.rm = TRUE),
        score_mediano = median(left_right_score, na.rm = TRUE),
        n = n(),
        .groups = "drop"
      ) %>%
      filter(n >= 5)  # Solo semanas con al menos 5 comentarios
    
    if (nrow(evolucion_semana) > 0) {
      fig9 <- evolucion_semana %>%
        ggplot(aes(x = semana, y = score_medio)) +
        geom_line(color = "steelblue", linewidth = 1.2) +
        geom_point(color = "steelblue", size = 2) +
        geom_ribbon(aes(ymin = score_medio - 0.1, ymax = score_medio + 0.1), 
                    alpha = 0.2, fill = "steelblue") +
        geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
        labs(
          title = "Evolución Temporal del Score Left-Right (Promedio Semanal)",
          x = "Semana",
          y = "Score Promedio"
        ) +
        theme_ideologia(legend.pos = "none")
      
      print(fig9)
      save_fig(fig9, "09_evolucion_temporal_scores.png")
      write_csv(evolucion_semana, file.path(OUT_DIR, "09_evolucion_temporal_scores.csv"))
    }
  }
  
  # Distribución de labels por mes
  if ("left_right_label" %in% names(df_temporal)) {
    labels_mes <- df_temporal %>%
      filter(!is.na(left_right_label)) %>%
      count(mes, left_right_label) %>%
      group_by(mes) %>%
      mutate(pct = n / sum(n) * 100) %>%
      ungroup()
    
    if (nrow(labels_mes) > 0) {
      fig10 <- labels_mes %>%
        ggplot(aes(x = mes, y = pct, fill = left_right_label)) +
        geom_area(alpha = 0.7, position = "stack") +
        scale_fill_viridis_d(option = "plasma") +
        labs(
          title = "Evolución de Distribución de Labels por Mes",
          x = "Mes",
          y = "Porcentaje",
          fill = "Label"
        ) +
        theme_ideologia(legend.pos = "bottom")
      
      print(fig10)
      save_fig(fig10, "10_evolucion_labels_temporal.png", height_cm = 18)
    }
  }
}

# =============================================================
# 7) ANÁLISIS POR SUBREDDIT (si existe)
# =============================================================
if ("post_subreddit" %in% names(df) || "subreddit" %in% names(df)) {
  cat("\n📱 Analizando por subreddit...\n")
  
  subreddit_col <- if("post_subreddit" %in% names(df)) "post_subreddit" else "subreddit"
  
  if ("left_right_score" %in% names(df)) {
    scores_subreddit <- df %>%
      filter(!is.na(!!sym(subreddit_col)), !is.na(left_right_score)) %>%
      group_by(!!sym(subreddit_col)) %>%
      summarise(
        score_medio = mean(left_right_score, na.rm = TRUE),
        n = n(),
        .groups = "drop"
      ) %>%
      filter(n >= 10) %>%  # Solo subreddits con al menos 10 comentarios
      arrange(desc(score_medio))
    
    if (nrow(scores_subreddit) > 0) {
      fig11 <- scores_subreddit %>%
        ggplot(aes(x = reorder(!!sym(subreddit_col), score_medio), y = score_medio, fill = score_medio)) +
        geom_col(alpha = 0.8, show.legend = FALSE, color = "black", linewidth = 0.3) +
        coord_flip() +
        scale_fill_gradient2(low = "blue", mid = "white", high = "red", midpoint = 0) +
        geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
        labs(
          title = "Score Left-Right Promedio por Subreddit",
          x = "Subreddit",
          y = "Score Promedio"
        ) +
        theme_ideologia(legend.pos = "none")
      
      print(fig11)
      save_fig(fig11, "11_scores_por_subreddit.png")
      write_csv(scores_subreddit, file.path(OUT_DIR, "11_scores_por_subreddit.csv"))
    }
  }
}

# =============================================================
# 8) RESUMEN ESTADÍSTICO COMPLETO
# =============================================================
cat("\n📊 Generando resumen estadístico completo...\n")

resumen <- list()

# Estadísticas básicas
resumen$n_total <- nrow(df)
resumen$n_con_score <- sum(!is.na(df$left_right_score))
resumen$n_con_label <- sum(!is.na(df$left_right_label))
resumen$n_con_confidence <- sum(!is.na(df$confidence))

# Estadísticas de scores
if ("left_right_score" %in% names(df)) {
  scores <- df$left_right_score[!is.na(df$left_right_score)]
  if (length(scores) > 0) {
    resumen$score_media <- mean(scores)
    resumen$score_mediana <- median(scores)
    resumen$score_sd <- sd(scores)
    resumen$score_min <- min(scores)
    resumen$score_max <- max(scores)
    resumen$score_q25 <- quantile(scores, 0.25)
    resumen$score_q75 <- quantile(scores, 0.75)
    resumen$pct_left <- sum(scores < 0) / length(scores) * 100
    resumen$pct_right <- sum(scores > 0) / length(scores) * 100
    resumen$pct_center <- sum(scores == 0) / length(scores) * 100
  }
}

# Estadísticas de confidence
if ("confidence" %in% names(df)) {
  conf <- df$confidence[!is.na(df$confidence)]
  if (length(conf) > 0) {
    resumen$confidence_media <- mean(conf)
    resumen$confidence_mediana <- median(conf)
    resumen$confidence_alta_pct <- sum(conf >= 0.7) / length(conf) * 100
    resumen$confidence_media_pct <- sum(conf >= 0.5 & conf < 0.7) / length(conf) * 100
    resumen$confidence_baja_pct <- sum(conf < 0.5) / length(conf) * 100
  }
}

# Distribución de labels
if ("left_right_label" %in% names(df)) {
  resumen$distribucion_labels <- df %>%
    filter(!is.na(left_right_label)) %>%
    count(left_right_label, sort = TRUE) %>%
    mutate(pct = n / sum(n) * 100)
}

# Guardar resumen
write_csv(as_tibble(resumen[!sapply(resumen, is.data.frame)]), 
          file.path(OUT_DIR, "resumen_estadistico.csv"))

if (!is.null(resumen$distribucion_labels)) {
  write_csv(resumen$distribucion_labels, 
            file.path(OUT_DIR, "resumen_distribucion_labels.csv"))
}

# Imprimir resumen
cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("📊 RESUMEN ESTADÍSTICO\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat(sprintf("Total comentarios: %d\n", resumen$n_total))
cat(sprintf("Con score: %d (%.1f%%)\n", resumen$n_con_score, 
            resumen$n_con_score / resumen$n_total * 100))
cat(sprintf("Con label: %d (%.1f%%)\n", resumen$n_con_label,
            resumen$n_con_label / resumen$n_total * 100))
if (!is.null(resumen$score_media)) {
  cat(sprintf("\nScore Left-Right:\n"))
  cat(sprintf("  Media: %.3f\n", resumen$score_media))
  cat(sprintf("  Mediana: %.3f\n", resumen$score_mediana))
  cat(sprintf("  SD: %.3f\n", resumen$score_sd))
  cat(sprintf("  Rango: [%.3f, %.3f]\n", resumen$score_min, resumen$score_max))
  cat(sprintf("  Left (<0): %.1f%%\n", resumen$pct_left))
  cat(sprintf("  Center (=0): %.1f%%\n", resumen$pct_center))
  cat(sprintf("  Right (>0): %.1f%%\n", resumen$pct_right))
}

cat("\n", paste0(rep("=", 70), collapse = ""), "\n")
cat("✅ ANÁLISIS COMPLETADO\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat(sprintf("\n💾 Resultados guardados en: %s\n", OUT_DIR))
cat(sprintf("📊 Total de figuras generadas: %d\n", length(list.files(OUT_DIR, pattern = "\\.png$"))))
