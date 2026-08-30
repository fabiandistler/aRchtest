test_that("arch_expect() passes on a clean project", {
  expect_success(arch_expect(ui_rule(), root = fixture("pkg_clean")))
})

test_that("arch_expect() fails when a rule is violated", {
  expect_failure(arch_expect(ui_rule(), root = fixture("pkg_layered")))
})

test_that("arch_expect() fails when a selector matches nothing", {
  expect_failure(
    arch_expect(
      rule("typo") |>
        modules_matching("R/nope_*.R") |>
        must_not_call(packages = "tools"),
      root = fixture("pkg_layered")
    ),
    "EMPTY SELECTION"
  )
})

test_that("the failure message names rule, rationale and findings", {
  expect_failure(
    arch_expect(
      ui_rule(why = "Presentation stays thin"),
      root = fixture("pkg_layered")
    ),
    "UI must not use tools"
  )
  expect_failure(
    arch_expect(
      ui_rule(why = "Presentation stays thin"),
      root = fixture("pkg_layered")
    ),
    "Presentation stays thin"
  )
  expect_failure(
    arch_expect(ui_rule(), root = fixture("pkg_layered")),
    "R/ui_dashboard.R:2:3"
  )
  expect_failure(
    arch_expect(ui_rule(), root = fixture("pkg_layered")),
    "render_table()",
    fixed = TRUE
  )
  expect_failure(
    arch_expect(ui_rule(), root = fixture("pkg_layered")),
    "tools::file_ext(rows$path)",
    fixed = TRUE
  )
})

test_that("arch_expect() returns the result invisibly", {
  result <- expect_invisible(
    arch_expect(ui_rule(), root = fixture("pkg_clean"))
  )

  expect_s3_class(result, "arch_result")
})

test_that("arch_expect() reports every rule of a rule set in one message", {
  failing <- list(
    ui_rule(),
    rule("domain must not reach infrastructure") |>
      modules_matching("R/domain_*.R") |>
      must_not_depend_on(modules = "R/infra_*.R")
  )

  expect_failure(
    arch_expect(failing, root = fixture("pkg_layered")),
    "UI must not use tools"
  )
  expect_failure(
    arch_expect(failing, root = fixture("pkg_layered")),
    "domain must not reach infrastructure"
  )
  expect_failure(
    arch_expect(failing, root = fixture("pkg_layered")),
    "store_lookup"
  )
})

test_that("a passing rule in a failing set is still accounted for", {
  mixed <- list(
    ui_rule(),
    rule("domain must not use Matrix") |>
      modules_matching("R/domain_*.R") |>
      must_not_call(packages = "Matrix")
  )

  expect_failure(
    arch_expect(mixed, root = fixture("pkg_layered")),
    "Passing rule\\(s\\): domain must not use Matrix"
  )
})

test_that("the failure message carries the resolution counts", {
  expect_failure(
    arch_expect(ui_rule(), root = fixture("pkg_layered")),
    "call site\\(s\\) resolved"
  )
})
