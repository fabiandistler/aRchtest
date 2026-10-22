# aRchtest (development version)

* `modules_excluding()` subtracts files from a rule's selection: the files a
  rule applies to are the union of its inclusion selectors minus the union of
  its exclusion selectors, so "only the API layer may call httr" can be written
  as `modules_matching("R/*.R")`, `modules_excluding("R/api_*.R")` and
  `must_not_call(packages = "httr")`. Exclusions combine, the check result and
  the rule's formatted output list them, and an exclusion that removes every
  selected file fails with EMPTY SELECTION naming both pattern sets (#24).
* File matching now uses PCRE (`perl = TRUE`) instead of TRE, so
  `modules_matching_regex()` accepts lookahead assertions such as
  `^R/(?!api_).*\\.R$` (#24).

# aRchtest 0.1.0

Initial release. `aRchtest` declares architectural boundaries between the
modules of an R project as data and enforces them as ordinary `testthat`
tests.

## New features

* `arch_check()` takes a single rule or a list of them and returns an
  `arch_result` carrying a `data.table` of violations with one row per finding:
  rule, file, line, column, enclosing function, callee, resolved owner, how it
  was resolved, an internal-API flag and the source text of the call. A clean
  check returns an empty table with the same columns and types, never `NULL`.
  The project is discovered, parsed and resolved once per check regardless of
  how many rules are supplied.
* `arch_expect()` wraps the same check as a `testthat` expectation.
* `arch_violations()` accesses the violations table.
* `print()` and `format()` methods give a readable summary grouped by rule.
* `modules_matching()` and `modules_matching_regex()` narrow a rule to a set of
  files, by glob or by regular expression, relative to the project root.
* `must_not_call()` forbids packages, individual functions, or both.
* `must_not_depend_on()` forbids a dependency on other modules of the same
  project, so `domain/` can be held away from `infra/`.
* `rule()` starts a rule with a name and an optional rationale. A rule is inert
  data: building one performs no analysis.
* Rules compose with the base R pipe; no magrittr or tidyverse dependency.

## Resolution

* The engine reads parse data only and never sources, loads or evaluates the
  code under analysis, so checks are deterministic and work on a project that
  does not currently run.
* Declared dependencies come from `DESCRIPTION` for a package project and from
  `library()`/`require()` calls for a Shiny app, plumber API or script project.
* Unqualified calls are resolved against declared dependencies, so a rule cannot
  be evaded by dropping the `::` prefix. Local definitions win over package
  exports.
* Base packages count as declared, so `must_not_call(functions = "system")`
  fires on a bare `system()` call.
* A symbol exported by more than one candidate is reported as ambiguous rather
  than guessed at, and `on_ambiguous = "fail"` makes ambiguity a violation.
* Calls that cannot be attributed are counted, never reported as violations, and
  the resolution counts are part of every result.
* A dependency whose exports cannot be enumerated degrades resolution visibly
  rather than erroring or reporting a falsely clean project.
* A file that does not parse is reported with a warning and skipped; the check
  still covers every other file and says the analysis was partial.
* A selector that matches no file fails the check rather than passing silently.

## Minor improvements and fixes

* `arch_check()` and `arch_expect()` find the project root when `root` is not
  given: they walk up from the working directory to the nearest directory
  holding a `DESCRIPTION` or an `.Rproj` file, and under `R CMD check` use the
  package sources in `<pkg>.Rcheck/00_pkg_src/<pkg>`. Previously the default
  `root = "."` pointed at `tests/testthat` under testthat, so the README
  example failed with EMPTY SELECTION on clean code. An explicit `root` is
  still used as given (#19).
* The EMPTY SELECTION message names the root the rule was checked against, so a
  wrong root is no longer reported as a wrong pattern (#19).
