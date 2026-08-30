# ADR-0003: Base packages are implicitly declared, in a second resolution tier

## Status

Accepted

## Context

Issue #11 (`must_not_call(functions =)`) is unfirable under the resolution order as
spec #2 states it. Walk `system()` through it: not namespace-qualified, not defined
locally, and not exported by a declared dependency — base and recommended packages do
not appear in `DESCRIPTION` `Imports`/`Depends`. It resolves as *unresolved*, and an
unresolved call is never a violation of a negative rule. So
`must_not_call(functions = "system")` would silently pass — the worst failure mode
this package has.

Issue #11 offered two options: (a) treat base packages as implicitly declared, or
(b) match `functions =` on symbol name before resolution runs. Issue #7 notes that (a)
is a change to the resolver, not to #11, and must be settled in the resolver.

## Decision

Option (a), with a refinement that removes its main cost.

Declared dependencies are resolved in **two tiers**:

1. **Tier 1 — declared dependencies.** For a package project, `DESCRIPTION` `Imports`
   and `Depends`. For a non-package project, packages named in `library()` and
   `require()` calls in the project's own source.
2. **Tier 2 — implicitly declared base packages.** `base`, `methods`, `utils`,
   `stats`, `graphics`, `grDevices`, `datasets` — exactly the packages R attaches by
   default, so an unqualified call to one of them resolves in a plain R session.

Tier 2 **resolves** a symbol only when tier 1 produces no candidate, but tier 2
candidates are always unioned in for **ambiguity detection**.

Strict tiering alone had a false-positive hole. A project with `Imports: Matrix` that
calls bare `head(x)` would attribute the call to `Matrix`, and
`must_not_call(packages = "Matrix")` would fire on ordinary `head()` — a violation the
user's code did not commit. Unioning tier 2 in for ambiguity detection sends that call
to the ambiguous bucket instead, which is the honest answer: given only `DESCRIPTION`
information, `head()` in that project genuinely could be either.

The cost is that a symbol clashing with a base export — `filter` in a project that
imports `dplyr` — becomes ambiguous rather than resolved. That is accepted: it is true
at the level of information the resolver has, and the spec's stated posture is that the
tool never quietly guesses. Ambiguity is reported, not failed, under the default policy.

Recommended packages (`MASS`, `Matrix`, `survival`, …) are *not* implicit. They are not
attached by default, so code calling them unqualified must declare them, and they show
up in tier 1 like any other dependency.

## Consequences

- `must_not_call(functions = "system")` fires on a bare `system()` call, resolved to
  `base`. The existing negative-rule machinery applies unchanged; no separate
  pre-resolution matching path exists.
- The unresolved bucket shrinks across the board, and resolution-coverage counts become
  more meaningful: what remains unresolved is genuinely unattributable — dynamic
  dispatch, undeclared packages, typos — rather than "was a base call". Documentation
  of the counts says so explicitly.
- No unqualified call to a base function can be attributed to a declared package that
  happens to export the same name. Attribution is either unambiguous or reported as
  ambiguous; it is never a guess between the two.
- The ambiguity fixtures use two pairs that ship with every R installation, so they
  need no new dependency in CI: `stats` and `Matrix` both export `toeplitz`, and
  `utils` and `Matrix` both export `head`. `Matrix` is declared in `Suggests`, and
  the tests that rely on it call `skip_if_not_installed("Matrix")`.
- A project *can* forbid a base package wholesale — `must_not_call(packages = "base")`
  is meaningful and will fire broadly. That is the user's choice to make.
- Local definitions still win over both tiers, so a project helper named `system`
  suppresses the violation.
