local_package <- function(ui_code, parent = NULL, name = "pkg1") {
  if (is.null(parent)) {
    parent <- withr::local_tempdir(.local_envir = parent.frame())
  }
  root <- file.path(parent, name)
  dir.create(file.path(root, "R"), recursive = TRUE)
  dir.create(file.path(root, "tests", "testthat"), recursive = TRUE)
  writeLines(
    c(paste0("Package: ", name), "Version: 0.1.0", "Imports: DBI"),
    file.path(root, "DESCRIPTION")
  )
  writeLines(ui_code, file.path(root, "R", "ui_dashboard.R"))
  writeLines(
    "test_that('architecture', expect_true(TRUE))",
    file.path(root, "tests", "testthat", "test-arch.R")
  )
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

readme_rule <- function() {
  rule("layering") |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = c("DBI", "RPostgres"))
}

clean_ui <- "render_table <- function(con) paste(con)"
dirty_ui <- "render_table <- function(con) DBI::dbGetQuery(con, 'select 1')"

test_that("the README example passes from tests/testthat on clean code (#19)", {
  root <- local_package(clean_ui)

  withr::with_dir(file.path(root, "tests", "testthat"), {
    expect_success(arch_expect(readme_rule()))
    result <- arch_check(readme_rule())
  })
  expect_equal(result$root, root)
  expect_true(result$is_package)
})

test_that("the README example reports a violation, not EMPTY SELECTION (#19)", {
  root <- local_package(dirty_ui)

  withr::with_dir(file.path(root, "tests", "testthat"), {
    result <- arch_check(readme_rule())
  })
  expect_false(result$rules$empty_selection)
  expect_equal(result$violations$file, "R/ui_dashboard.R")
  expect_equal(result$violations$owner, "DBI")
})

test_that("the default root finds the sources under R CMD check (#19)", {
  check_dir <- file.path(withr::local_tempdir(), "pkg1.Rcheck")
  dir.create(file.path(check_dir, "00_pkg_src"), recursive = TRUE)
  source_root <- local_package(
    dirty_ui,
    parent = file.path(check_dir, "00_pkg_src")
  )
  dir.create(file.path(check_dir, "tests", "testthat"), recursive = TRUE)

  withr::with_dir(file.path(check_dir, "tests", "testthat"), {
    result <- arch_check(readme_rule())
  })
  expect_equal(result$root, source_root)
  expect_equal(nrow(result$violations), 1L)
})

test_that("an .Rproj file marks the root of a non-package project", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  dir.create(file.path(root, "tests", "testthat"), recursive = TRUE)
  file.create(file.path(root, "app.Rproj"))
  writeLines(dirty_ui, file.path(root, "R", "ui_dashboard.R"))
  writeLines("1", file.path(root, "tests", "testthat", "test-arch.R"))

  withr::with_dir(file.path(root, "tests", "testthat"), {
    result <- arch_check(readme_rule())
  })
  expect_false(result$is_package)
  expect_equal(nrow(result$violations), 1L)
})

test_that("an explicit root is used as given, without searching upwards", {
  root <- local_package(dirty_ui)
  testthat_dir <- file.path(root, "tests", "testthat")

  result <- arch_check(readme_rule(), root = testthat_dir)
  expect_equal(result$root, normalizePath(testthat_dir, winslash = "/"))
  expect_true(result$rules$empty_selection)
})

test_that("the EMPTY SELECTION message names the resolved root", {
  root <- local_package(clean_ui)
  testthat_dir <- normalizePath(
    file.path(root, "tests", "testthat"),
    winslash = "/"
  )

  expect_failure(
    arch_expect(readme_rule(), root = testthat_dir),
    paste0("root ", testthat_dir),
    fixed = TRUE
  )
})
