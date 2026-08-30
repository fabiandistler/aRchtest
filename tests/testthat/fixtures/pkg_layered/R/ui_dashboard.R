render_table <- function(rows) {
  tools::file_ext(rows$path)
}

render_footer <- function(rows) {
  file_ext(rows$path)
}

render_title <- function(text) {
  toTitleCase(text)
}
