# aRchtest 0.0.0.9001

Initial development release. `aRchtest` lets you declare architectural
boundaries as data and enforce them as ordinary `testthat` tests.

## The grammar

* `rule()` starts a rule with a name and an optional rationale. A rule is inert
  data: building one performs no analysis.
* `modules_matching()` and `modules_matching_regex()` narrow a rule to a set of
  files, by glob or by regular expression, relative to the project root.
* `must_not_call()` forbids packages, individual functions, or both.
* `must_not_depend_on()` forbids a dependency on other modules of the same
  project, so `domain/` can be held away from `infra/`.
* The verbs compose with the base R pipe; no magrittr or tidyverse dependency.

## Checking

* `arch_check()` returns an `arch_result` carrying a `data.table` of violations
  with one row per finding — rule, file, line, column, enclosing function,
  callee, resolved owner, how it was resolved, an internal-API flag and the
  source text of the call. A clean check returns an empty table with the same
  columns and types, never `NULL`.
* `arch_expect()` wraps the same check as a `testthat` expectation.
* `arch_violations()` accesses the violations table.
* `arch_check()` accepts a single rule or a list of them; the project is
  discovered, parsed and resolved once per check regardless of how many rules
  are supplied.
* `print()` and `format()` methods give a readable summary grouped by rule.

## Analysis

* The engine reads parse data only and never sources, loads or evaluates the
  code under analysis, so checks are deterministic and work on a project that
  does not currently run.
* Unqualified calls are resolved against declared dependencies, so a rule cannot
  be evaded by dropping the `::` prefix. Local definitions win over package
  exports.
* Base packages count as declared, so `must_not_call(functions = "system")`
  fires on a bare `system()` call.
* Declared dependencies come from `DESCRIPTION` for a package project and from
  `library()`/`require()` calls for a Shiny app, plumber API or script project.
* A symbol exported by more than one candidate is reported as **ambiguous**
  rather than guessed at, and `on_ambiguous = "fail"` makes ambiguity a
  violation.
* Calls that cannot be attributed are counted, never reported as violations, and
  the resolution counts are part of every result.
* A dependency whose exports cannot be enumerated degrades resolution visibly
  rather than erroring or reporting a falsely clean project.
* A file that does not parse is reported with a warning and skipped; the check
  still covers every other file and says the analysis was partial.
* A selector that matches no file fails the check rather than passing silently.
