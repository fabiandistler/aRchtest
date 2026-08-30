# ADR-0001: The analysis engine reads parse data and never evaluates project code

## Status

Accepted

## Context

Spec #2 sketched an engine built on `getParseData()` *plus* `codetools`. `codetools`
(`findGlobals()`, `checkUsage()`) operates on evaluated closures, not on source text.
Using it would require sourcing or loading the project under analysis, which forfeits
determinism, breaks analysis of projects that do not currently load, and makes CI runs
inherit the project's runtime environment.

## Decision

The engine is built on `utils::getParseData()` alone. `aRchtest` never sources, loads
or evaluates the code of the project under analysis. `codetools` is not a dependency.

Namespaces of the project's *declared dependencies* are loaded, because enumerating a
package's exports requires it. That is a different thing from evaluating the project.

## Consequences

- Analysis is deterministic and safe to run in CI.
- A project that does not currently load, or does not currently parse, still yields
  architecture feedback.
- Dynamic dispatch (S4, R6, `do.call()`, `get()`) cannot be resolved and is recorded
  as unresolved rather than guessed at.
