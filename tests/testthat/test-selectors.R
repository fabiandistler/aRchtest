test_that("a regex selector selects modules by pattern", {
  glob <- arch_check(ui_rule(), root = fixture("pkg_layered"))
  regex <- arch_check(
    rule("UI must not use tools") |>
      modules_matching_regex("^R/ui_.*\\.R$") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_equal(regex$violations, glob$violations)
  expect_equal(
    regex$selected_files[["UI must not use tools"]],
    c("R/ui_dashboard.R", "R/ui_report.R")
  )
})

test_that("a glob star does not cross a path separator", {
  result <- arch_check(
    rule("everything under R") |>
      modules_matching("*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_true(result$rules$empty_selection)
})

test_that("a double star crosses path separators", {
  result <- arch_check(
    rule("everything under R") |>
      modules_matching("**.R") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_equal(result$rules$n_files, 5L)
})

test_that("selectors compose so a rule can cover several patterns", {
  result <- arch_check(
    rule("ui and domain") |>
      modules_matching("R/ui_*.R") |>
      modules_matching("R/domain_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_equal(
    result$selected_files[["ui and domain"]],
    c("R/domain_pricing.R", "R/ui_dashboard.R", "R/ui_report.R")
  )
})

test_that("a selector matching no file fails with a distinct message", {
  result <- arch_check(
    rule("typo") |>
      modules_matching("R/iu_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_true(result$rules$empty_selection)
  expect_equal(nrow(result$violations), 0L)
  expect_false(aRchtest:::arch_ok(result))

  text <- format(result)
  expect_true(any(grepl("EMPTY SELECTION", text, fixed = TRUE)))
  expect_true(any(grepl("R/iu_*.R", text, fixed = TRUE)))
  expect_true(any(grepl("typo", text, fixed = TRUE)))
})

test_that("an empty selection is distinguishable from an ordinary violation", {
  result <- arch_check(
    rule("typo") |>
      modules_matching("R/iu_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 0L)
  expect_true(result$rules$empty_selection)
  expect_equal(result$rules$n_files, 0L)
})

test_that("print shows the selected-file count", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_true(any(grepl("2 file(s) selected", format(result), fixed = TRUE)))
})

test_that("a constraint without a selector errors at construction", {
  expect_error(
    rule("no selector") |> must_not_call(packages = "tools"),
    "needs a selector first"
  )
  expect_error(
    rule("no selector") |> must_not_depend_on(modules = "R/infra_*.R"),
    "needs a selector first"
  )
  expect_error(
    rule("no selector") |> must_not_call(packages = "tools"),
    "no selector"
  )
})

test_that("a malformed argument vector errors at construction", {
  based <- rule("named rule") |> modules_matching("R/*.R")

  expect_error(
    must_not_call(based, packages = character()), "must not be empty"
  )
  expect_error(
    must_not_call(based, packages = NA_character_), "must not contain NA"
  )
  expect_error(must_not_call(based, packages = c("tools", "")), "empty strings")
  expect_error(must_not_call(based, packages = 42), "character vector")
  expect_error(
    must_not_call(based, functions = list("system")), "character vector"
  )
  expect_error(
    must_not_depend_on(based, modules = character()), "must not be empty"
  )
  expect_error(must_not_call(based, packages = character()), "named rule")
})

test_that("a constraint with neither packages nor functions errors", {
  based <- rule("named rule") |> modules_matching("R/*.R")

  expect_error(must_not_call(based), "needs `packages`, `functions`, or both")
  expect_error(must_not_depend_on(based), "needs `modules`")
})

test_that("an unknown argument to a DSL verb errors at construction", {
  based <- rule("named rule") |> modules_matching("R/*.R")

  expect_error(must_not_call(based, package = "tools"), "unknown argument")
  expect_error(
    must_not_call(based, packages = "tools", extra = 1), "unknown argument"
  )
  expect_error(must_not_depend_on(based, module = "R/x.R"), "unknown argument")
  expect_error(
    modules_matching(rule("named rule"), "R/*.R", nope = 1), "unknown argument"
  )
  expect_error(must_not_call(based, package = "tools"), "named rule")
})

test_that("rule() validates its own arguments", {
  expect_error(rule(character()), "single non-empty string")
  expect_error(rule(NA_character_), "single non-empty string")
  expect_error(rule(""), "single non-empty string")
  expect_error(rule("ok", why = 42), "single string or NULL")
})

test_that("a DSL verb applied to something that is not a rule errors", {
  expect_error(must_not_call("not a rule", packages = "tools"), "rule\\(\\)")
  expect_error(modules_matching("not a rule", "R/*.R"), "rule\\(\\)")
})

test_that("a rule prints its selectors and constraints", {
  built <- rule("layering", why = "keep it clean") |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = "tools", functions = "system") |>
    must_not_depend_on(modules = "R/infra_*.R")

  expect_output(print(built), "layering", fixed = TRUE)
  expect_output(print(built), "keep it clean", fixed = TRUE)
  expect_output(print(built), "R/ui_*.R", fixed = TRUE)
  expect_output(print(built), "must not call packages: tools", fixed = TRUE)
  expect_output(print(built), "must not call functions: system", fixed = TRUE)
  expect_output(
    print(built), "must not depend on modules: R/infra_*.R", fixed = TRUE
  )
})
