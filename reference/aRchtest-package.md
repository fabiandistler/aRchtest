# aRchtest: Declare and Enforce Architectural Rules in 'testthat'

Declare architectural boundaries between the modules of an R project as
data and enforce them as ordinary 'testthat' tests. Rules are built with
a small pipe-friendly grammar, checked by static analysis of the
project's parse data, and reported as located findings naming the file,
line, enclosing function and offending call. The code under analysis is
never sourced, loaded or evaluated, so checks are deterministic, safe in
continuous integration, and work on a project that does not currently
run.

## See also

Useful links:

- <https://github.com/fabiandistler/aRchtest>

- <https://fabiandistler.github.io/aRchtest/>

- Report bugs at <https://github.com/fabiandistler/aRchtest/issues>

## Author

**Maintainer**: Fabian Distler <fdistlermpi@gmail.com>

Authors:

- Fabian Distler <fdistlermpi@gmail.com>
