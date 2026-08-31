# Check architectural rules against a project

`arch_check()` performs the analysis a rule describes and returns the
findings as data. It discovers the project's source files, parses them,
attributes every call it finds to an owner, and applies each rule's
constraints to the calls in the files that rule selects.

## Usage

``` r
arch_check(rules, root = ".", on_ambiguous = c("report", "fail"))
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

An `arch_result`: a list with

- `violations` – a `data.table` with one row per finding and columns
  `rule`, `file`, `line`, `column`, `enclosing_function`, `callee`,
  `owner`, `resolved_by`, `internal` and `source_text`. On success it is
  empty but has the same columns and types, never `NULL`.

- `ambiguous` – near misses that could not be attributed confidently.

- `rules` – one row per rule, with the number of files it selected,
  whether its selector matched nothing, and how many violations it
  found.

- `selected_files` – per rule, the files its selector matched.

- `counts` – call sites seen, resolved, ambiguous and unresolved.

- `files_parsed`, `skipped_files` – parse coverage.

- `declared_dependencies`, `unavailable_dependencies` – resolution
  inputs.

- `root`, `is_package`, `on_ambiguous` – how the check was scoped.

## Details

The project under analysis is never sourced, loaded or evaluated – only
its parse data is read. Checks are therefore deterministic, safe to run
in continuous integration, and work on a project that does not currently
run.

The project is discovered, parsed and resolved **once** per call
regardless of how many rules are supplied, so expressing more
architecture does not cost proportionally more time.

## Resolving unqualified calls

Attributing a bare `dbGetQuery()` to `DBI` means enumerating what `DBI`
exports, which requires the package to be **installed** in the library
path of the R session running the check. A declared dependency that
cannot be loaded degrades resolution rather than erroring: its calls
fall into the unresolved bucket and the package is listed in
`unavailable_dependencies`.

Read `counts` before trusting a clean result. A check that resolved
little of what it saw proves little, and a degraded pass looks exactly
like a clean project unless you look.

## Examples

``` r
project <- system.file("examples", "layered", package = "aRchtest")

result <- rule("UI must not reach the database") |>
  modules_matching("R/ui_*.R") |>
  must_not_call(packages = "stats") |>
  arch_check(root = project)

result
#> <arch_result> 1 rule(s), 1 violation(s)
#>   root: /home/runner/work/_temp/Library/aRchtest/examples/layered (package)
#> 
#> * UI must not reach the database -- 1 file(s) selected, 1 violation(s)
#>     R/ui_dashboard.R:2:15  in render_summary()  stats::median -> stats [namespace]  stats::median(sales$amount)
#> 
#> resolution: 9 of 9 call site(s) resolved, 0 ambiguous, 0 unresolved  (4 file(s) parsed)
result$violations
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
