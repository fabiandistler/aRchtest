fixture <- function(name) {
  normalizePath(test_path("fixtures", name), winslash = "/", mustWork = TRUE)
}

ui_rule <- function(...) {
  rule("UI must not use tools", ...) |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = "tools")
}
