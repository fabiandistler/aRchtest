store_lookup <- function(key) {
  readRDS(key)
}

store_write <- function(key, value) {
  saveRDS(value, key)
}
