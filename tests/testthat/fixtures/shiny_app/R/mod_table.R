mod_table_server <- function(id) {
  file_ext(id)
}

mod_table_label <- function(id) {
  decorate(id)
}

decorate <- function(id) {
  paste0("[", id, "]")
}
