assert_defaults <- function(what, n) {
  f <- formals(load_sales)
  g <- Filter(load_sales, n)
  h <- lapply(what, sum)
  h
}
default_handler <- helper
