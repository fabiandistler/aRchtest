test_that("a project with no DESCRIPTION is analysed without error", {
  result <- arch_check(
    rule("modules must not use tools") |>
      modules_matching("R/mod_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("shiny_app")
  )

  expect_false(result$is_package)
  expect_s3_class(result, "arch_result")
})

test_that("library() calls supply the declared dependencies", {
  result <- arch_check(
    rule("modules must not use tools") |>
      modules_matching("R/mod_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("shiny_app")
  )

  expect_equal(result$declared_dependencies, c("tools", "utils"))
  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$file, "R/mod_table.R")
  expect_equal(result$violations$line, 2L)
  expect_equal(result$violations$callee, "file_ext")
  expect_equal(result$violations$owner, "tools")
  expect_equal(result$violations$resolved_by, "export")
})

test_that("local definitions still win in a non-package project", {
  result <- arch_check(
    rule("modules must not use tools") |>
      modules_matching("R/mod_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("shiny_app")
  )

  expect_false(any(result$violations$callee == "decorate"))
})

test_that("resolution coverage is reported for non-package projects", {
  result <- arch_check(
    rule("modules must not use tools") |>
      modules_matching("R/mod_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("shiny_app")
  )

  expect_gt(result$counts$call_sites, 0L)
  expect_equal(
    result$counts$resolved + result$counts$ambiguous + result$counts$unresolved,
    result$counts$call_sites
  )
  expect_gte(result$counts$unresolved, 1L)
})

test_that("the character-string form of require() is recognised", {
  result <- arch_check(
    rule("routes stay thin") |>
      modules_matching("plumber.R") |>
      must_not_call(packages = "tools"),
    root = fixture("plumber_api")
  )

  expect_equal(result$declared_dependencies, "tools")
  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$line, 5L)
  expect_equal(result$violations$enclosing_function, "route_reports")
})

test_that("a plumber route handler can be held away from infrastructure", {
  result <- arch_check(
    rule("routes must not touch the store",
      why = "The API surface stays thin"
    ) |>
      modules_matching("plumber.R") |>
      must_not_depend_on(modules = "R/infra_*.R"),
    root = fixture("plumber_api")
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$callee, "store_lookup")
  expect_equal(result$violations$owner, "R/infra_store.R")
  expect_equal(result$violations$enclosing_function, "route_raw")
})
