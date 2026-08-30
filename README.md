# aRchtest

ArchUnit for R — declare dependency rules between modules and enforce them as
`testthat` tests.

```r
rule("layering") |>
  modules_matching("R/ui_*.R") |>
  must_not_call(packages = c("DBI", "RPostgres")) |>
  arch_expect()   # fails as a testthat test, with file:line:col for every violation
```

Purely static: the graph comes from `getParseData()`, the code under analysis is
never evaluated.

Not implemented yet. The design is in [SPEC.md](SPEC.md).
