test_that("a ::: call is a violation and is flagged as an internal API access", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))
  internal <- result$violations[which(result$violations$resolved_by == "namespace_internal")]

  expect_equal(nrow(internal), 1L)
  expect_equal(internal$file, "R/ui_report.R")
  expect_equal(internal$line, 5L)
  expect_equal(internal$callee, "tools:::.hidden_helper")
  expect_true(internal$internal)
})

test_that(":: and ::: calls to the same package are distinguishable", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))
  report <- result$violations[which(result$violations$file == "R/ui_report.R")]

  expect_equal(report$resolved_by, c("namespace", "namespace_internal"))
  expect_equal(report$internal, c(FALSE, TRUE))
  expect_true(all(report$owner == "tools"))
})

test_that("violations are found at top level as well as inside functions", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))
  top <- result$violations[which(result$violations$line == 1L & result$violations$file == "R/ui_report.R")]

  expect_equal(nrow(top), 1L)
  expect_true(is.na(top$enclosing_function))
  expect_false(any(is.na(
    result$violations$enclosing_function[result$violations$file == "R/ui_dashboard.R"]
  )))
})

test_that("a violation in a nested function names the innermost enclosing function", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))
  nested <- result$violations[which(result$violations$line == 5L)]

  expect_equal(nested$enclosing_function, "helper")
})

test_that("a forbidden name in a comment or a string produces no violation", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_false(any(result$violations$line %in% c(11L, 15L)))
  expect_equal(nrow(result$violations), 4L)
})

test_that("an unparseable file is reported, skipped, and does not stop the check", {
  expect_warning(
    result <- arch_check(ui_rule(), root = fixture("pkg_broken")),
    "could not be parsed"
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$file, "R/ui_good.R")
  expect_equal(result$skipped_files$file, "R/ui_halfdone.R")
  expect_equal(result$files_parsed, 1L)
})

test_that("a skipped file is visible in the printed result", {
  suppressWarnings(
    result <- arch_check(ui_rule(), root = fixture("pkg_broken"))
  )

  expect_true(any(grepl("PARTIAL", format(result), fixed = TRUE)))
  expect_true(any(grepl("R/ui_halfdone.R", format(result), fixed = TRUE)))
})

test_that("calls dispatched through an object are not attributed to a package", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  writeLines(
    c("handle <- function(api) {", "  api$file_ext(1)", "}"),
    file.path(root, "R", "ui_dispatch.R")
  )

  result <- arch_check(ui_rule(), root = root)

  expect_equal(nrow(result$violations), 0L)
  expect_equal(result$counts$unresolved, 1L)
})
