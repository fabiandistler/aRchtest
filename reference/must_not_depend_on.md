# Forbid a dependency on other modules of the same project

`must_not_depend_on()` enforces a boundary inside your own code rather
than against an external package. The modules a rule selects must not
call functions defined in the modules named here, so a `domain/` file
reaching into an `infra/` helper fails with the same located finding an
external violation would produce.

## Usage

``` r
must_not_depend_on(rule, ..., modules, regex = FALSE)
```

## Arguments

- rule:

  An `arch_rule` that already has a selector.

- ...:

  Not used. Present so a misspelled argument errors here rather than
  surfacing later as a confusing check result.

- modules:

  A character vector of patterns naming the forbidden modules.

- regex:

  Whether `modules` are regular expressions. The default, `FALSE`, reads
  them as globs, matching
  [`modules_matching()`](https://fabiandistler.github.io/aRchtest/reference/modules_matching.md).

## Value

The rule, with the constraint attached.

## Details

Forbidden modules are named with the same selector vocabulary the rule's
own selector uses, resolved relative to the project root. No `::` is
required: the constraint works on ordinary unqualified calls between
project files. A module calling a function it defines itself is never a
violation.

## Examples

``` r
rule("domain must not know about infrastructure") |>
  modules_matching("R/domain_*.R") |>
  must_not_depend_on(modules = "R/infra_*.R")
#> <arch_rule> domain must not know about infrastructure
#>   selects: R/domain_*.R (glob)
#>   must not depend on modules: R/infra_*.R
```
