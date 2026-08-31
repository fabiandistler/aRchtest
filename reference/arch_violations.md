# The violations a check found

A convenience accessor for the violations table of an
[`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md)
result. The table has one row per finding and is a `data.table`, so it
can be filtered, grouped and summarised with tools you already use. When
a check passes it is empty but keeps the same columns and types, so code
consuming it needs no special case for success.

## Usage

``` r
arch_violations(result)
```

## Arguments

- result:

  An `arch_result` from
  [`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md).

## Value

A `data.table` of violations.

## Examples

``` r
project <- system.file("examples", "layered", package = "aRchtest")

rule("UI must not reach the database") |>
  modules_matching("R/ui_*.R") |>
  must_not_call(packages = "stats") |>
  arch_check(root = project) |>
  arch_violations()
#>                              rule             file  line column
#>                            <char>           <char> <int>  <int>
#> 1: UI must not reach the database R/ui_dashboard.R     2     15
#>    enclosing_function        callee  owner resolved_by internal
#>                <char>        <char> <char>      <char>   <lgcl>
#> 1:     render_summary stats::median  stats   namespace    FALSE
#>                    source_text
#>                         <char>
#> 1: stats::median(sales$amount)
```
