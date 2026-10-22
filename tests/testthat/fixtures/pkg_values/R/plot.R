plot_all <- function(cons) {
  a <- lapply(cons, load_sales)
  b <- purrr::map(cons, load_sales)
  c <- Reduce(load_sales, cons)
  a
}
