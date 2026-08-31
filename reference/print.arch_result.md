# Print a check result

Prints a readable summary of an
[`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md)
result: every rule with the number of files it selected and the findings
grouped under it, followed by the resolution counts. A non-zero
ambiguous count, a dependency whose exports could not be enumerated, and
a file that could not be parsed are all called out, because each of them
means a passing check proves less than it appears to.

## Usage

``` r
# S3 method for class 'arch_result'
print(x, ...)
```

## Arguments

- x:

  An `arch_result` from
  [`arch_check()`](https://fabiandistler.github.io/aRchtest/reference/arch_check.md).

- ...:

  Ignored.

## Value

`x`, invisibly.

## Examples

``` r
project <- system.file("examples", "layered", package = "aRchtest")

print(arch_check(
  rule("no shelling out") |>
    modules_matching("R/*.R") |>
    must_not_call(functions = "system"),
  root = project
))
#> <arch_result> 1 rule(s), 1 violation(s)
#>   root: /home/runner/work/_temp/Library/aRchtest/examples/layered (package)
#> 
#> * no shelling out -- 4 file(s) selected, 1 violation(s)
#>     R/infra_shell.R:2:3  in store_archive()  system -> base [base]  system(paste("tar -czf", path))
#> 
#> resolution: 9 of 9 call site(s) resolved, 0 ambiguous, 0 unresolved  (4 file(s) parsed)
```
