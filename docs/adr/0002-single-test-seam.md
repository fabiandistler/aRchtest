# ADR-0002: `arch_check()` is the single test seam

## Status

Accepted

## Context

Spec #2 commits to a single test seam — `arch_check(rule, root = <fixture project>)` —
and names it the design choice most worth pushing back on before implementation.
Issue #7 requires that the call be made deliberately and recorded, with the documented
fallback being to expose the resolved call-site table as a second, lower seam.

## Decision

`arch_check()` stays the single seam. Discovery, parsing, resolution and rule
evaluation are exercised only through it. The parse-data extractor, the symbol index
and the file matcher stay internal and unexported.

Resolver correctness is driven from fixture projects, and the `arch_result` is widened
to make resolution observable without exposing the internal call-site table: it carries
per-check resolution counts, the ambiguous-call table, the declared dependencies whose
exports could not be enumerated, and the files that could not be parsed.

## Consequences

- The four-stage pipeline can be reorganised without touching a single test.
- Every resolver edge case has to be expressible as a fixture project, which also
  proves the case matters end to end.
- Resolver behaviour is asserted through *observable consequences* — a violation
  appears, or a count moves — not by inspecting intermediate structures.
- If a future resolver bug proves genuinely undrivable from fixtures, the fallback
  remains open: export the resolved call-site table as a second seam. That would be a
  new decision superseding this one, not a silent widening.
