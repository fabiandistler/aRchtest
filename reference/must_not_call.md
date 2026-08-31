# Forbid calls to packages or functions

`must_not_call()` states that the modules a rule selects must not call
the given packages, the given functions, or both. It is a negative
constraint: it never asserts what the modules *may* call.

## Usage

``` r
must_not_call(rule, ..., packages = NULL, functions = NULL)
```

## Arguments

- rule:

  An `arch_rule` that already has a selector.

- ...:

  Not used. Present so a misspelled argument errors here rather than
  surfacing later as a confusing check result.

- packages:

  A character vector of package names the selected modules must not
  call.

- functions:

  A character vector of function names the selected modules must not
  call. Bare names such as `"system"` match the function whoever owns
  it; qualified names such as `"utils::head"` match only that owner.

## Value

The rule, with the constraint attached.

## Details

A call is attributed to an owner before the constraint is applied, so
both `DBI::dbGetQuery()` and a bare `dbGetQuery()` are caught – a rule
cannot be evaded by dropping the `::` prefix. A call the analysis cannot
attribute is never reported as a violation; see
[`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md)
for how to read the resolution counts that tell you how much was
attributed.

Base packages count as declared, so `functions = "system"` fires on a
bare [`system()`](https://rdrr.io/r/base/system.html) call. A function
the project defines itself always wins over a package export of the same
name, so a local helper never produces a violation.

## Examples

``` r
rule("UI must not reach the database") |>
  modules_matching("R/ui_*.R") |>
  must_not_call(packages = c("DBI", "RPostgres"))
#> <arch_rule> UI must not reach the database
#>   selects: R/ui_*.R (glob)
#>   must not call packages: DBI, RPostgres

rule("No shelling out") |>
  modules_matching("R/*.R") |>
  must_not_call(functions = c("system", "setwd"))
#> <arch_rule> No shelling out
#>   selects: R/*.R (glob)
#>   must not call functions: system, setwd
```
