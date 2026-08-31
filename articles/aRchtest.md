# Declaring and enforcing an architecture

``` r

library(aRchtest)
```

An architectural agreement that lives in a README is not enforced. This
vignette shows how to turn one into a test that fails the moment someone
crosses the boundary.

The examples run against a tiny layered project shipped with the
package:

``` r

project <- system.file("examples", "layered", package = "aRchtest")

list.files(project, recursive = TRUE)
#> [1] "DESCRIPTION"        "R/domain_pricing.R" "R/infra_shell.R"   
#> [4] "R/infra_store.R"    "R/ui_dashboard.R"
```

It has three layers. `R/ui_dashboard.R` renders things,
`R/domain_pricing.R` holds business rules, and `R/infra_store.R` reads
and writes files.

## A rule for a package project

A rule names an agreement, selects the modules it governs, and states a
constraint. Nothing happens until you check it – a rule is inert data.

``` r

ui_layer <- rule(
  "UI must not compute statistics",
  why = "Presentation stays thin so the domain owns the numbers"
) |>
  modules_matching("R/ui_*.R") |>
  must_not_call(packages = "stats")

ui_layer
#> <arch_rule> UI must not compute statistics
#>   why: Presentation stays thin so the domain owns the numbers
#>   selects: R/ui_*.R (glob)
#>   must not call packages: stats
```

[`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md)
runs the analysis and hands back the findings as data:

``` r

result <- arch_check(ui_layer, root = project)

result
#> <arch_result> 1 rule(s), 1 violation(s)
#>   root: /home/runner/work/_temp/Library/aRchtest/examples/layered (package)
#> 
#> * UI must not compute statistics -- 1 file(s) selected, 1 violation(s)
#>     why: Presentation stays thin so the domain owns the numbers
#>     R/ui_dashboard.R:2:15  in render_summary()  stats::median -> stats [namespace]  stats::median(sales$amount)
#> 
#> resolution: 9 of 9 call site(s) resolved, 0 ambiguous, 0 unresolved  (4 file(s) parsed)
```

In your own package the root defaults to the working directory, so you
would simply write `arch_check(ui_layer)`.

## Reading a failure

The violations table has one row per finding:

``` r

arch_violations(result)
#>                              rule             file  line column
#>                            <char>           <char> <int>  <int>
#> 1: UI must not compute statistics R/ui_dashboard.R     2     15
#>    enclosing_function        callee  owner resolved_by internal
#>                <char>        <char> <char>      <char>   <lgcl>
#> 1:     render_summary stats::median  stats   namespace    FALSE
#>                    source_text
#>                         <char>
#> 1: stats::median(sales$amount)
```

Each column answers one question:

| Column | What it tells you |
|----|----|
| `rule` | Which agreement was broken. Matters when you check a rule set. |
| `file`, `line`, `column` | Where, relative to the project root. Your editor can jump straight to it. |
| `enclosing_function` | The innermost named function containing the call, or `NA` at file top level. |
| `callee` | The symbol as written, so [`stats::median`](https://rdrr.io/r/stats/median.html) and a bare `median` are distinguishable. |
| `owner` | Who the call was attributed to – a package, or one of your own modules. |
| `resolved_by` | *How* it was attributed. See below. |
| `internal` | `TRUE` when the call used `:::` to reach a package’s internals. |
| `source_text` | The call as it appears in the source, so a CI log is enough to act on. |

`resolved_by` takes one of these values:

- `namespace` – written as `pkg::fn`.
- `namespace_internal` – written as `pkg:::fn`, reaching into internals.
- `local` – resolved to a function your own project defines.
- `export` – an unqualified call attributed to a declared dependency.
- `base` – an unqualified call attributed to a base package.
- `ambiguous` – more than one candidate; only present under
  `on_ambiguous = "fail"`.

To fix a violation you either move the call to the layer that should own
it, or you change the rule because the agreement was wrong. Both are
fine; leaving a suppressed violation behind is not an option the package
offers.

## Enforcing it in your test suite

[`arch_expect()`](https://fabiandistler.github.io/aRchtest/reference/arch_expect.md)
turns the same check into a `testthat` expectation:

``` r

test_that("UI must not compute statistics", {
  rule("UI must not compute statistics",
    why = "Presentation stays thin so the domain owns the numbers"
  ) |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = "stats") |>
    arch_expect()
})
```

The failure message names the rule, its rationale, and every finding. It
fails on violations, and it also fails when a selector matched **no file
at all** – a rule that selects nothing would otherwise pass vacuously,
which is worse than having no rule.

## Boundaries inside your own code

[`must_not_depend_on()`](https://fabiandistler.github.io/aRchtest/reference/must_not_depend_on.md)
holds one set of your modules away from another:

``` r

arch_check(
  rule("domain must not reach infrastructure",
    why = "Domain logic has to be testable without a store"
  ) |>
    modules_matching("R/domain_*.R") |>
    must_not_depend_on(modules = "R/infra_*.R"),
  root = project
)
#> <arch_result> 1 rule(s), 0 violation(s)
#>   root: /home/runner/work/_temp/Library/aRchtest/examples/layered (package)
#> 
#> * domain must not reach infrastructure -- 1 file(s) selected, 0 violation(s)
#>     why: Domain logic has to be testable without a store
#> 
#> resolution: 9 of 9 call site(s) resolved, 0 ambiguous, 0 unresolved  (4 file(s) parsed)
```

No `::` is required – the constraint works on ordinary unqualified calls
between your files, and a module calling a function it defines itself is
never a violation.

## Forbidding individual functions

Sometimes the package is fine and one function is not:

``` r

arch_check(
  rule("nothing here may shell out") |>
    modules_matching("R/*.R") |>
    must_not_call(functions = c("system", "setwd")),
  root = project
)
#> <arch_result> 1 rule(s), 1 violation(s)
#>   root: /home/runner/work/_temp/Library/aRchtest/examples/layered (package)
#> 
#> * nothing here may shell out -- 4 file(s) selected, 1 violation(s)
#>     R/infra_shell.R:2:3  in store_archive()  system -> base [base]  system(paste("tar -czf", path))
#> 
#> resolution: 9 of 9 call site(s) resolved, 0 ambiguous, 0 unresolved  (4 file(s) parsed)
```

Base packages count as declared dependencies, so a bare
[`system()`](https://rdrr.io/r/base/system.html) resolves to `base` and
the rule fires. A function your project defines itself always wins over
a package export of the same name, so a local helper named `system`
would not be reported.

## A whole architecture as a rule set

Pass a list and get one combined result. The project is discovered,
parsed and resolved **once**, no matter how many rules you check:

``` r

architecture <- list(
  rule("UI must not compute statistics") |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = "stats"),
  rule("domain must not reach infrastructure") |>
    modules_matching("R/domain_*.R") |>
    must_not_depend_on(modules = "R/infra_*.R")
)

combined <- arch_check(architecture, root = project)
combined$rules
#>                                    rule    why     patterns n_files
#>                                  <char> <char>       <char>   <int>
#> 1:       UI must not compute statistics   <NA>     R/ui_*.R       1
#> 2: domain must not reach infrastructure   <NA> R/domain_*.R       1
#>    empty_selection n_violations
#>             <lgcl>        <int>
#> 1:           FALSE            1
#> 2:           FALSE            0
```

Every violation row carries the rule that produced it, so a combined
result stays attributable.

## Projects without a DESCRIPTION

A Shiny app, a plumber API or a folder of scripts works the same way.
With no `DESCRIPTION` present, the declared dependencies come from the
[`library()`](https://rdrr.io/r/base/library.html) and
[`require()`](https://rdrr.io/r/base/library.html) calls in the
project’s own source instead:

``` r

app <- file.path(tempdir(), "shinyish")
dir.create(file.path(app, "R"), recursive = TRUE, showWarnings = FALSE)

writeLines(
  c("library(stats)", "", "server <- function(input, output) {", "  NULL", "}"),
  file.path(app, "app.R")
)
writeLines(
  c("mod_table_server <- function(id) {", "  median(id)", "}"),
  file.path(app, "R", "mod_table.R")
)

arch_check(
  rule("modules must not compute statistics") |>
    modules_matching("R/mod_*.R") |>
    must_not_call(packages = "stats"),
  root = app
)
#> <arch_result> 1 rule(s), 1 violation(s)
#>   root: /tmp/Rtmpkixvgf/shinyish (non-package)
#> 
#> * modules must not compute statistics -- 1 file(s) selected, 1 violation(s)
#>     R/mod_table.R:2:3  in mod_table_server()  median -> stats [base]  median(id)
#> 
#> resolution: 2 of 2 call site(s) resolved, 0 ambiguous, 0 unresolved  (2 file(s) parsed)
```

The bare [`median()`](https://rdrr.io/r/stats/median.html) call is
attributed to `stats` because `app.R` declares it with
[`library(stats)`](https://rdrr.io/r/base/library.html). Both the
[`library(pkg)`](https://rdrr.io/r/base/library.html) and the
[`require("pkg")`](https://rdrr.io/r/base/library.html) forms are
recognised. If a `DESCRIPTION` *is* present it wins, and
[`library()`](https://rdrr.io/r/base/library.html) calls are ignored.

## Trusting a passing check

This is the part worth reading twice, because a check that resolved
nothing looks exactly like a clean project.

Attributing a bare `dbGetQuery()` to `DBI` means asking `DBI` what it
exports, which requires **`DBI` to be installed** in the library path
running the check. That is rarely a burden – your test suite already
needs your dependencies – but a dependency that cannot be loaded
degrades resolution rather than erroring, and its calls land in the
unresolved bucket where they can never be violations.

Every result ends with a coverage line:

``` r

result$counts
#> $call_sites
#> [1] 9
#> 
#> $resolved
#> [1] 9
#> 
#> $ambiguous
#> [1] 0
#> 
#> $unresolved
#> [1] 0
```

- **`resolved` well below `call_sites`** means much of your code was not
  attributed, so the rule proved less than it looks like it did.
- **`AMBIGUOUS`** in the printed output means a symbol had more than one
  candidate package and `aRchtest` refused to guess. Qualify the call
  with `::`, or pass `on_ambiguous = "fail"` to treat ambiguity as a
  violation.
- **`DEGRADED`** means a declared dependency’s exports could not be
  enumerated. Install it and re-run before believing a green result.
- **`PARTIAL`** means a file did not parse and was skipped. The rest of
  the project was still analysed – which is what makes the tool usable
  mid-refactor – but the analysis is not complete.

## What this package deliberately does not do

Positive and allowlist constraints (`must_only_call()`),
layered-architecture helpers, dependency cycle detection, dynamic
dispatch resolution (S4, R6,
[`do.call()`](https://rdrr.io/r/base/do.call.html)), autofix,
visualisation and baselining of existing violations are all out of scope
for now. See the README for the reasoning behind each.
