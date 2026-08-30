banner <- tools::file_ext("report.md")

render_report <- function(x) {
  helper <- function(y) {
    tools:::.hidden_helper(y)
  }
  helper(x)
}

describe <- function() {
  "tools::file_ext never runs"
}

annotate <- function() {
  # tools::file_ext in a comment
  NULL
}
