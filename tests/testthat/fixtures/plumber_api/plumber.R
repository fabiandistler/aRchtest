require("tools")

#* @get /reports
route_reports <- function(path) {
  file_ext(path)
}

#* @get /raw
route_raw <- function(key) {
  store_lookup(key)
}

#* @get /health
route_health <- function() {
  "ok"
}
