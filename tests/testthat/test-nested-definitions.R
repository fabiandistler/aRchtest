# Issue #20: nested function definitions must not enter the project-wide
# definition index, so a bare base name like `all` defined inside one module
# stops shadowing base::all across the whole project. Nested definitions stay
# known for attribution, so calls inside their enclosing function remain
# local. When two files define the same top-level name, the resolution
# follows R's collation order: the last collated file wins.

test_that("a nested definition does not become a cross-file dependency", {
  result <- arch_check(
    rule("rd does not depend on build") |>
      modules_matching("R/rd.R") |>
      must_not_depend_on(modules = "R/build.R"),
    root = fixture("pkg_nested")
  )

  expect_equal(nrow(result$violations), 0L)
  expect_equal(result$counts$unresolved, 0L)
})

test_that("a base call shadowed in another module resolves to base again", {
  result <- arch_check(
    rule("no bare all in rd") |>
      modules_matching("R/rd.R") |>
      must_not_call(functions = "all"),
    root = fixture("pkg_nested")
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$callee, "all")
  expect_equal(result$violations$owner, "base")
  expect_equal(result$violations$resolved_by, "base")
  expect_equal(result$violations$enclosing_function, "rd_check")
})

test_that("a call to a nested helper stays local to its enclosing function", {
  result <- arch_check(
    rule("build owns its nested helper") |>
      modules_matching("R/build.R") |>
      must_not_call(functions = "all"),
    root = fixture("pkg_nested")
  )

  expect_equal(nrow(result$violations), 0L)
  expect_equal(result$counts$unresolved, 0L)
})

test_that("a conditionally guarded definition does not claim project scope", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  writeLines(
    c("if (interactive()) {", "  maybe_loaded <- function() 1", "}"),
    file.path(root, "R", "maybe.R")
  )
  writeLines(
    "run_maybe <- function() maybe_loaded()",
    file.path(root, "R", "user.R")
  )

  result <- arch_check(
    rule("user must not depend on maybe") |>
      modules_matching("R/user.R") |>
      must_not_depend_on(modules = "R/maybe.R"),
    root = root
  )

  expect_equal(nrow(result$violations), 0L)
  expect_gte(result$counts$unresolved, 1L)
})

test_that("the collation-last definition of a repeated name owns the calls", {
  result <- arch_check(
    rule("user must not depend on omega") |>
      modules_matching("R/user.R") |>
      must_not_depend_on(modules = "R/z_omega.R"),
    root = fixture("pkg_collate")
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$callee, "shared")
  expect_equal(result$violations$owner, "R/z_omega.R")
  expect_equal(result$violations$resolved_by, "local")
})

test_that("a module attributing its own repeated name stays attributable", {
  result <- arch_check(
    rule("alpha holds its own definition") |>
      modules_matching("R/a_alpha.R") |>
      must_not_depend_on(modules = "R/z_omega.R"),
    root = fixture("pkg_collate")
  )

  expect_equal(nrow(result$violations), 0L)
})
