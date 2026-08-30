test_that("an unqualified call to a forbidden declared dependency is a violation", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))
  unqualified <- result$violations[which(result$violations$resolved_by == "export")]

  expect_equal(nrow(unqualified), 1L)
  expect_equal(unqualified$file, "R/ui_dashboard.R")
  expect_equal(unqualified$line, 6L)
  expect_equal(unqualified$callee, "file_ext")
  expect_equal(unqualified$owner, "tools")
})

test_that("declared dependencies come from DESCRIPTION Imports and Depends", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_equal(result$declared_dependencies, "tools")
})

test_that("a local definition wins over a package export in another file", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_false(any(result$violations$callee == "toTitleCase"))
  expect_false(any(result$violations$line == 10L))
})

test_that("a local definition is attributed to the module that defines it", {
  result <- arch_check(
    rule("domain owns its helpers") |>
      modules_matching("R/ui_*.R") |>
      must_not_depend_on(modules = "R/domain_*.R"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 1L)
  expect_equal(result$violations$callee, "toTitleCase")
  expect_equal(result$violations$owner, "R/domain_pricing.R")
  expect_equal(result$violations$resolved_by, "local")
})

test_that("an unattributable call is counted, never a violation", {
  result <- arch_check(
    rule("domain must not use tools") |>
      modules_matching("R/domain_*.R") |>
      must_not_call(packages = c("tools", "Matrix")),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 0L)
  expect_gte(result$counts$unresolved, 1L)
})

test_that("a package project ignores library() calls when resolving", {
  result <- arch_check(
    rule("legacy must not use Matrix") |>
      modules_matching("R/legacy_*.R") |>
      must_not_call(packages = "Matrix"),
    root = fixture("pkg_layered")
  )

  expect_equal(nrow(result$violations), 0L)
  expect_equal(result$declared_dependencies, "tools")
})

test_that("resolution counts are reported alongside the total", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_named(
    result$counts, c("call_sites", "resolved", "ambiguous", "unresolved")
  )
  expect_gt(result$counts$call_sites, 0L)
  expect_gt(result$counts$resolved, 0L)
  expect_equal(
    result$counts$resolved + result$counts$ambiguous + result$counts$unresolved,
    result$counts$call_sites
  )
})

test_that("violations record how the call was resolved", {
  result <- arch_check(ui_rule(), root = fixture("pkg_layered"))

  expect_setequal(
    unique(result$violations$resolved_by),
    c("namespace", "namespace_internal", "export")
  )
})

test_that("an uninstallable dependency degrades resolution visibly", {
  result <- arch_check(
    rule("ui must not use the missing package") |>
      modules_matching("R/ui_*.R") |>
      must_not_call(packages = "anRchtestPackageThatIsNotInstalled"),
    root = fixture("pkg_missing_dep")
  )

  expect_equal(nrow(result$violations), 0L)
  expect_equal(
    result$unavailable_dependencies, "anRchtestPackageThatIsNotInstalled"
  )
  expect_true(any(grepl("DEGRADED", format(result), fixed = TRUE)))
})

test_that("the project is parsed once regardless of how many rules are checked", {
  root <- fixture("pkg_layered")
  one <- arch_check(ui_rule(), root = root)
  many <- arch_check(
    lapply(1:5, function(i) {
      rule(paste("rule", i)) |>
        modules_matching("R/ui_*.R") |>
        must_not_call(packages = "tools")
    }),
    root = root
  )

  expect_equal(many$files_parsed, one$files_parsed)
  expect_equal(many$counts, one$counts)
})
