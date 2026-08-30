render_summary <- function(sales) {
  midpoint <- stats::median(sales$amount)
  paste0("Median sale: ", midpoint)
}

render_header <- function(title) {
  toupper(title)
}
