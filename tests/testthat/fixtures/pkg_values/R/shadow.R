analyze_records <- function(x) {
  helper <- function() 1
  lapply(x, helper)
}
