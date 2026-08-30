store_write <- function(path, value) {
  saveRDS(value, path)
}

store_read <- function(path) {
  readRDS(path)
}
