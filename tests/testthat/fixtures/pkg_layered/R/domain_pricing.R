toTitleCase <- function(text) {
  paste0(toupper(substr(text, 1, 1)), substring(text, 2))
}

apply_discount <- function(amount, rate) {
  store_lookup(amount) * rate
}

shell_out <- function() {
  system("ls")
}

mystery <- function(x) {
  frobnicate(x)
}

self_contained <- function(text) {
  toTitleCase(text)
}
