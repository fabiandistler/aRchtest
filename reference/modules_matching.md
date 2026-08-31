# Select the modules a rule applies to

`modules_matching()` narrows a rule to the files matched by a glob
pattern. `modules_matching_regex()` does the same with a regular
expression, for when file naming is too irregular for a glob. Both match
against paths relative to the project root, so a rule reads the same
wherever the tests are run from.

## Usage

``` r
modules_matching(rule, pattern, ...)

modules_matching_regex(rule, pattern, ...)
```

## Arguments

- rule:

  An `arch_rule` from
  [`rule()`](https://fabiandistler.github.io/aRchtest/reference/rule.md).

- pattern:

  A single glob pattern (`modules_matching()`) or regular expression
  (`modules_matching_regex()`), matched against file paths relative to
  the project root.

- ...:

  Not used. Present so a misspelled argument errors here rather than
  surfacing later as a confusing check result.

## Value

The rule, with the selector attached.

## Details

In a glob, `*` matches any run of characters within one path segment,
`**` matches across segments, and `?` matches a single character within
a segment. Everything else is literal. Reach for the regex variant only
when a glob cannot express the selection – a glob is easier for the next
reader.

Calling a selector more than once on the same rule widens the selection:
a file is selected if it matches any of the rule's patterns.

## Examples

``` r
rule("layering") |> modules_matching("R/ui_*.R")
#> <arch_rule> layering
#>   selects: R/ui_*.R (glob)

rule("layering") |> modules_matching_regex("^R/(ui|view)_.*\\.R$")
#> <arch_rule> layering
#>   selects: ^R/(ui|view)_.*\.R$ (regex)
```
