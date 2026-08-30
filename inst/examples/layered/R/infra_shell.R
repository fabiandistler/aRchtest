store_archive <- function(path) {
  system(paste("tar -czf", path))
}
