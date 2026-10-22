# Exclude files from a rule's selection

`modules_excluding()` subtracts files from the selection a rule has so
far: the files a rule applies to are the union of its inclusion
selectors minus the union of its exclusion selectors. Use it for the
boundary a positive constraint cannot yet state: "only the API layer may
call httr" cannot be listed out loud, but "every file except the API
layer must not call httr" says the same thing as a negative constraint
over a selection that keeps `R/api_*.R` out.

## Usage

``` r
modules_excluding(rule, pattern, ...)
```

## Arguments

- rule:

  An `arch_rule` from
  [`rule()`](https://fabiandistler.github.io/aRchtest/reference/rule.md)
  that already has a selector.

- pattern:

  A single glob pattern naming the modules the rule must not cover,
  matched against file paths relative to the project root.

- ...:

  Not used. Present so a misspelled argument errors here rather than
  surfacing later as a confusing check result.

## Value

The rule, with the exclusion attached.

## Details

The pattern is a single glob, translated like
[`modules_matching()`](https://fabiandistler.github.io/aRchtest/reference/modules_matching.md)
does, and matched against paths relative to the project root. Call it
after at least one inclusion selector, and more than once to exempt
several patterns: the exclusions combine, they never narrow each other.

An exclusion that removes every selected file fails the check rather
than letting the rule pass vacuously; the EMPTY SELECTION message names
both the inclusion and the exclusion patterns (see
[`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md)).

## See also

[`modules_matching()`](https://fabiandistler.github.io/aRchtest/reference/modules_matching.md)
to add files to the selection.

## Examples

``` r
rule("only the API layer talks HTTP") |>
  modules_matching("R/*.R") |>
  modules_excluding("R/api_*.R") |>
  must_not_call(packages = "httr")
#> <arch_rule> only the API layer talks HTTP
#>   selects: R/*.R (glob)
#>   excludes: R/api_*.R (glob)
#>   must not call packages: httr

rule("everything but the sync job stays local") |>
  modules_matching("R/*.R") |>
  modules_excluding("R/sync_*.R") |>
  must_not_depend_on(modules = "R/infra_*.R")
#> <arch_rule> everything but the sync job stays local
#>   selects: R/*.R (glob)
#>   excludes: R/sync_*.R (glob)
#>   must not depend on modules: R/infra_*.R
```
