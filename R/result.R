arch_empty_violations <- function() {
  data.table::data.table(
    rule = character(),
    file = character(),
    line = integer(),
    column = integer(),
    enclosing_function = character(),
    callee = character(),
    owner = character(),
    resolved_by = character(),
    internal = logical(),
    source_text = character()
  )
}

arch_empty_ambiguous <- function() {
  data.table::data.table(
    rule = character(),
    file = character(),
    line = integer(),
    column = integer(),
    enclosing_function = character(),
    callee = character(),
    candidates = character(),
    source_text = character()
  )
}

arch_result <- function(violations, ambiguous, rules, selected_files, counts,
                        files_parsed, skipped_files, declared_dependencies,
                        unavailable_dependencies, root, is_package,
                        on_ambiguous) {
  structure(
    list(
      violations = violations,
      ambiguous = ambiguous,
      rules = rules,
      selected_files = selected_files,
      counts = counts,
      files_parsed = files_parsed,
      skipped_files = skipped_files,
      declared_dependencies = declared_dependencies,
      unavailable_dependencies = unavailable_dependencies,
      root = root,
      is_package = is_package,
      on_ambiguous = on_ambiguous
    ),
    class = "arch_result"
  )
}

#' The violations a check found
#'
#' A convenience accessor for the violations table of an [arch_check()] result.
#' The table has one row per finding and is a `data.table`, so it can be
#' filtered, grouped and summarised with tools you already use. When a check
#' passes it is empty but keeps the same columns and types, so code consuming
#' it needs no special case for success.
#'
#' @param result An `arch_result` from [arch_check()].
#'
#' @return A `data.table` of violations.
#' @export
#'
#' @examples
#' project <- system.file("examples", "layered", package = "aRchtest")
#'
#' rule("UI must not reach the database") |>
#'   modules_matching("R/ui_*.R") |>
#'   must_not_call(packages = "stats") |>
#'   arch_check(root = project) |>
#'   arch_violations()
arch_violations <- function(result) {
  if (!inherits(result, "arch_result")) {
    stop("`result` must come from arch_check().", call. = FALSE)
  }
  result$violations
}

arch_ok <- function(result) {
  nrow(result$violations) == 0L && !any(result$rules$empty_selection)
}

#' @export
format.arch_result <- function(x, ...) {
  out <- c(
    paste0(
      "<arch_result> ", nrow(x$rules), " rule(s), ",
      nrow(x$violations), " violation(s)"
    ),
    paste0("  root: ", x$root, if (x$is_package) " (package)" else " (non-package)")
  )

  for (i in seq_len(nrow(x$rules))) {
    out <- c(out, "", arch_format_rule(x, i))
  }

  out <- c(out, "", arch_format_coverage(x))
  out
}

arch_format_rule <- function(x, i) {
  name <- x$rules$rule[i]
  header <- paste0(
    "* ", name, " -- ", x$rules$n_files[i], " file(s) selected, ",
    x$rules$n_violations[i], " violation(s)"
  )
  out <- header

  if (!is.na(x$rules$why[i])) {
    out <- c(out, paste0("    why: ", x$rules$why[i]))
  }

  if (isTRUE(x$rules$empty_selection[i])) {
    out <- c(out, paste0("    ", arch_empty_selection_text(x, name)))
    return(out)
  }

  found <- x$violations[which(x$violations$rule == name)]
  if (nrow(found)) {
    out <- c(out, paste0("    ", arch_format_finding(found)))
  }

  unsure <- x$ambiguous[which(x$ambiguous$rule == name)]
  if (nrow(unsure)) {
    out <- c(
      out,
      paste0("    ambiguous, not counted as violations (", nrow(unsure), "):"),
      paste0("      ", arch_format_ambiguous(unsure))
    )
  }

  out
}

arch_empty_selection_text <- function(x, name) {
  patterns <- x$rules$patterns[match(name, x$rules$rule)]
  paste0(
    "EMPTY SELECTION: rule '", name, "' selected no file with pattern(s) ",
    patterns, ". A rule that selects nothing cannot pass -- fix the pattern."
  )
}

arch_format_finding <- function(found) {
  where <- ifelse(
    is.na(found$enclosing_function),
    "at top level",
    paste0("in ", found$enclosing_function, "()")
  )
  paste0(
    found$file, ":", found$line, ":", found$column, "  ", where,
    "  ", found$callee, " -> ", found$owner, " [", found$resolved_by,
    arch_internal_tag(found$internal), "]  ", found$source_text
  )
}

arch_internal_tag <- function(internal) {
  ifelse(internal %in% TRUE, ", internal API", "")
}

arch_format_ambiguous <- function(unsure) {
  where <- ifelse(
    is.na(unsure$enclosing_function),
    "at top level",
    paste0("in ", unsure$enclosing_function, "()")
  )
  paste0(
    unsure$file, ":", unsure$line, ":", unsure$column, "  ", where,
    "  ", unsure$callee, " -> one of ", unsure$candidates
  )
}

arch_format_coverage <- function(x) {
  counts <- x$counts
  out <- paste0(
    "resolution: ", counts$resolved, " of ", counts$call_sites,
    " call site(s) resolved, ", counts$ambiguous, " ambiguous, ",
    counts$unresolved, " unresolved  (", x$files_parsed, " file(s) parsed)"
  )

  if (counts$ambiguous > 0L) {
    out <- c(
      out,
      paste0(
        "AMBIGUOUS: ", counts$ambiguous,
        " call site(s) could not be attributed to one package. ",
        "Qualify them with :: or set on_ambiguous = \"fail\" to enforce."
      )
    )
  }

  if (length(x$unavailable_dependencies)) {
    out <- c(
      out,
      paste0(
        "DEGRADED: could not enumerate exports of ",
        paste(x$unavailable_dependencies, collapse = ", "),
        ". Unqualified calls to these packages are NOT checked -- ",
        "install them and re-run before trusting a clean result."
      )
    )
  }

  if (nrow(x$skipped_files)) {
    out <- c(
      out,
      paste0(
        "PARTIAL: ", nrow(x$skipped_files),
        " file(s) could not be parsed and were skipped: ",
        paste(x$skipped_files$file, collapse = ", "),
        ". This analysis is not complete."
      )
    )
  }

  out
}

#' Print a check result
#'
#' Prints a readable summary of an [arch_check()] result: every rule with the
#' number of files it selected and the findings grouped under it, followed by
#' the resolution counts. A non-zero ambiguous count, a dependency whose
#' exports could not be enumerated, and a file that could not be parsed are all
#' called out, because each of them means a passing check proves less than it
#' appears to.
#'
#' @param x An `arch_result` from [arch_check()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#' @export
#'
#' @examples
#' project <- system.file("examples", "layered", package = "aRchtest")
#'
#' print(arch_check(
#'   rule("no shelling out") |>
#'     modules_matching("R/*.R") |>
#'     must_not_call(functions = "system"),
#'   root = project
#' ))
print.arch_result <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}

arch_failure_message <- function(result) {
  lines <- character()

  for (i in seq_len(nrow(result$rules))) {
    name <- result$rules$rule[i]
    found <- result$violations[which(result$violations$rule == name)]
    empty <- isTRUE(result$rules$empty_selection[i])
    if (!nrow(found) && !empty) {
      next
    }

    lines <- c(lines, paste0("Rule '", name, "'"))
    if (!is.na(result$rules$why[i])) {
      lines <- c(lines, paste0("  why: ", result$rules$why[i]))
    }
    if (empty) {
      lines <- c(lines, paste0("  ", arch_empty_selection_text(result, name)))
    }
    if (nrow(found)) {
      lines <- c(
        lines,
        paste0("  ", nrow(found), " violation(s):"),
        paste0("    ", arch_format_finding(found))
      )
    }
  }

  passing <- result$rules$rule[
    result$rules$n_violations == 0L & !result$rules$empty_selection
  ]
  if (length(passing)) {
    lines <- c(
      lines,
      paste0("Passing rule(s): ", paste(passing, collapse = ", "))
    )
  }

  c(lines, arch_format_coverage(result))
}
