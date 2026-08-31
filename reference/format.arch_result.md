# Format a check result

Builds the same readable summary
[`print.arch_result()`](https://fabiandistler.github.io/aRchtest/reference/print.arch_result.md)
displays, but returns it as a character vector instead of writing it to
the console. Use it when you want to route the summary somewhere else –
a log, a CI annotation, a file.

## Usage

``` r
# S3 method for class 'arch_result'
format(x, ...)
```

## Arguments

- x:

  An `arch_result` from
  [`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md).

- ...:

  Ignored.

## Value

A character vector, one element per line of the summary.

## Examples

``` r
project <- system.file("examples", "layered", package = "aRchtest")

summary_lines <- format(arch_check(
  rule("UI must not compute statistics") |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = "stats"),
  root = project
))

writeLines(summary_lines)
#> <arch_result> 1 rule(s), 1 violation(s)
#>   root: /home/runner/work/_temp/Library/aRchtest/examples/layered (package)
#> 
#> * UI must not compute statistics -- 1 file(s) selected, 1 violation(s)
#>     R/ui_dashboard.R:2:15  in render_summary()  stats::median -> stats [namespace]  stats::median(sales$amount)
#> 
#> resolution: 9 of 9 call site(s) resolved, 0 ambiguous, 0 unresolved  (4 file(s) parsed)
```
