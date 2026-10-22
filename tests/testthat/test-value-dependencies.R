# Issue #21: a project function passed as a value, like passing helper into
# lapply, is a real dependency. A bare argument naming a top-level project
# function and not shadowed locally resolves distinctly as value and counts in
# must_not_depend_on constraints, while shadowed names, base functions such as
# sum passed by value, and dynamic name lookups stay out of the graph.

test_that("a value-passed project function is a dependency violation", {
  result <- arch_check(
    rule("plot does not depend on db") |>
      modules_matching("R/plot.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = fixture("pkg_values")
  )

  expect_equal(nrow(result$violations), 3L)
  expect_equal(result$violations$line, c(2L, 3L, 4L))
  expect_true(all(result$violations$owner == "R/db.R"))
  expect_true(all(result$violations$resolved_by == "value"))
  expect_equal(result$violations$enclosing_function, rep("plot_all", 3L))
  expect_equal(result$counts$unresolved, 0L)
})

test_that("value violations point at the argument position", {
  result <- arch_check(
    rule("plot does not depend on db") |>
      modules_matching("R/plot.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = fixture("pkg_values")
  )

  expect_equal(
    result$violations$source_text,
    c(
      "lapply(cons, load_sales)",
      "purrr::map(cons, load_sales)",
      "Reduce(load_sales, cons)"
    )
  )
})

test_that("a value edge is not a call and must_not_call ignores it", {
  result <- arch_check(
    rule("plot must not call load_sales") |>
      modules_matching("R/plot.R") |>
      must_not_call(functions = "load_sales"),
    root = fixture("pkg_values")
  )

  expect_equal(nrow(result$violations), 0L)
})

test_that("formals() and Filter() pass values, lapply(x, sum) does not", {
  result <- arch_check(
    rule("ops does not depend on db") |>
      modules_matching("R/ops.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = fixture("pkg_values")
  )

  expect_equal(nrow(result$violations), 2L)
  expect_equal(result$violations$callee, rep("load_sales", 2L))
  expect_equal(result$violations$line, c(2L, 3L))
  expect_false(any(result$violations$callee == "sum"))
  expect_equal(
    result$violations$source_text,
    c("formals(load_sales)", "Filter(load_sales, n)")
  )
})

test_that("a bare assignment keeps the value out of the graph", {
  result <- arch_check(
    rule("ops does not depend on db") |>
      modules_matching("R/ops.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = fixture("pkg_values")
  )

  # The final top-level line anchors to no call, so the bare helper there
  # produces no value edge.
  expect_false(any(result$violations$line == 8L))
})

test_that("a local shadowing binding keeps the value out of the graph", {
  result <- arch_check(
    rule("shadow does not depend on db") |>
      modules_matching("R/shadow.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = fixture("pkg_values")
  )

  expect_equal(nrow(result$violations), 0L)
})

test_that("a named argument value is also a value edge", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  writeLines("load_sales <- function(con) 1", file.path(root, "R", "db.R"))
  writeLines(
    c(
      "run_switch <- function(type) {",
      "  switch(type, pass = load_sales)",
      "  do.call(\"load_sales\", list())",
      "  match.fun(\"load_sales\")",
      "  get(\"load_sales\")",
      "}"
    ),
    file.path(root, "R", "edge.R")
  )

  result <- arch_check(
    rule("edge does not depend on db") |>
      modules_matching("R/edge.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = root
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$callee, "load_sales")
  expect_equal(result$violations$line, 2L)
  expect_equal(result$violations$source_text, "switch(type, pass = load_sales)")
})

test_that("backticked and quoted symbol uses match shadows and definitions", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  writeLines(
    c(
      "load_sales <- function(con) 1",
      "`load.sales.alt` <- function(x) 2"
    ),
    file.path(root, "R", "db.R")
  )
  writeLines(
    c(
      "bt_probe <- function(x) {",
      "  k <- lapply(x, `load.sales.alt`)",
      "  p <- sapply(x, `load_sales`)",
      "  list(k, p)",
      "}"
    ),
    file.path(root, "R", "bt.R")
  )

  result <- arch_check(
    rule("backtick does not depend on db") |>
      modules_matching("R/bt.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = root
  )

  expect_equal(nrow(result$violations), 2L)
  expect_equal(
    sort(result$violations$callee),
    sort(c("load.sales.alt", "load_sales"))
  )
  expect_true(all(result$violations$resolved_by == "value"))
  expect_equal(
    sort(result$violations$source_text),
    sort(c("lapply(x, `load.sales.alt`)", "sapply(x, `load_sales`)"))
  )
})

test_that("member reads and lambda bodies keep the value out", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  writeLines("load_sales <- function(con) 1", file.path(root, "R", "db.R"))
  writeLines(
    c(
      "mem_probe <- function(obj) {",
      "  d <- invisible(obj$load_sales)",
      "  d",
      "}",
      "lam_probe <- function(x) {",
      "  k <- lapply(x, function(y) load_sales)",
      "  k",
      "}"
    ),
    file.path(root, "R", "parts.R")
  )

  result <- arch_check(
    rule("parts does not depend on db") |>
      modules_matching("R/parts.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = root
  )

  expect_equal(nrow(result$violations), 0L)
})

test_that("a formula body inside a call argument is a value use", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  writeLines("load_sales <- function(con) 1", file.path(root, "R", "db.R"))
  writeLines(
    "frm_probe <- function(x) purrr::map(x, ~ .x + load_sales)",
    file.path(root, "R", "frm.R")
  )

  result <- arch_check(
    rule("frm does not depend on db") |>
      modules_matching("R/frm.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = root
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$callee, "load_sales")
  expect_true(all(result$violations$resolved_by == "value"))
  expect_equal(
    result$violations$source_text,
    "purrr::map(x, ~ .x + load_sales)"
  )
})

test_that("without a shadowing binding the value edge appears", {
  result <- arch_check(
    rule("direct does not depend on db") |>
      modules_matching("R/direct.R") |>
      must_not_depend_on(modules = "R/db.R"),
    root = fixture("pkg_values")
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$line, 2L)
  expect_equal(result$violations$callee, "helper")
  expect_equal(result$violations$owner, "R/db.R")
  expect_equal(result$violations$resolved_by, "value")
  expect_equal(result$violations$source_text, "lapply(x, helper)")
})
