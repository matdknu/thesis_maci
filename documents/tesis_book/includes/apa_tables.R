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
#' @param df data.frame
#' @param caption Título completo (oración clara, punto final recomendado)
#' @param note Texto opcional bajo la tabla (Nota.)
#' @param align Vector align para kable o NULL
#' @param col.names Nombres de columnas mostrados (reemplaza names(df))
kable_apa <- function(df, caption, note = NULL, align = NULL, col.names = NULL) {
  df <- as.data.frame(df)
  if (!is.null(col.names)) colnames(df) <- col.names
  k <- knitr::kable(df, caption = caption, booktabs = TRUE, align = align)
  if (isTRUE(requireNamespace("kableExtra", quietly = TRUE))) {
    k <- kableExtra::kable_styling(
      k,
      bootstrap_options = c("striped", "hover", "condensed"),
      latex_options = c("striped", "hold_position"),
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
  }
  k
}

#' Alias semántico para el cuerpo de la tesis
tabla_apa <- function(...) kable_apa(...)
