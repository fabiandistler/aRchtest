architecture <- function() {
  list(
    ui_rule(),
    rule("domain must not reach infrastructure") |>
      modules_matching("R/domain_*.R") |>
      must_not_depend_on(modules = "R/infra_*.R")
  )
}

test_that("a list of rules produces one combined result", {
  result <- arch_check(architecture(), root = fixture("pkg_layered"))

  expect_s3_class(result, "arch_result")
  expect_s3_class(result$violations, "data.table")
  expect_equal(nrow(result$violations), 5L)
  expect_equal(nrow(result$rules), 2L)
})

test_that("every violation row carries the rule that produced it", {
  result <- arch_check(architecture(), root = fixture("pkg_layered"))

  expect_equal(
    sum(result$violations$rule == "UI must not use tools"), 4L
  )
  expect_equal(
    sum(result$violations$rule == "domain must not reach infrastructure"), 1L
  )
})

test_that("per-rule metadata stays attributable to its own rule", {
  result <- arch_check(
    c(architecture(), list(
      rule("typo") |>
        modules_matching("R/nope_*.R") |>
        must_not_call(packages = "tools")
    )),
    root = fixture("pkg_layered")
  )

  expect_equal(result$rules$rule[3], "typo")
  expect_equal(result$rules$empty_selection, c(FALSE, FALSE, TRUE))
  expect_equal(result$rules$n_files, c(2L, 1L, 0L))
  expect_equal(result$rules$n_violations, c(4L, 1L, 0L))
  expect_equal(result$selected_files[["typo"]], character())
})

test_that("coverage counts are reported for the check as a whole", {
  one <- arch_check(ui_rule(), root = fixture("pkg_layered"))
  many <- arch_check(architecture(), root = fixture("pkg_layered"))

  expect_equal(many$counts, one$counts)
})

test_that("print groups findings under the rule that produced them", {
  text <- format(arch_check(architecture(), root = fixture("pkg_layered")))
  ui_at <- grep("UI must not use tools", text, fixed = TRUE)
  domain_at <- grep("domain must not reach infrastructure", text, fixed = TRUE)
  store_at <- grep("store_lookup", text, fixed = TRUE)

  expect_length(ui_at, 1L)
  expect_length(domain_at, 1L)
  expect_true(all(store_at > domain_at))
})

test_that("a mixed rule set reports failures and accounts for the rest", {
  result <- arch_check(
    list(
      ui_rule(),
      rule("domain must not use Matrix") |>
        modules_matching("R/domain_*.R") |>
        must_not_call(packages = "Matrix")
    ),
    root = fixture("pkg_layered")
  )

  expect_equal(unique(result$violations$rule), "UI must not use tools")
  expect_equal(result$rules$n_violations, c(4L, 0L))
  expect_equal(result$rules$rule[2], "domain must not use Matrix")
  expect_equal(result$rules$n_files[2], 1L)
})
