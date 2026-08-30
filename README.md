# aRchtest

Declare architectural boundaries between the modules of an R project as data,
and enforce them as ordinary `testthat` tests.

## The problem

R codebases — packages, Shiny apps, plumber APIs — have no way to declare and
enforce architectural boundaries. A team can agree that "UI code never talks to
the database directly", or that `domain/` must not depend on `infra/`, but
nothing checks it. The agreement lives in a README, a code review habit, or
someone's head.

The result is architectural drift that stays invisible until it hurts: a
`dbGetQuery()` call slipped into a Shiny module, a domain function reaching into
an infrastructure helper, a layering violation that only becomes obvious when
someone tries to swap the database or test the domain in isolation. By then the
violation is load-bearing and expensive to unwind.

R has no analogue to ArchUnit (Java), import-linter (Python) or
dependency-cruiser (JS). Visualisation shows you drift after the fact; it does
not stop the commit that causes it.

The problem has sharpened with coding agents. Agents produce architectural drift
fast, and they respond to deterministic, machine-readable feedback far better
than to prose conventions. A rule that fails in CI is a guardrail an agent can
act on; a paragraph in `CONTRIBUTING.md` is not.

## The headline example

```r
test_that("UI never touches the database directly", {
  rule("layering") |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = c("DBI", "RPostgres")) |>
    arch_expect()
})
```

When someone crosses the boundary, the test fails with every finding located:

```
Rule 'layering'
  2 violation(s):
    R/ui_dashboard.R:12:3  in render_table()  DBI::dbGetQuery -> DBI [namespace]  DBI::dbGetQuery(con, sql)
    R/ui_report.R:4:5      in render_report()  dbConnect -> DBI [export]          dbConnect(drv)
resolution: 41 of 44 call site(s) resolved, 0 ambiguous, 3 unresolved  (5 file(s) parsed)
```

## How it works

The analysis is purely static. `aRchtest` reads your project's parse data and
**never sources, loads or evaluates the code under analysis**. That makes checks
deterministic, safe to run in CI, fast, and usable on a project that does not
currently load — including a half-finished refactor.

Crucially, the checker resolves *unqualified* calls, not just `DBI::dbGetQuery()`.
A bare `dbGetQuery(conn, ...)` is attributed to `DBI` by consulting the project's
declared dependencies. A tool that only caught namespace-qualified calls would be
trivially evaded.

Calls are attributed in this order:

1. Namespace-qualified (`pkg::fn`, `pkg:::fn`) — attributed to `pkg`, with `:::`
   additionally flagged as an internal-API access.
2. Defined locally in the project — attributed to the defining module. Local
   definitions win, so a helper of yours that shadows a package export never
   produces a false violation.
3. Exported by a declared dependency — `DESCRIPTION` `Imports`/`Depends` for a
   package, `library()`/`require()` calls for a Shiny app, plumber API or script
   project.
4. Exported by a base package — `base`, `methods`, `utils`, `stats`, `graphics`,
   `grDevices`, `datasets`, so `must_not_call(functions = "system")` fires.
5. Otherwise unresolved — recorded and counted, never reported as a violation.

## Read the resolution counts

> **Dependency packages must be installed** for unqualified calls to be resolved.
> Attributing a bare `dbGetQuery()` to `DBI` means asking `DBI` what it exports,
> which requires `DBI` to be installed in the library path running the check.

A declared dependency that cannot be loaded **degrades resolution rather than
erroring**. Its calls fall into the unresolved bucket, and unresolved calls are
never violations — so a degraded check can look exactly like a clean project.

Every result therefore ends with a coverage line, and calls out anything that
makes a pass mean less than it appears to:

```
resolution: 41 of 44 call site(s) resolved, 0 ambiguous, 3 unresolved  (5 file(s) parsed)
DEGRADED: could not enumerate exports of RPostgres. Unqualified calls to these
  packages are NOT checked — install them and re-run before trusting a clean result.
PARTIAL: 1 file(s) could not be parsed and were skipped: R/wip.R.
  This analysis is not complete.
```

If you see `DEGRADED` or `PARTIAL`, fix that before you believe a green check. A
low resolved count means the same thing more quietly.

## Ambiguity is surfaced, never guessed

When an unqualified symbol is exported by more than one candidate package and is
not defined locally, `aRchtest` refuses to guess. The call goes into a distinct
`ambiguous` bucket with its candidates listed, and is **not** counted as a
violation by default:

```
AMBIGUOUS: 2 call site(s) could not be attributed to one package.
  Qualify them with :: or set on_ambiguous = "fail" to enforce.
```

Pass `on_ambiguous = "fail"` if you want a stricter posture.

## A rule that selects nothing fails

A vacuously green architecture test is worse than no test at all, so a selector
that matches no file fails the check with a distinct message naming the rule and
the pattern.

## Installation

```r
# install.packages("pak")
pak::pak("fabiandistler/aRchtest")
```

Add it to your project's `Suggests`, alongside `testthat`.

## What this package does not do

By design, out of scope for now:

- **Positive and allowlist constraints** — `must_only_call()`,
  `may_only_be_called_by()`. These need a complete resolution picture to be
  trustworthy; with unresolved symbols present, an allowlist rule cannot tell
  "called something not on the list" from "could not attribute the call".
- **Layered-architecture helpers** — a declarative `arch_layers()` expanding a
  layer ordering into a rule set.
- **Dependency cycle detection** between modules.
- **Dynamic dispatch resolution** — S4 generics and methods, R6 and reference
  class methods, and calls through `do.call()`, `get()` or `match.fun()`. These
  are recorded as unresolved rather than guessed at.
- **Reverse-dependency and transitive analysis.**
- **Non-R sources** — Rmd/qmd chunks, `inst/` scripts, C/C++ via `.Call()`,
  JavaScript in Shiny.
- **Autofix.** The package reports violations; it does not rewrite your code.
- **Visualisation.** `pkgnet` covers that ground; enforcement is the gap here.
- **A standalone CLI or GitHub Action.** Enforcement runs through `testthat`,
  which already runs in CI.
- **Configuration files.** Rules are R code in your test suite; there is no
  YAML or TOML rule format.
- **Baselining** existing violations so a rule can be adopted on a project that
  already breaks it.

## Documentation

`vignette("aRchtest")` walks through declaring an architecture for a package
project and for a non-package project, and through reading a failure.
