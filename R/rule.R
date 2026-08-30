#' Start an architectural rule
#'
#' `rule()` opens a rule. A rule is inert data: building one performs no
#' analysis, so rules are cheap to construct, can be stored in a list, and can
#' be shared across tests. Add a selector with [modules_matching()] or
#' [modules_matching_regex()], add a constraint with [must_not_call()] or
#' [must_not_depend_on()], and check it with [arch_check()] or
#' [arch_expect()].
#'
#' @param name A single string naming the rule. The name appears in every
#'   violation the rule produces and in the failure message, so it should read
#'   as the architectural agreement being enforced.
#' @param why An optional single string explaining *why* the boundary exists.
#'   It is shown in the failure message, so a future reader learns the
#'   rationale and not only that a line was crossed.
#'
#' @return An `arch_rule` object.
#' @export
#'
#' @examples
#' rule("UI must not reach the database", why = "Presentation stays thin")
rule <- function(name, why = NULL) {
  bad_name <- !is.character(name) || length(name) != 1L ||
    is.na(name) || !nzchar(name)
  if (bad_name) {
    stop("`name` must be a single non-empty string.", call. = FALSE)
  }
  if (!is.null(why)) {
    if (!is.character(why) || length(why) != 1L || is.na(why)) {
      stop(
        "Rule '", name, "': `why` must be a single string or NULL.",
        call. = FALSE
      )
    }
  }

  structure(
    list(
      name = name,
      why = why,
      selectors = list(),
      constraints = list()
    ),
    class = "arch_rule"
  )
}

#' Select the modules a rule applies to
#'
#' `modules_matching()` narrows a rule to the files matched by a glob pattern.
#' `modules_matching_regex()` does the same with a regular expression, for when
#' file naming is too irregular for a glob. Both match against paths relative
#' to the project root, so a rule reads the same wherever the tests are run
#' from.
#'
#' In a glob, `*` matches any run of characters within one path segment, `**`
#' matches across segments, and `?` matches a single character within a
#' segment. Everything else is literal. Reach for the regex variant only when a
#' glob cannot express the selection -- a glob is easier for the next reader.
#'
#' Calling a selector more than once on the same rule widens the selection: a
#' file is selected if it matches any of the rule's patterns.
#'
#' @param rule An `arch_rule` from [rule()].
#' @param pattern A single glob pattern (`modules_matching()`) or regular
#'   expression (`modules_matching_regex()`), matched against file paths
#'   relative to the project root.
#' @param ... Not used. Present so a misspelled argument errors here rather
#'   than surfacing later as a confusing check result.
#'
#' @return The rule, with the selector attached.
#' @export
#'
#' @examples
#' rule("layering") |> modules_matching("R/ui_*.R")
#'
#' rule("layering") |> modules_matching_regex("^R/(ui|view)_.*\\.R$")
modules_matching <- function(rule, pattern, ...) {
  arch_add_selector(rule, pattern, "glob", ...)
}

#' @rdname modules_matching
#' @export
modules_matching_regex <- function(rule, pattern, ...) {
  arch_add_selector(rule, pattern, "regex", ...)
}

arch_add_selector <- function(rule, pattern, type, ...) {
  arch_assert_rule(rule, "modules_matching")
  arch_reject_extra(rule, list(...), "modules_matching")
  arch_assert_strings(pattern, "pattern", rule$name)
  if (length(pattern) != 1L) {
    stop(
      "Rule '", rule$name, "': `pattern` must be a single string.",
      call. = FALSE
    )
  }

  rule$selectors <- c(
    rule$selectors,
    list(list(type = type, pattern = pattern))
  )
  rule
}

#' Forbid calls to packages or functions
#'
#' `must_not_call()` states that the modules a rule selects must not call the
#' given packages, the given functions, or both. It is a negative constraint:
#' it never asserts what the modules *may* call.
#'
#' A call is attributed to an owner before the constraint is applied, so both
#' `DBI::dbGetQuery()` and a bare `dbGetQuery()` are caught -- a rule cannot be
#' evaded by dropping the `::` prefix. A call the analysis cannot attribute is
#' never reported as a violation; see [arch_check()] for how to read the
#' resolution counts that tell you how much was attributed.
#'
#' Base packages count as declared, so `functions = "system"` fires on a bare
#' `system()` call. A function the project defines itself always wins over a
#' package export of the same name, so a local helper never produces a
#' violation.
#'
#' @param rule An `arch_rule` that already has a selector.
#' @param ... Not used. Present so a misspelled argument errors here rather
#'   than surfacing later as a confusing check result.
#' @param packages A character vector of package names the selected modules
#'   must not call.
#' @param functions A character vector of function names the selected modules
#'   must not call. Bare names such as `"system"` match the function whoever
#'   owns it; qualified names such as `"utils::head"` match only that owner.
#'
#' @return The rule, with the constraint attached.
#' @export
#'
#' @examples
#' rule("UI must not reach the database") |>
#'   modules_matching("R/ui_*.R") |>
#'   must_not_call(packages = c("DBI", "RPostgres"))
#'
#' rule("No shelling out") |>
#'   modules_matching("R/*.R") |>
#'   must_not_call(functions = c("system", "setwd"))
must_not_call <- function(rule, ..., packages = NULL, functions = NULL) {
  arch_assert_rule(rule, "must_not_call")
  arch_reject_extra(rule, list(...), "must_not_call")
  arch_require_selector(rule, "must_not_call")

  if (is.null(packages) && is.null(functions)) {
    stop(
      "Rule '", rule$name,
      "': must_not_call() needs `packages`, `functions`, or both.",
      call. = FALSE
    )
  }
  if (!is.null(packages)) {
    arch_assert_strings(packages, "packages", rule$name)
  }
  if (!is.null(functions)) {
    arch_assert_strings(functions, "functions", rule$name)
  }

  rule$constraints <- c(
    rule$constraints,
    list(list(
      type = "must_not_call",
      packages = packages,
      functions = functions
    ))
  )
  rule
}

#' Forbid a dependency on other modules of the same project
#'
#' `must_not_depend_on()` enforces a boundary inside your own code rather than
#' against an external package. The modules a rule selects must not call
#' functions defined in the modules named here, so a `domain/` file reaching
#' into an `infra/` helper fails with the same located finding an external
#' violation would produce.
#'
#' Forbidden modules are named with the same selector vocabulary the rule's own
#' selector uses, resolved relative to the project root. No `::` is required:
#' the constraint works on ordinary unqualified calls between project files. A
#' module calling a function it defines itself is never a violation.
#'
#' @param rule An `arch_rule` that already has a selector.
#' @param ... Not used. Present so a misspelled argument errors here rather
#'   than surfacing later as a confusing check result.
#' @param modules A character vector of patterns naming the forbidden modules.
#' @param regex Whether `modules` are regular expressions. The default, `FALSE`,
#'   reads them as globs, matching [modules_matching()].
#'
#' @return The rule, with the constraint attached.
#' @export
#'
#' @examples
#' rule("domain must not know about infrastructure") |>
#'   modules_matching("R/domain_*.R") |>
#'   must_not_depend_on(modules = "R/infra_*.R")
must_not_depend_on <- function(rule, ..., modules, regex = FALSE) {
  arch_assert_rule(rule, "must_not_depend_on")
  arch_reject_extra(rule, list(...), "must_not_depend_on")
  arch_require_selector(rule, "must_not_depend_on")

  if (missing(modules)) {
    stop(
      "Rule '", rule$name, "': must_not_depend_on() needs `modules`.",
      call. = FALSE
    )
  }
  arch_assert_strings(modules, "modules", rule$name)
  if (!is.logical(regex) || length(regex) != 1L || is.na(regex)) {
    stop(
      "Rule '", rule$name, "': `regex` must be TRUE or FALSE.",
      call. = FALSE
    )
  }

  rule$constraints <- c(
    rule$constraints,
    list(list(
      type = "must_not_depend_on",
      modules = modules,
      selector_type = if (regex) "regex" else "glob"
    ))
  )
  rule
}

#' @export
print.arch_rule <- function(x, ...) {
  cat("<arch_rule> ", x$name, "\n", sep = "")
  if (!is.null(x$why)) {
    cat("  why: ", x$why, "\n", sep = "")
  }
  if (length(x$selectors)) {
    for (selector in x$selectors) {
      cat("  selects: ", selector$pattern, " (", selector$type, ")\n", sep = "")
    }
  } else {
    cat("  selects: <no selector yet>\n")
  }
  for (constraint in x$constraints) {
    if (identical(constraint$type, "must_not_call")) {
      if (length(constraint$packages)) {
        cat(
          "  must not call packages: ",
          paste(constraint$packages, collapse = ", "), "\n",
          sep = ""
        )
      }
      if (length(constraint$functions)) {
        cat(
          "  must not call functions: ",
          paste(constraint$functions, collapse = ", "), "\n",
          sep = ""
        )
      }
    } else {
      cat(
        "  must not depend on modules: ",
        paste(constraint$modules, collapse = ", "), "\n",
        sep = ""
      )
    }
  }
  invisible(x)
}

arch_assert_rule <- function(rule, verb) {
  if (!inherits(rule, "arch_rule")) {
    stop(
      "`", verb, "()` must be applied to a rule created with rule().",
      call. = FALSE
    )
  }
  invisible(rule)
}

arch_require_selector <- function(rule, verb) {
  if (!length(rule$selectors)) {
    stop(
      "Rule '", rule$name, "': ", verb,
      "() needs a selector first -- add modules_matching() ",
      "or modules_matching_regex() before the constraint.",
      call. = FALSE
    )
  }
  invisible(rule)
}

arch_reject_extra <- function(rule, extra, verb) {
  if (!length(extra)) {
    return(invisible(NULL))
  }
  named <- names(extra)
  named <- named[nzchar(named)]
  detail <- if (length(named)) {
    paste0("unknown argument(s): ", paste(named, collapse = ", "))
  } else {
    paste0(length(extra), " unnamed argument(s)")
  }
  stop(
    "Rule '", rule$name, "': ", verb, "() received ", detail,
    ". Check the spelling against ?", verb, ".",
    call. = FALSE
  )
}

arch_assert_strings <- function(x, argument, rule_name) {
  if (!is.character(x)) {
    stop(
      "Rule '", rule_name, "': `", argument,
      "` must be a character vector, not ", class(x)[1L], ".",
      call. = FALSE
    )
  }
  if (!length(x)) {
    stop(
      "Rule '", rule_name, "': `", argument, "` must not be empty.",
      call. = FALSE
    )
  }
  if (anyNA(x)) {
    stop(
      "Rule '", rule_name, "': `", argument, "` must not contain NA.",
      call. = FALSE
    )
  }
  if (any(!nzchar(x))) {
    stop(
      "Rule '", rule_name, "': `", argument,
      "` must not contain empty strings.",
      call. = FALSE
    )
  }
  invisible(x)
}

arch_glob_to_regex <- function(pattern) {
  chars <- strsplit(pattern, "", fixed = TRUE)[[1L]]
  out <- character(0)
  i <- 1L
  while (i <= length(chars)) {
    ch <- chars[i]
    if (ch == "*") {
      if (i < length(chars) && chars[i + 1L] == "*") {
        out <- c(out, ".*")
        i <- i + 2L
        next
      }
      out <- c(out, "[^/]*")
    } else if (ch == "?") {
      out <- c(out, "[^/]")
    } else if (grepl("^[[:alnum:]_/-]$", ch)) {
      out <- c(out, ch)
    } else {
      out <- c(out, paste0("\\", ch))
    }
    i <- i + 1L
  }
  paste0("^", paste(out, collapse = ""), "$")
}

arch_match_files <- function(files, pattern, type) {
  regex <- if (identical(type, "glob")) arch_glob_to_regex(pattern) else pattern
  files[grepl(regex, files)]
}

arch_select_files <- function(files, selectors) {
  matched <- unlist(
    lapply(selectors, function(s) arch_match_files(files, s$pattern, s$type)),
    use.names = FALSE
  )
  sort(unique(matched), method = "radix")
}
