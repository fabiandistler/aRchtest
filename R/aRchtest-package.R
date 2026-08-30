#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom data.table data.table
#' @importFrom data.table rbindlist
#' @importFrom data.table setattr
#' @importFrom data.table setorderv
## usethis namespace: end
NULL

utils::globalVariables(c(
  "rule", "file", "line", "column", "enclosing_function", "callee",
  "owner", "resolved_by", "internal", "source_text", "candidates"
))
