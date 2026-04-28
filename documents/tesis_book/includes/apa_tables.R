# Tablas estilo APA para la tesis (Quarto book)
# knitr::kable + kableExtra: compatible HTML y PDF (booktabs, nota al pie)

round_df <- function(df, digits = 3) {
  if (!nrow(df)) return(df)
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  for (cn in num_cols) df[[cn]] <- round(df[[cn]], digits)
  df
}

pretty_dim_label <- function(x) {
  recode <- c(
    polarizacion = "Polarización",
    marco = "Marco",
    emocion = "Emoción",
    estrategia = "Estrategia",
    frontera = "Frontera"
  )
  x <- as.character(x)
  ifelse(x %in% names(recode), unname(recode[x]), x)
}

pretty_metric_label <- function(x) {
  recode <- c(
    correlacion_pearson = "Pearson r",
    kappa = "Kappa"
  )
  x <- as.character(x)
  ifelse(x %in% names(recode), unname(recode[x]), x)
}

read_or_empty <- function(path) {
  if (file.exists(path)) read.csv(path, stringsAsFactors = FALSE) else data.frame()
}

#' En salida LaTeX, los guiones bajos en títulos/notas de tabla activan subíndices
#' ("Missing $ inserted"). Escapa como \\_ fuera de modo matemático.
latex_escape_underscores <- function(text) {
  if (!length(text)) {
    return(text)
  }
  if (!isTRUE(knitr::is_latex_output())) {
    return(text)
  }
  vapply(
    as.character(text),
    function(x) {
      if (!nzchar(x)) {
        return(x)
      }
      gsub("_", "\\_", x, fixed = TRUE)
    },
    character(1),
    USE.NAMES = FALSE
  )
}

# Pandas/CSV: TRUE/FALSE como texto; o 0/1 desde scripts Python
as_signif_05 <- function(x) {
  if (is.logical(x)) return(x)
  xc <- tolower(trimws(as.character(x)))
  num <- suppressWarnings(as.numeric(xc))
  (!is.na(num) & num == 1) | xc %in% c("true", "t", "yes")
}

format_p_apa <- function(p) {
  p <- suppressWarnings(as.numeric(p))
  vapply(seq_along(p), function(i) {
    if (length(p) < i || is.na(p[i])) return("")
    if (p[i] < 0.001) return("< .001")
    format(round(p[i], 3), nsmall = 3, trim = TRUE)
  }, character(1))
}

pretty_ols_term <- function(x) {
  x0 <- gsub("^\"|\"$", "", as.character(x))
  if (x0 == "Intercept") return("Intercepto")
  if (x0 == "comment_score_c") return("Karma (puntuación, centrado)")
  if (!grepl("^C\\(", x0)) return(x0)
  vn <- sub("^C\\(([^,]+),.*", "\\1", x0)
  lev <- sub(".*\\[T\\.([^]]+)\\].*", "\\1", x0)
  if (identical(lev, x0)) return(x0)

  vn_map <- c(
    marco_final = "Marco",
    emocion_final = "Emoción",
    estrategia_final = "Estrategia",
    frontera_final = "Frontera",
    candidato = "Candidato objetivo",
    fase = "Fase",
    tipo_hilo = "Tipo de hilo"
  )
  lev_map <- c(
    conflicto = "conflicto",
    diagnostico = "diagnóstico",
    economico = "económico",
    identitario = "identitario",
    moral = "moral",
    motivacional = "motivacional",
    pronostico = "pronóstico",
    alegria = "alegría",
    desprecio = "desprecio",
    esperanza = "esperanza",
    indignacion = "indignación",
    ira = "ira",
    ironia = "ironía",
    miedo = "miedo",
    atribucion_oculta = "atribución oculta",
    construccion_amenaza = "construcción de amenaza",
    deslegitimacion = "deslegitimación",
    esencializacion = "esencialización",
    ridiculizacion = "ridiculización",
    inter_bloque = "inter-bloque",
    intra_bloque = "intra-bloque",
    jara = "Jara",
    kaiser = "Kaiser",
    kast = "Kast",
    primera_vuelta = "primera vuelta",
    segunda_vuelta = "segunda vuelta",
    mixto = "mixto",
    solo_derecha = "solo derecha",
    solo_derecha_multiple = "solo derecha múltiple",
    ERROR = "error"
  )

  vn_lbl <- if (!is.na(vn_map[vn])) unname(vn_map[vn]) else vn
  lev_lbl <- if (!is.na(lev_map[lev])) unname(lev_map[lev]) else lev
  paste(vn_lbl, lev_lbl, sep = ": ")
}

#' Tabla principal: booktabs (sin nota al pie: en PDF con Quarto, kableExtra::footnote
#' rompe el float y puede mostrar artefactos como "[!h]" o desalinear columnas).
#' @param landscape Si TRUE (p. ej. en PDF), página horizontal con pdflscape (tablas anchas).
#' @param scale_down Si TRUE (LaTeX), escala la tabla al ancho de línea. No se combina con
#'   longtable: kableExtra ante scale_down + longtable termina envolviendo en landscape.
#' @param longtable Si FALSE, evita particionar tablas entre páginas en PDF.
#'   Recomendado para mantener formato APA consistente.
#' @param note Ignorado (reservado por compatibilidad; no se renderiza).
kable_apa <- function(
    df,
    caption,
    note = NULL,
    align = NULL,
    col.names = NULL,
    landscape = FALSE,
    scale_down = FALSE,
    longtable = NULL,
    max_rows_longtable = 45L
) {
  df <- as.data.frame(df)
  chunk_label <- tryCatch(knitr::opts_current$get("label"), error = function(e) NULL)
  # En tablas del anexo con label tbl-anexo-*, Quarto genera el float/caption
  # externo. Evitamos una caption interna duplicada (que crea entradas vacías en LoT).
  if (isTRUE(knitr::is_latex_output()) &&
      !is.null(chunk_label) &&
      startsWith(as.character(chunk_label), "tbl-anexo-")) {
    caption <- NULL
  }
  if (!is.null(col.names)) colnames(df) <- col.names
  if (is.null(align)) {
    align <- paste(ifelse(vapply(df, is.numeric, logical(1)), "r", "l"), collapse = "")
  }
  if (is.null(longtable)) {
    # En esta tesis se prioriza que cada tabla quede completa en una sola página.
    # Evita cortes internos entre páginas (longtable) y fuerza tabular.
    longtable <- FALSE
  }
  caption <- latex_escape_underscores(caption)
  # kableExtra: scale_down sobre longtable dispara aviso y puede envolver en landscape en el PDF.
  # Si piden scale_down en LaTeX, forzar tabular (sin longtable).
  if (isTRUE(scale_down) && isTRUE(knitr::is_latex_output())) {
    longtable <- FALSE
  }
  # Sin format explícito, knitr/kableExtra a veces emiten longtable aunque longtable=FALSE.
  fmt <- if (isTRUE(knitr::is_latex_output())) {
    "latex"
  } else if (isTRUE(knitr::is_html_output())) {
    "html"
  } else {
    NULL
  }
  k <- knitr::kable(
    df,
    format = fmt,
    caption = caption,
    booktabs = TRUE,
    align = align,
    row.names = FALSE,
    longtable = longtable
  )
  if (isTRUE(requireNamespace("kableExtra", quietly = TRUE))) {
    # Sin "hold_position": con Quarto + entorno table de crossref, kableExtra
    # puede dejar "[!h]" como texto visible en el PDF (fragmento fuera de \begin{table}[!h]).
    # Estilo APA limpio y homogéneo: sin franjas grises ni sombreado.
    latex_opts <- c()
    if (isTRUE(scale_down) && isTRUE(knitr::is_latex_output()) && !isTRUE(longtable)) {
      latex_opts <- c("scale_down")
    }
    ksty <- list(
      k,
      bootstrap_options = c("condensed"),
      latex_options = latex_opts,
      full_width = FALSE
    )
    if (isTRUE(scale_down) && isTRUE(knitr::is_latex_output()) && isTRUE(longtable)) {
      ksty$font_size <- 8
    }
    k <- do.call(kableExtra::kable_styling, ksty)
    if (isTRUE(landscape) && isTRUE(knitr::is_latex_output())) {
      k <- kableExtra::landscape(k)
    }
  }
  k
}

#' Tablas del anexo: siempre vertical (retrato); en PDF se escala si hace falta.
kable_apa_anexo <- function(...) {
  kable_apa(
    ...,
    landscape = FALSE,
    scale_down = knitr::is_latex_output()
  )
}

#' Alias semántico para el cuerpo de la tesis
tabla_apa <- function(...) kable_apa(...)
