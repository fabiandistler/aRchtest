test_that("a forbidden qualified call is reported with a located finding", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))
  found <- result$violations[
    which(result$violations$file == "R/ui_dashboard.R" & result$violations$line == 2L)
  ]

  expect_equal(nrow(found), 1L)
  expect_equal(found$rule, "UI must not use tools")
  expect_equal(found$column, 3L)
  expect_equal(found$enclosing_function, "render_table")
  expect_equal(found$callee, "tools::file_ext")
  expect_equal(found$owner, "tools")
  expect_equal(found$resolved_by, "namespace")
  expect_false(found$internal)
  expect_equal(found$source_text, "tools::file_ext(rows$path)")
})

test_that("every violation is reported, not just the first", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_equal(
    result$violations[, c("file", "line")],
    data.table::data.table(
      file = c("R/ui_dashboard.R", "R/ui_dashboard.R", "R/ui_report.R", "R/ui_report.R"),
      line = c(2L, 6L, 1L, 5L)
    )
  )
})

test_that("building a rule performs no analysis", {
  built <- rule("inert") |>
    modules_matching("R/does_not_exist_*.R") |>
    must_not_call(packages = "tools")

  expect_s3_class(built, "arch_rule")
  expect_equal(built$name, "inert")
  expect_length(built$constraints, 1L)
})

test_that("the violations table has the frozen column contract", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_s3_class(result$violations, "data.table")
  expect_equal(
    names(result$violations),
    c(
      "rule", "file", "line", "column", "enclosing_function", "callee",
      "owner", "resolved_by", "internal", "source_text"
    )
  )
  expect_type(result$violations$line, "integer")
  expect_type(result$violations$column, "integer")
  expect_type(result$violations$internal, "logical")
  expect_type(result$violations$callee, "character")
})

test_that("a clean project returns an empty but identically typed table", {
  clean <- arch_check(ui_rule(), root = fixture("pkg_clean"))
  dirty <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_equal(nrow(clean$violations), 0L)
  expect_s3_class(clean$violations, "data.table")
  expect_equal(names(clean$violations), names(dirty$violations))
  expect_equal(
    vapply(clean$violations, typeof, character(1)),
    vapply(dirty$violations, typeof, character(1))
  )
})

test_that("the result carries check metadata", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_equal(result$rules$rule, "UI must not use tools")
  expect_equal(result$rules$n_files, 2L)
  expect_equal(
    result$selected_files[["UI must not use tools"]],
    c("R/ui_dashboard.R", "R/ui_report.R")
  )
  expect_equal(result$files_parsed, 5L)
  expect_true(result$is_package)
  expect_equal(result$root, fixture("pkg_layered"))
  expect_equal(
    result$counts$resolved + result$counts$ambiguous + result$counts$unresolved,
    result$counts$call_sites
  )
})

test_that("the root defaults to the working directory", {
  withr::with_dir(fixture("pkg_layered"), {
    result <- arch_check(ui_rule())
    expect_equal(nrow(result$violations), 4L)
  })
})

test_that("results are identical across repeated checks and working directories", {
  root <- fixture("pkg_layered")
  first <- arch_check(ui_rule(), root = root)
  second <- arch_check(ui_rule(), root = root)

  elsewhere <- withr::with_dir(
    fixture("pkg_clean"),
    arch_check(ui_rule(), root = root)
  )

  expect_equal(first$violations, second$violations)
  expect_equal(first$violations, elsewhere$violations)
  expect_equal(first$counts, elsewhere$counts)
})

test_that("print and format give a readable summary", {
  result <- arch_check(
    ui_rule(why = "Presentation stays thin"),
    root = fixture("pkg_layered")
  )
  text <- format(result)

  expect_type(text, "character")
  expect_true(any(grepl("UI must not use tools", text, fixed = TRUE)))
  expect_true(any(grepl("Presentation stays thin", text, fixed = TRUE)))
  expect_true(any(grepl("R/ui_dashboard.R:2:3", text, fixed = TRUE)))
  expect_true(any(grepl("render_table()", text, fixed = TRUE)))
  expect_true(any(grepl("resolution:", text, fixed = TRUE)))
  expect_output(print(result), "UI must not use tools", fixed = TRUE)
})

test_that("arch_violations() returns the violations table", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_equal(arch_violations(result), result$violations)
  expect_error(arch_violations("not a result"), "arch_check")
})

test_that("arch_check() rejects things that are not rules", {
  expect_error(arch_check("not a rule", root = fixture("pkg_clean")), "rule\\(\\)")
  expect_error(arch_check(list(), root = fixture("pkg_clean")), "non-empty list")
  expect_error(
    arch_check(list(ui_rule(), "nope"), root = fixture("pkg_clean")),
    "element\\(s\\) 2"
  )
})

test_that("a missing project root is an error", {
  expect_error(
    arch_check(ui_rule(), root = file.path(tempdir(), "no-such-project")),
    "does not exist"
  )
})
