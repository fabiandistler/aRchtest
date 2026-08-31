# Start an architectural rule

`rule()` opens a rule. A rule is inert data: building one performs no
analysis, so rules are cheap to construct, can be stored in a list, and
can be shared across tests. Add a selector with
[`modules_matching()`](https://fabiandistler.github.io/aRchtest/reference/modules_matching.md)
or
[`modules_matching_regex()`](https://fabiandistler.github.io/aRchtest/reference/modules_matching.md),
add a constraint with
[`must_not_call()`](https://fabiandistler.github.io/aRchtest/reference/must_not_call.md)
or
[`must_not_depend_on()`](https://fabiandistler.github.io/aRchtest/reference/must_not_depend_on.md),
and check it with
[`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md)
or
[`arch_expect()`](https://fabiandistler.github.io/aRchtest/reference/arch_expect.md).

## Usage

``` r
rule(name, why = NULL)
```

## Arguments

- name:

  A single string naming the rule. The name appears in every violation
  the rule produces and in the failure message, so it should read as the
  architectural agreement being enforced.

- why:

  An optional single string explaining *why* the boundary exists. It is
  shown in the failure message, so a future reader learns the rationale
  and not only that a line was crossed.

## Value

An `arch_rule` object.

## Examples

``` r
rule("UI must not reach the database", why = "Presentation stays thin")
#> <arch_rule> UI must not reach the database
#>   why: Presentation stays thin
#>   selects: <no selector yet>
```
