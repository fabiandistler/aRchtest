test_that("a call into a forbidden module is a violation naming that module", {
  result <- arch_check(
    rule("domain must not reach infrastructure") |>
      modules_matching("R/domain_*.R") |>
      must_not_depend_on(modules = "R/infra_*.R"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$file, "R/domain_pricing.R")
  expect_equal(result$violations$line, 6L)
  expect_equal(result$violations$enclosing_function, "apply_discount")
  expect_equal(result$violations$callee, "store_lookup")
  expect_equal(result$violations$owner, "R/infra_store.R")
  expect_equal(result$violations$resolved_by, "local")
  expect_equal(result$violations$source_text, "store_lookup(amount)")
})

test_that("a call to a module that is neither selected nor forbidden is fine", {
  result <- arch_check(
    rule("ui must not reach infrastructure") |>
      modules_matching("R/ui_*.R") |>
      must_not_depend_on(modules = "R/infra_*.R"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 0L)
})

test_that("a module calling a function it defines itself is not a violation", {
  result <- arch_check(
    rule("domain must not depend on domain") |>
      modules_matching("R/domain_*.R") |>
      must_not_depend_on(modules = "R/domain_*.R"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 0L)
})

test_that("the constraint works on unqualified calls with no :: required", {
  result <- arch_check(
    rule("domain must not reach infrastructure") |>
      modules_matching("R/domain_*.R") |>
      must_not_depend_on(modules = "R/infra_*.R"),
    root = fixture("pkg_layered")
  )

  expect_false(grepl("::", result$violations$callee, fixed = TRUE))
})

test_that("forbidden modules can be named with a regular expression", {
  result <- arch_check(
    rule("domain must not reach infrastructure") |>
      modules_matching("R/domain_*.R") |>
      must_not_depend_on(modules = "^R/infra_.*\\.R$", regex = TRUE),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$owner, "R/infra_store.R")
})

test_that("one rule can carry both constraints and report findings from each", {
  result <- arch_check(
    rule("domain is isolated") |>
      modules_matching("R/domain_*.R") |>
      must_not_call(functions = "system") |>
      must_not_depend_on(modules = "R/infra_*.R"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 2L)
  expect_setequal(result$violations$callee, c("store_lookup", "system"))
  expect_setequal(result$violations$owner, c("R/infra_store.R", "base"))
})
