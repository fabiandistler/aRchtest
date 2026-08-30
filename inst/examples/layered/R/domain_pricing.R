apply_discount <- function(amount, rate) {
  amount - round_money(amount * rate)
}

round_money <- function(amount) {
  round(amount, 2)
}
