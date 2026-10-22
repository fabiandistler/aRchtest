confinement_rule <- function(...) {
  rule("only the API layer talks HTTP", ...) |>
    modules_matching("R/*.R") |>
    modules_excluding("R/api_*.R") |>
    must_not_call(packages = "httr")
}

test_that("everything except the exempted module carries the constraint", {
  result <- arch_check(confinement_rule(), root = fixture("pkg_httr_boundary"))

  expect_false(any(result$rules$empty_selection))
  expect_equal(result$rules$n_files, 1L)
  expect_equal(
    result$selected_files[["only the API layer talks HTTP"]],
    "R/ui_main.R"
  )

  expect_equal(nrow(result$violations), 1L)
  row <- result$violations[1]
  expect_equal(row$file, "R/ui_main.R")
  expect_equal(row$line, 2L)
  expect_equal(row$callee, "httr::GET")
  expect_equal(row$owner, "httr")
  expect_equal(row$resolved_by, "namespace")
  expect_false(row$internal)
})

test_that("excluding every selected file fails and names both pattern sets", {
  result <- arch_check(
    rule("nothing left") |>
      modules_matching("R/ui_*.R") |>
      modules_excluding("R/ui_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_true(result$rules$empty_selection)
  expect_equal(result$rules$n_files, 0L)
  expect_equal(nrow(result$violations), 0L)

  text <- format(result)
  expect_true(any(grepl("EMPTY SELECTION", text, fixed = TRUE)))
  expect_true(any(grepl(
    "pattern(s) R/ui_*.R (excluding R/ui_*.R) under root",
    text,
    fixed = TRUE
  )))
})

test_that("exclusions combine, so a rule can exempt several patterns", {
  result <- arch_check(
    rule("the kitchen sink stays local") |>
      modules_matching("R/*.R") |>
      modules_excluding("R/infra_*.R") |>
      modules_excluding("R/legacy_*.R") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_equal(
    result$selected_files[["the kitchen sink stays local"]],
    c("R/domain_pricing.R", "R/ui_dashboard.R", "R/ui_report.R")
  )
  expect_equal(result$rules$exclusions, "R/infra_*.R, R/legacy_*.R")
  expect_equal(result$rules$patterns, "R/*.R")
})

test_that("a rule without exclusions leaves the record column empty", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_equal(result$rules$patterns, "R/ui_*.R")
  expect_equal(result$rules$exclusions, "")
})

test_that("a lookahead regex now selects the same files as the glob subtract", {
  lookahead <- arch_check(
    rule("no HTTP outside the API") |>
      modules_matching_regex("^R/(?!api_).*\\.R$") |>
      must_not_call(packages = "httr"),
    root = fixture("pkg_httr_boundary")
  )
  subtract <- arch_check(
    confinement_rule(),
    root = fixture("pkg_httr_boundary")
  )

  expect_equal(
    lookahead$selected_files[["no HTTP outside the API"]],
    subtract$selected_files[["only the API layer talks HTTP"]]
  )
  # The rule column is part of the violations table, so it differs by design.
  expect_equal(
    lookahead$violations[, -"rule"],
    subtract$violations[, -"rule"]
  )
})

test_that("PCRE matching keeps glob selectors working", {
  result <- arch_check(
    rule("ui only") |>
      modules_matching("R/ui_dashboar?.R") |>
      must_not_call(packages = "tools"),
    root = fixture("pkg_layered")
  )

  expect_false(any(result$rules$empty_selection))
  expect_equal(result$selected_files[["ui only"]], "R/ui_dashboard.R")
})

test_that("an exclusion without an inclusion selector errors at construction", {
  expect_error(
    rule("no selector yet") |> modules_excluding("R/api_*.R"),
    "needs a selector first"
  )
  expect_error(
    rule("no selector yet") |> modules_excluding("R/api_*.R"),
    "before the exclusion"
  )
})

test_that("a malformed exclusion pattern errors at construction", {
  based <- rule("named rule") |> modules_matching("R/*.R")

  expect_error(
    modules_excluding(based, "R/api_*.R", nope = 1),
    "unknown argument"
  )
  expect_error(modules_excluding(based, character()), "must not be empty")
  expect_error(
    modules_excluding(based, NA_character_),
    "must not contain NA"
  )
  expect_error(
    modules_excluding(based, c("R/api_*.R", "")),
    "empty strings"
  )
  expect_error(modules_excluding(based, 42), "character vector")
  expect_error(
    modules_excluding(based, c("R/api_*.R", "R/ui_*.R")),
    "single string"
  )
  expect_error(
    modules_excluding(based, "R/api_*.R", nope = 1),
    "named rule"
  )
})

test_that("an exclusion verb applied to something that is not a rule errors", {
  expect_error(modules_excluding("not a rule", "R/api_*.R"), "rule\\(\\)")
})

test_that("an empty selector list selects nothing instead of erroring", {
  expect_equal(arch_select_files(character(), list()), character())
  expect_equal(
    arch_select_files(c("R/ui_main.R"), list()),
    character()
  )
})

test_that("a rule without exclusions still selects its files", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_equal(
    result$selected_files[["UI must not use tools"]],
    c("R/ui_dashboard.R", "R/ui_report.R")
  )
  expect_equal(result$rules$n_files, 2L)
})

test_that("a rule prints its exclusions", {
  built <- confinement_rule(why = "Only the client knows the wire format")

  expect_output(print(built), "selects: R/*.R (glob)", fixed = TRUE)
  expect_output(print(built), "excludes: R/api_*.R (glob)", fixed = TRUE)
})
