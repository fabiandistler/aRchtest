# archtest — Specification

**ArchUnit for R.** Declare dependency rules between modules and enforce them as
`testthat` tests.

Status: design specification, pre-implementation. This document is the contract
the implementation is measured against; anything not stated here is open.

---

## 1. Problem

R codebases — packages, Shiny apps, plumber APIs — have no way to enforce
layering. There is no mechanism to state and check claims like:

- "UI code never calls `DBI` directly."
- "`domain/` imports nothing from `infra/`."
- "Nothing outside `R/db_*.R` opens a connection."

Architectural drift is therefore invisible until it hurts: a `dbGetQuery()` in a
Shiny observer, a domain function reaching into an HTTP client, a cycle between
two supposedly independent module groups. Review catches some of it; nothing
catches it in CI.

## 2. Gap

There is no R analogue to ArchUnit (Java), import-linter (Python), or
dependency-cruiser (JS).

| Package | What it does | Why it does not close the gap |
|---|---|---|
| `flow` | call graphs / flow diagrams | stale since 2023; visualisation, not enforcement |
| `dupree` | duplicate code detection | unmaintained; different problem |
| `pkgnet` | package dependency reports | reports and visualises; asserts nothing |
| `lintr` | style and code smells | per-expression linting; no notion of modules or cross-file edges |

`lintr` is the closest neighbour and the clearest boundary: it answers "is this
line well-formed?", `archtest` answers "is this file allowed to depend on that
one?".

## 3. Goals and non-goals

### Goals

- **G1** Build a call/dependency graph of an R project from `getParseData()`,
  without evaluating the code under analysis.
- **G2** Provide a small, pipe-friendly rule DSL over that graph.
- **G3** Fail as an ordinary `testthat` test, reporting every violation with
  `file:line:col`.
- **G4** Be deterministic: same sources in, same findings out, in a stable order.
- **G5** Be adoptable on an existing codebase without a big-bang cleanup
  (baseline, suppressions).
- **G6** Stay base-R-friendly: no hard dependency beyond `utils`.

### Non-goals

- **N1** Runtime/dynamic analysis. `archtest` never runs the target code.
- **N2** Resolving computed dispatch. `do.call(fname, ...)` with a non-literal
  `fname`, `eval(parse(text = ...))`, `get(paste0(...))` are reported as
  *unresolved*, never guessed.
- **N3** Visualisation. A graph is exposed as data; drawing it is someone
  else's package.
- **N4** Style linting. That is `lintr`'s job.
- **N5** Auto-fixing violations.

## 4. Concepts

### 4.1 Graph model

`arch_graph()` produces an immutable graph object.

**Nodes** carry a `kind`:

| kind | id example | meaning |
|---|---|---|
| `file` | `R/ui_dashboard.R` | a source file, path relative to project root |
| `function` | `R/ui_dashboard.R::render_kpi` | a function defined in the project |
| `package` | `DBI` | an external package |
| `unknown` | `<unresolved:dbGetQuery>` | a symbol that could not be resolved |

**Edges** carry a `kind`:

| kind | source → target | produced by |
|---|---|---|
| `call` | function/file → function/package/unknown | `f()`, `pkg::f()` |
| `use` | function/file → function/package/unknown | bare symbol reference to a known function (`lapply(x, dbGetQuery)`) |
| `attach` | file → package | `library()`, `require()`, `requireNamespace()` |
| `import` | project → package | `NAMESPACE` `import()` / `importFrom()` |
| `source` | file → file | `source("other.R")` with a literal path |

Every edge records the source location of the token that produced it
(`file`, `line`, `col`) and a `qualified` flag (`TRUE` for `::`/`:::`).
`:::` edges additionally carry `internal = TRUE` — useful on its own
(`must_not_use_internals()`).

### 4.2 Modules

A **module** is a named set of nodes. Modules are how rules address code.
They are defined by, in order of expressiveness:

```r
modules_matching("R/ui_*.R")                       # glob on file path
modules_matching(regex("^R/domain/"))              # regex on file path
module("ui", files = c("R/ui_dashboard.R", "R/ui_sidebar.R"))
modules_by_prefix("R/", pattern = "^([a-z]+)_")    # ui_*, domain_*, infra_* -> one module each
functions_matching("^validate_")                   # function-level module
```

A project-level registry keeps rules readable:

```r
arch_modules(
  ui     = "R/ui_*.R",
  domain = "R/domain_*.R",
  infra  = c("R/db_*.R", "R/http_*.R")
)
```

Once registered, rules refer to modules by name. A file matching two module
definitions belongs to both; that is legal and reported by
`arch_modules_overlap()` so it is at least visible.

## 5. Public API

### 5.1 Graph construction

```r
arch_graph(
  path        = ".",
  include     = NULL,            # globs; default: package R/ dir, else all .R/.r
  exclude     = c("tests/*", "man/*"),
  resolve     = c("static", "namespace"),
  strict      = FALSE            # TRUE: never loadNamespace(), ambiguity stays ambiguous
)
```

- `resolve = "static"` (default) resolves names from parse data plus DESCRIPTION
  and NAMESPACE metadata. Determining which package exports a bare symbol
  requires reading dependency exports; by default this uses
  `loadNamespace()` on **dependencies** (never on the project itself).
- `resolve = "namespace"` additionally loads the project via `pkgload::load_all()`
  and enriches with `codetools::findGlobals()`. Higher recall, requires the
  project to be loadable — opt-in only, and `pkgload`/`codetools` stay in
  `Suggests`.
- `strict = TRUE` forbids loading anything. Symbols that cannot be attributed to
  exactly one package become `ambiguous` edges listing candidates.

Methods: `print()`, `as.data.frame()` (edge list), `summary()`.

### 5.2 Rule DSL

A rule is built by piping. `rule()` opens it, a selector names the subject, one
or more constraints restrict it, a terminal evaluates it.

```r
rule("layering") |>
  modules_matching("R/ui_*.R") |>
  must_not_call(packages = c("DBI", "RPostgres")) |>
  arch_expect()
```

**Selectors** (exactly one per rule):

| function | subject |
|---|---|
| `modules_matching(x)` | files matching a glob or regex |
| `modules(...)` | named modules from the registry |
| `functions_matching(x)` | functions whose name matches a regex |
| `everything()` | the whole project |

**Constraints** (one or more; all must hold):

| function | asserts |
|---|---|
| `must_not_call(packages=, functions=, modules=)` | subject has no `call`/`use` edge to any listed target |
| `must_only_call(packages=, functions=, modules=)` | every outgoing edge targets something listed (allow-list) |
| `must_not_be_called_by(modules=)` | no incoming edge from those modules |
| `must_not_use(functions=)` | no use of listed functions/operators, e.g. `c("<<-", "assign", "setwd", "attach")` |
| `must_not_use_internals(packages=)` | no `:::` edges into those packages |
| `must_not_attach()` | no `library()`/`require()` calls (correct inside a package's `R/`) |
| `must_have_no_cycles()` | the induced module subgraph is acyclic |
| `must_have_no_unresolved()` | no `unknown`/`ambiguous` edges out of the subject |

**Layering shorthand** — expands to the transitive set of `must_not_call` rules,
which is the case this package exists for:

```r
arch_layers(ui > service > domain, allow_skip = FALSE) |> arch_expect()
```

Each layer may call the layer below it (and, unless `allow_skip = FALSE`, any
layer further down); calls upward are violations. `domain` calling `ui` is
reported, `ui` calling `domain` is not.

**Terminals**:

| function | returns |
|---|---|
| `arch_check(rule, graph = arch_graph())` | `arch_findings` data frame; never fails |
| `arch_expect(rule, graph = ..., baseline = NULL)` | a `testthat` expectation |
| `arch_report(rules, format = c("text", "json"))` | aggregate report |

Rules are ordinary values: they can be stored in a list, reused across graphs,
and printed. `arch_check()` on a rule with no constraints is an error, not an
empty pass — a rule that asserts nothing is a bug, not a green test.

### 5.3 Findings

`arch_findings` is a data frame with one row per violation and stable columns:

| column | type | content |
|---|---|---|
| `rule` | chr | rule name |
| `constraint` | chr | which constraint failed, e.g. `must_not_call` |
| `file` | chr | project-relative path |
| `line`, `col` | int | location of the offending token |
| `from` | chr | node id of the caller (function if known, else file) |
| `to` | chr | node id of the callee |
| `edge_kind` | chr | `call`, `use`, `attach`, … |
| `message` | chr | one-line human-readable explanation |
| `id` | chr | stable hash of (rule, from, to, edge_kind) — see §7 |

Ordering is deterministic: by `rule`, then `file`, then `line`, then `col`,
then `to`.

### 5.4 testthat integration

```r
# tests/testthat/test-architecture.R
test_that("UI does not talk to the database", {
  rule("ui-no-db") |>
    modules_matching("R/ui_*.R") |>
    must_not_call(packages = c("DBI", "RPostgres", "pool")) |>
    arch_expect()
})
```

`arch_expect()` calls `testthat::expect()` with `ok = nrow(findings) == 0`. The
failure message lists every finding, one per line, in
`path:line:col  from -> to` form so terminals and IDEs make them clickable, and
caps the list at 20 with an `… and N more` tail.

Building the graph is the expensive step, not checking rules. `arch_expect()`
takes `graph` explicitly, and `arch_graph()` memoises per (path, options,
source mtimes) within a session so a test file with twenty rules parses the
project once.

## 6. Adoption on an existing codebase

Two escape hatches, both deliberately visible.

**Baseline.** `arch_baseline_write(rules, path = "tests/testthat/_arch_baseline.json")`
records the finding `id`s that exist today. With
`arch_expect(baseline = "tests/testthat/_arch_baseline.json")`, only findings
absent from the baseline fail. Baseline entries that no longer match anything
are reported as stale, and `arch_baseline_strict = TRUE` makes staleness itself
a failure — so the baseline can only shrink.

**Inline suppression.** A comment on or directly above the offending line:

```r
con <- DBI::dbConnect(drv)  # archtest-ignore: ui-no-db -- legacy, see #142
```

Suppressions are read from parse-data comment tokens, must name a rule
(a bare `# archtest-ignore` is an error), and are counted in `arch_report()`.

## 7. Extraction and resolution

### 7.1 Parsing

For each file: `parse(file, keep.source = TRUE)` then `utils::getParseData()`.
No `eval`, no `source`, no `library` of the target.

Tokens of interest:

- `SYMBOL_FUNCTION_CALL` → callee of a `call` edge.
- `SYMBOL_PACKAGE` + `NS_GET` / `NS_GET_INT` → qualified call, package known
  exactly.
- `SYMBOL` matching a known function name → `use` edge (catches function values
  passed to `lapply`, `purrr::map`, etc.).
- `LEFT_ASSIGN` / `EQ_ASSIGN` / `RIGHT_ASSIGN` with a `FUNCTION` or `OP-LAMBDA`
  on the right → function definition; the assigned name becomes a `function`
  node.
- `COMMENT` → suppression directives.

The enclosing function of a token is found by walking the parse-data parent
chain to the nearest function-definition `expr`. Tokens with no such ancestor
belong to the file node — which is exactly right for top-level script code in
Shiny and plumber projects.

### 7.2 Name resolution

For an unqualified symbol `f` used at a given site, in order; first match wins:

1. A local binding — formal argument, or assignment earlier in the enclosing
   function. → no edge.
2. A top-level definition in the analysed project. → internal edge.
3. A `library()` / `require()` call in the same file, above the use site.
   → edge to that package. (Scripts only; `must_not_attach()` exists to forbid
   this pattern inside packages.)
4. `NAMESPACE`: `importFrom(pkg, f)` → `pkg`; `import(pkg)` → `pkg` if `pkg`
   exports `f`.
5. Exports of packages listed in DESCRIPTION `Imports`/`Depends`. Exactly one
   match → edge. More than one → `ambiguous` edge listing candidates.
6. `base` and the other base/recommended packages → edge to that package.
7. Otherwise → `unknown` node.

Shadowing is respected in one direction only: a project-local definition beats
an imported one (step 2 before 4), matching R's own search order for a package's
namespace. Locally rebinding a base function is reported by
`must_not_shadow_base()` rather than silently changing resolution.

### 7.3 Known limitations

Stated up front because they bound what a green test means:

- S4 (`setGeneric`/`setMethod`) and R5/R6 methods are attributed to the file
  and to the enclosing `setMethod`/`R6Class` call, not to a per-method node.
  Rules at module granularity work; rules at function granularity may miss.
- Method dispatch is not resolved: `print(x)` produces an edge to `print`, not
  to `print.myclass`.
- NSE-heavy code (`dplyr` masking, `rlang::eval_tidy`) resolves the verb, not
  the columns — which is the intended granularity, but worth knowing.
- Computed names are `unresolved` by construction (N2). A project that cares
  can assert `must_have_no_unresolved()` on its critical modules and take the
  false-positive cost knowingly.
- `source()` with a computed path is not followed.

## 8. Package shape

```
R/            graph.R  parse.R  resolve.R  modules.R  rules.R  constraints.R
              findings.R  baseline.R  expect.R  report.R
tests/testthat/
inst/examples/   package/  shiny/  plumber/   # fixture projects, also used as docs
```

- `Depends: R (>= 4.1)` — the native pipe is the DSL's spine.
- `Imports: utils` only.
- `Suggests: testthat (>= 3.0), pkgload, codetools, jsonlite, cli, withr`.
  `jsonlite` is needed for baseline/JSON report and degrades to a documented
  error when absent; `cli` is formatting only, with a base fallback.
- No `Remotes`, no compiled code.

## 9. Agent fit

Agents produce architectural drift fast, and the drift is exactly the kind a
human reviewer waves through. Deterministic, machine-readable CI feedback is
the guardrail, so it is a first-class output rather than an afterthought:

- `arch_report(format = "json")` emits the findings table verbatim — stable
  ids, absolute-from-root paths, line and column — so an agent can locate and
  fix without re-deriving anything.
- Findings ids are stable across unrelated edits, so "did my fix work?" is a
  set difference, not a diff of prose.
- The failure message names the rule and the constraint, so the intended
  invariant is legible from the failure alone.
- `arch_rules_template()` scaffolds `tests/testthat/test-architecture.R` from
  the current graph: it proposes modules from the file-name prefixes it finds
  and writes the rules commented out, for a human to un-comment. It never
  writes rules that already pass silently — a generated always-green test is
  worse than none.

## 10. Milestones

| # | Deliverable | Done when |
|---|---|---|
| M0 | Extractor and graph | `arch_graph()` on the three fixture projects yields the expected edge list; snapshot-tested |
| M1 | DSL core | `rule() \|> modules_matching() \|> must_not_call() \|> arch_expect()` — the motivating example — passes and fails correctly |
| M2 | Modules and layering | registry, `arch_layers()`, `must_have_no_cycles()` |
| M3 | Adoption | baseline, inline suppressions, JSON report |
| M4 | Non-package targets | Shiny app dirs, plumber files, `source()` following |
| M5 | Release | pkgdown site, `R CMD check` clean on three platforms, CRAN submission |

M1 is the point at which the package is useful to its author; M3 is the point
at which it is useful to anyone else.

## 11. Open questions

1. **Module registry scope.** Global option, a `arch_modules()` call at the top
   of the test file, or a declarative `inst/architecture.R` the package reads?
   Leaning: the test-file call, with the file as an optional convention.
2. **`must_only_call` and base R.** An allow-list rule that does not implicitly
   permit `base` is unusable; one that does is surprising. Leaning: implicit
   `base` allow, with `allow_base = FALSE` to opt out.
3. **Transitive rules.** Should `must_not_call` consider transitive paths
   (`ui -> util -> DBI`)? Direct-only is predictable and cheap; transitive is
   what the architect actually means. Leaning: direct by default, with
   `transitive = TRUE`, and findings that report the full path.
4. **`resolve = "namespace"` as default** once it proves stable, or permanently
   opt-in? Depends on how much recall step 7.2/5 loses in practice.
5. **Non-R sources.** Shiny modules split across `ui.R`/`server.R`/`global.R`
   have implicit ordering that `source()` following does not capture. Worth a
   dedicated project type in M4?
