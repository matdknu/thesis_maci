# Tablas estilo APA para la tesis (Quarto book)
# knitr::kable + kableExtra: compatible HTML y PDF (booktabs, nota al pie)

round_df <- function(df, digits = 3) {
  if (!nrow(df)) return(df)
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  for (cn in num_cols) df[[cn]] <- round(df[[cn]], digits)
  df
}

read_or_empty <- function(path) {
  if (file.exists(path)) read.csv(path, stringsAsFactors = FALSE) else data.frame()
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
  paste0(vn, ": ", lev)
}

#' Tabla principal: booktabs + nota al pie tipo APA
#' @param landscape Si TRUE (p. ej. en PDF), página horizontal con pdflscape (tablas anchas).
#' @param scale_down Si TRUE (LaTeX), escala la tabla al ancho de línea (alternativa a landscape).
kable_apa <- function(
    df,
    caption,
    note = NULL,
    align = NULL,
    col.names = NULL,
    landscape = FALSE,
    scale_down = FALSE
) {
  df <- as.data.frame(df)
  if (!is.null(col.names)) colnames(df) <- col.names
  k <- knitr::kable(df, caption = caption, booktabs = TRUE, align = align)
  if (isTRUE(requireNamespace("kableExtra", quietly = TRUE))) {
    latex_opts <- c("striped", "hold_position")
    if (isTRUE(scale_down)) latex_opts <- c(latex_opts, "scale_down")
    k <- kableExtra::kable_styling(
      k,
      bootstrap_options = c("striped", "hover", "condensed"),
      latex_options = latex_opts,
      full_width = FALSE
    )
    if (length(note) && nzchar(note)) {
      k <- kableExtra::footnote(
        k,
        general = note,
        general_title = "Nota.",
        footnote_as_chunk = TRUE
      )
    }
    if (isTRUE(landscape) && isTRUE(knitr::is_latex_output())) {
      k <- kableExtra::landscape(k)
    }
  }
  k
}

#' Tablas del anexo: en PDF se fuerza página horizontal para evitar desbordes.
kable_apa_anexo <- function(...) {
  kable_apa(..., landscape = knitr::is_latex_output(), scale_down = FALSE)
}

#' Alias semántico para el cuerpo de la tesis
tabla_apa <- function(...) kable_apa(...)
