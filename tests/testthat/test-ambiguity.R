ambiguous_rule <- function() {
  rule("UI must not use Matrix") |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = "Matrix")
}

test_that("a symbol exported by two candidates is ambiguous, not a violation", {
  skip_if_not_installed("Matrix")
  result <- arch_check(ambiguous_rule(), root = fixture("pkg_ambiguous"))

  expect_equal(nrow(result$violations), 0L)
  expect_equal(nrow(result$ambiguous), 2L)
  expect_equal(result$counts$ambiguous, 2L)
})

test_that("an ambiguous call carries its full candidate list", {
  skip_if_not_installed("Matrix")
  result <- arch_check(ambiguous_rule(), root = fixture("pkg_ambiguous"))
  toeplitz <- result$ambiguous[which(result$ambiguous$callee == "toeplitz")]

  expect_equal(nrow(toeplitz), 1L)
  expect_equal(toeplitz$candidates, "Matrix|stats")
  expect_equal(toeplitz$line, 2L)
  expect_equal(toeplitz$enclosing_function, "summarise_matrix")
})

test_that("a base export is never silently attributed to a declared package", {
  skip_if_not_installed("Matrix")
  result <- arch_check(ambiguous_rule(), root = fixture("pkg_ambiguous"))
  head_call <- result$ambiguous[which(result$ambiguous$callee == "head")]

  expect_equal(nrow(head_call), 1L)
  expect_equal(head_call$candidates, "Matrix|utils")
})

test_that("the strict policy turns ambiguity into a violation", {
  skip_if_not_installed("Matrix")
  result <- arch_check(
    ambiguous_rule(),
    root = fixture("pkg_ambiguous"),
    on_ambiguous = "fail"
  )

  expect_equal(nrow(result$violations), 2L)
  expect_true(all(result$violations$resolved_by == "ambiguous"))
  expect_equal(nrow(result$ambiguous), 0L)
  expect_setequal(result$violations$owner, c("Matrix|stats", "Matrix|utils"))
})

test_that("a local definition removes the ambiguity", {
  skip_if_not_installed("Matrix")
  result <- arch_check(ambiguous_rule(), root = fixture("pkg_ambiguous_local"))

  expect_equal(nrow(result$violations), 0L)
  expect_equal(nrow(result$ambiguous), 0L)
  expect_equal(result$counts$ambiguous, 0L)
})

test_that("a non-zero ambiguous count is called out when printing", {
  skip_if_not_installed("Matrix")
  result <- arch_check(ambiguous_rule(), root = fixture("pkg_ambiguous"))
  text <- format(result)

  expect_true(any(grepl("AMBIGUOUS", text, fixed = TRUE)))
  expect_true(
    any(grepl("ambiguous, not counted as violations", text, fixed = TRUE))
  )
})

test_that("the ambiguity policy must be one of the documented values", {
  expect_error(
    arch_check(
      ambiguous_rule(),
      root = fixture("pkg_ambiguous"),
      on_ambiguous = "explode"
    ),
    "should be one of"
  )
})
