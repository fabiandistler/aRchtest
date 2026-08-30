#' Enforce architectural rules as a testthat expectation
#'
#' `arch_expect()` runs [arch_check()] and turns the result into a `testthat`
#' expectation, so an architectural agreement is enforced by the tooling you
#' already run rather than by a new command to remember.
#'
#' The expectation fails when any rule found a violation, and also when a rule's
#' selector matched no file at all -- a vacuously green architecture test is
#' worse than no test. The failure message names each failing rule, its
#' rationale if one was given, and every finding with its file, line, enclosing
#' function, callee and source text, so a CI log is enough to act on without
#' opening the code.
#'
#' @inheritParams arch_check
#'
#' @return The `arch_result`, invisibly.
#' @export
#'
#' @examples
#' project <- system.file("examples", "layered", package = "aRchtest")
#'
#' if (requireNamespace("testthat", quietly = TRUE)) {
#'   testthat::test_that("domain stays free of infrastructure", {
#'     rule("domain must not reach infrastructure",
#'       why = "Domain logic has to be testable without a store"
#'     ) |>
#'       modules_matching("R/domain_*.R") |>
#'       must_not_depend_on(modules = "R/infra_*.R") |>
#'       arch_expect(root = project)
#'   })
#' }
arch_expect <- function(rules, root = ".", on_ambiguous = c("report", "fail")) {
  if (!requireNamespace("testthat", quietly = TRUE)) {
    stop(
      "arch_expect() needs the testthat package. ",
      "Use arch_check() for a structured result without testthat.",
      call. = FALSE
    )
  }

  result <- arch_check(rules, root = root, on_ambiguous = on_ambiguous)
  testthat::expect(
    arch_ok(result),
    paste(arch_failure_message(result), collapse = "\n")
  )
  invisible(result)
}
