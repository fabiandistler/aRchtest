# Enforce architectural rules as a testthat expectation

`arch_expect()` runs
[`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md)
and turns the result into a `testthat` expectation, so an architectural
agreement is enforced by the tooling you already run rather than by a
new command to remember.

## Usage

``` r
arch_expect(rules, root = ".", on_ambiguous = c("report", "fail"))
```

## Arguments

- rules:

  A single `arch_rule` or a list of them. Rule names must be unique, so
  every finding stays attributable to the rule that produced it.

- root:

  Path to the project root to analyse. Defaults to the working
  directory. All file selection and every reported path is relative to
  this root, so rules read the same wherever the tests run from.

- on_ambiguous:

  What to do with a call whose symbol is exported by more than one
  candidate package and which is not defined locally. `"report"`, the
  default, puts such a call in the `ambiguous` table and keeps it out of
  `violations`. `"fail"` counts it as a violation.

## Value

The `arch_result`, invisibly.

## Details

The expectation fails when any rule found a violation, and also when a
rule's selector matched no file at all – a vacuously green architecture
test is worse than no test. The failure message names each failing rule,
its rationale if one was given, and every finding with its file, line,
enclosing function, callee and source text, so a CI log is enough to act
on without opening the code.

## Examples

``` r
project <- system.file("examples", "layered", package = "aRchtest")

if (requireNamespace("testthat", quietly = TRUE)) {
  testthat::test_that("domain stays free of infrastructure", {
    rule("domain must not reach infrastructure",
      why = "Domain logic has to be testable without a store"
    ) |>
      modules_matching("R/domain_*.R") |>
      must_not_depend_on(modules = "R/infra_*.R") |>
      arch_expect(root = project)
  })
}
#> Test passed with 1 success 🥇.
```
