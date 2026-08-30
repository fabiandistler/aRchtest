test_that("an unqualified call to a forbidden base function is a violation", {
  result <- arch_check(
    rule("no shelling out", why = "Nothing here may touch the shell") |>
      modules_matching("R/domain_*.R") |>
      must_not_call(functions = "system"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$file, "R/domain_pricing.R")
  expect_equal(result$violations$line, 10L)
  expect_equal(result$violations$enclosing_function, "shell_out")
  expect_equal(result$violations$callee, "system")
  expect_equal(result$violations$owner, "base")
  expect_equal(result$violations$resolved_by, "base")
})

test_that("a namespace-qualified call to a forbidden function is a violation", {
  result <- arch_check(
    rule("no file extensions") |>
      modules_matching("R/ui_*.R") |>
      must_not_call(functions = "tools::file_ext"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 3L)
  expect_true(all(result$violations$owner == "tools"))
  expect_setequal(
    result$violations$resolved_by, c("namespace", "export")
  )
})

test_that("a bare function name matches whoever owns it", {
  result <- arch_check(
    rule("no file extensions") |>
      modules_matching("R/ui_*.R") |>
      must_not_call(functions = "file_ext"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 3L)
  expect_setequal(result$violations$line, c(2L, 6L, 1L))
})

test_that("a local function shadowing a forbidden name is not a violation", {
  result <- arch_check(
    rule("no title casing") |>
      modules_matching("R/ui_*.R") |>
      must_not_call(functions = "toTitleCase"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 0L)
})

test_that("forbidding one function leaves the rest of its package alone", {
  result <- arch_check(
    rule("no shelling out") |>
      modules_matching("R/domain_*.R") |>
      must_not_call(functions = "system"),
    root = fixture("pkg_layered")
  )

  expect_false(
    any(result$violations$callee %in% c("paste0", "toupper", "substr"))
  )
  expect_equal(nrow(result$violations), 1L)
})

test_that("functions and packages can be forbidden by the same constraint", {
  result <- arch_check(
    rule("ui is constrained") |>
      modules_matching("R/ui_*.R") |>
      must_not_call(packages = "tools", functions = "system"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 4L)
})

test_that("an unresolved call is never a violation of a function rule", {
  result <- arch_check(
    rule("no frobnicating") |>
      modules_matching("R/domain_*.R") |>
      must_not_call(functions = "frobnicate"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 0L)
  expect_gte(result$counts$unresolved, 1L)
})
