arch_resolved_methods <- c(
  "namespace", "namespace_internal", "local", "export", "base"
)
arch_package_methods <- c("namespace", "namespace_internal", "export", "base")

#' Check architectural rules against a project
#'
#' `arch_check()` performs the analysis a rule describes and returns the
#' findings as data. It discovers the project's source files, parses them,
#' attributes every call it finds to an owner, and applies each rule's
#' constraints to the calls in the files that rule selects.
#'
#' The project under analysis is never sourced, loaded or evaluated -- only its
#' parse data is read. Checks are therefore deterministic, safe to run in
#' continuous integration, and work on a project that does not currently run.
#'
#' The project is discovered, parsed and resolved **once** per call regardless
#' of how many rules are supplied, so expressing more architecture does not
#' cost proportionally more time.
#'
#' # Resolving unqualified calls
#'
#' Attributing a bare `dbGetQuery()` to `DBI` means enumerating what `DBI`
#' exports, which requires the package to be **installed** in the library path
#' of the R session running the check. A declared dependency that cannot be
#' loaded degrades resolution rather than erroring: its calls fall into the
#' unresolved bucket and the package is listed in `unavailable_dependencies`.
#'
#' Read `counts` before trusting a clean result. A check that resolved little
#' of what it saw proves little, and a degraded pass looks exactly like a clean
#' project unless you look.
#'
#' @param rules A single `arch_rule` or a list of them. Rule names must be
#'   unique, so every finding stays attributable to the rule that produced it.
#' @param root Path to the project root to analyse. Defaults to the working
#'   directory. All file selection and every reported path is relative to this
#'   root, so rules read the same wherever the tests run from.
#' @param on_ambiguous What to do with a call whose symbol is exported by more
#'   than one candidate package and which is not defined locally.
#'   `"report"`, the default, puts such a call in the `ambiguous` table and
#'   keeps it out of `violations`. `"fail"` counts it as a violation.
#'
#' @return An `arch_result`: a list with
#'   * `violations` -- a `data.table` with one row per finding and columns
#'     `rule`, `file`, `line`, `column`, `enclosing_function`, `callee`,
#'     `owner`, `resolved_by`, `internal` and `source_text`. On success it is
#'     empty but has the same columns and types, never `NULL`.
#'   * `ambiguous` -- near misses that could not be attributed confidently.
#'   * `rules` -- one row per rule, with the number of files it selected,
#'     whether its selector matched nothing, and how many violations it found.
#'   * `selected_files` -- per rule, the files its selector matched.
#'   * `counts` -- call sites seen, resolved, ambiguous and unresolved.
#'   * `files_parsed`, `skipped_files` -- parse coverage.
#'   * `declared_dependencies`, `unavailable_dependencies` -- resolution inputs.
#'   * `root`, `is_package`, `on_ambiguous` -- how the check was scoped.
#' @export
#'
#' @examples
#' project <- system.file("examples", "layered", package = "aRchtest")
#'
#' result <- rule("UI must not reach the database") |>
#'   modules_matching("R/ui_*.R") |>
#'   must_not_call(packages = "stats") |>
#'   arch_check(root = project)
#'
#' result
#' result$violations
arch_check <- function(rules, root = ".", on_ambiguous = c("report", "fail")) {
  on_ambiguous <- match.arg(on_ambiguous)
  rules <- arch_as_rule_list(rules)

  analysis <- arch_analyse(root)
  sites <- analysis$sites

  violations <- vector("list", length(rules))
  ambiguous <- vector("list", length(rules))
  selected_files <- vector("list", length(rules))
  rule_names <- vapply(rules, function(r) r$name, character(1))
  rule_why <- vapply(
    rules,
    function(r) if (is.null(r$why)) NA_character_ else r$why,
    character(1)
  )
  empty_selection <- logical(length(rules))

  for (i in seq_along(rules)) {
    evaluated <- arch_evaluate_rule(
      rules[[i]], sites, analysis$project$files, on_ambiguous
    )
    violations[[i]] <- evaluated$violations
    ambiguous[[i]] <- evaluated$ambiguous
    selected_files[[i]] <- evaluated$files
    empty_selection[i] <- evaluated$empty_selection
  }
  names(selected_files) <- rule_names

  n_violations <- vapply(violations, nrow, integer(1))
  violations <- data.table::rbindlist(violations)
  ambiguous <- data.table::rbindlist(ambiguous)

  rule_table <- data.table::data.table(
    rule = rule_names,
    why = rule_why,
    patterns = vapply(
      rules,
      function(r) {
        patterns <- vapply(r$selectors, function(s) s$pattern, character(1))
        paste(patterns, collapse = ", ")
      },
      character(1)
    ),
    n_files = vapply(selected_files, length, integer(1), USE.NAMES = FALSE),
    empty_selection = empty_selection,
    n_violations = n_violations
  )

  arch_result(
    violations = violations,
    ambiguous = ambiguous,
    rules = rule_table,
    selected_files = selected_files,
    counts = arch_counts(sites),
    files_parsed = analysis$files_parsed,
    skipped_files = analysis$skipped,
    declared_dependencies = analysis$declared,
    unavailable_dependencies = analysis$unavailable,
    root = analysis$project$root,
    is_package = analysis$project$is_package,
    on_ambiguous = on_ambiguous
  )
}

arch_as_rule_list <- function(rules) {
  if (inherits(rules, "arch_rule")) {
    return(list(rules))
  }
  if (!is.list(rules) || !length(rules)) {
    stop(
      "`rules` must be a rule from rule(), or a non-empty list of them.",
      call. = FALSE
    )
  }
  ok <- vapply(rules, inherits, logical(1), "arch_rule")
  if (!all(ok)) {
    stop(
      "`rules` must contain only rules created with rule(); element(s) ",
      paste(which(!ok), collapse = ", "), " are not.",
      call. = FALSE
    )
  }

  names_used <- vapply(rules, function(r) r$name, character(1))
  duplicated_names <- unique(names_used[duplicated(names_used)])
  if (length(duplicated_names)) {
    stop(
      "Rule names must be unique so findings stay attributable; ",
      "repeated name(s): ",
      paste(sQuote(duplicated_names, q = FALSE), collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  rules
}

arch_analyse <- function(root) {
  project <- arch_discover(root)

  parsed <- lapply(project$files, function(rel) {
    arch_parse_file(file.path(project$root, rel), rel)
  })

  ok <- vapply(parsed, function(p) p$ok, logical(1))
  skipped <- data.table::data.table(
    file = project$files[!ok],
    reason = vapply(parsed[!ok], function(p) p$reason, character(1))
  )
  if (nrow(skipped)) {
    warning(
      "aRchtest skipped ", nrow(skipped), " file(s) that could not be parsed: ",
      paste(skipped$file, collapse = ", "),
      ". The analysis covers the remaining files only.",
      call. = FALSE
    )
  }

  usable <- parsed[ok]
  calls <- data.table::rbindlist(
    c(list(arch_empty_calls()), lapply(usable, function(p) p$calls))
  )
  defs <- data.table::rbindlist(
    c(list(arch_empty_defs()), lapply(usable, function(p) p$defs))
  )
  libraries <- sort(
    unique(unlist(lapply(usable, function(p) p$libraries), use.names = FALSE)),
    method = "radix"
  )

  declared <- if (project$is_package) {
    arch_declared_from_description(project$description)
  } else {
    libraries
  }
  if (is.null(declared)) {
    declared <- character()
  }

  declared_index <- arch_symbol_index(setdiff(declared, arch_base_packages))
  base_index <- arch_symbol_index(arch_base_packages)

  list(
    project = project,
    sites = arch_resolve(
      calls, arch_local_index(defs), declared_index$index, base_index$index
    ),
    skipped = skipped,
    files_parsed = sum(ok),
    declared = declared,
    unavailable = declared_index$unavailable
  )
}

arch_counts <- function(sites) {
  list(
    call_sites = nrow(sites),
    resolved = sum(sites$resolved_by %in% arch_resolved_methods),
    ambiguous = sum(sites$resolved_by == "ambiguous"),
    unresolved = sum(sites$resolved_by == "unresolved")
  )
}

arch_evaluate_rule <- function(rule, sites, files, on_ambiguous) {
  selected <- arch_select_files(files, rule$selectors)

  if (!length(selected)) {
    return(list(
      empty_selection = TRUE,
      files = character(),
      violations = arch_empty_violations(),
      ambiguous = arch_empty_ambiguous()
    ))
  }

  scoped <- sites[which(sites$file %in% selected)]
  violations <- list()
  ambiguous <- list()

  for (constraint in rule$constraints) {
    hits <- if (identical(constraint$type, "must_not_call")) {
      arch_match_must_not_call(scoped, constraint)
    } else {
      arch_match_must_not_depend_on(scoped, constraint, files)
    }

    violations[[length(violations) + 1L]] <- arch_violation_rows(
      scoped, hits$violation, rule$name
    )
    if (identical(on_ambiguous, "fail")) {
      violations[[length(violations) + 1L]] <- arch_violation_rows(
        scoped, hits$ambiguous, rule$name
      )
    } else {
      ambiguous[[length(ambiguous) + 1L]] <- arch_ambiguous_rows(
        scoped, hits$ambiguous, rule$name
      )
    }
  }

  violations <- data.table::rbindlist(
    c(list(arch_empty_violations()), violations)
  )
  ambiguous <- data.table::rbindlist(
    c(list(arch_empty_ambiguous()), ambiguous)
  )
  violations <- unique(violations)
  ambiguous <- unique(ambiguous)
  if (nrow(violations)) {
    data.table::setorderv(violations, c("file", "line", "column"))
  }
  if (nrow(ambiguous)) {
    data.table::setorderv(ambiguous, c("file", "line", "column"))
  }

  list(
    empty_selection = FALSE,
    files = selected,
    violations = violations,
    ambiguous = ambiguous
  )
}

arch_match_must_not_call <- function(scoped, constraint) {
  n <- nrow(scoped)
  violation <- rep(FALSE, n)
  ambiguous <- rep(FALSE, n)
  if (!n) {
    return(list(violation = violation, ambiguous = ambiguous))
  }

  attributed <- scoped$resolved_by %in% arch_package_methods
  unsure <- scoped$resolved_by == "ambiguous"

  if (length(constraint$packages)) {
    violation <- violation |
      (attributed & scoped$owner %in% constraint$packages)
    ambiguous <- ambiguous |
      (unsure & vapply(
        scoped$candidates,
        function(cand) any(cand %in% constraint$packages),
        logical(1)
      ))
  }

  if (length(constraint$functions)) {
    wanted <- arch_split_function_spec(constraint$functions)
    bare <- wanted$symbol[is.na(wanted$package)]
    qualified <- wanted[!is.na(wanted$package), ]

    if (length(bare)) {
      violation <- violation | (attributed & scoped$symbol %in% bare)
      ambiguous <- ambiguous | (unsure & scoped$symbol %in% bare)
    }
    if (nrow(qualified)) {
      key <- paste(scoped$owner, scoped$symbol, sep = "::")
      wanted_keys <- paste(qualified$package, qualified$symbol, sep = "::")
      violation <- violation | (attributed & key %in% wanted_keys)
      ambiguous <- ambiguous |
        (unsure & scoped$symbol %in% qualified$symbol & vapply(
          scoped$candidates,
          function(cand) any(cand %in% qualified$package),
          logical(1)
        ))
    }
  }

  list(violation = violation, ambiguous = ambiguous & !violation)
}

arch_split_function_spec <- function(functions) {
  has_ns <- grepl(":::?", functions)
  package <- ifelse(has_ns, sub(":::?.*$", "", functions), NA_character_)
  symbol <- ifelse(has_ns, sub("^.*:::?", "", functions), functions)
  data.frame(package = package, symbol = symbol, stringsAsFactors = FALSE)
}

arch_match_must_not_depend_on <- function(scoped, constraint, files) {
  n <- nrow(scoped)
  if (!n) {
    return(list(violation = logical(0), ambiguous = logical(0)))
  }

  forbidden <- arch_select_files(
    files,
    lapply(constraint$modules, function(p) {
      list(pattern = p, type = constraint$selector_type)
    })
  )

  violation <- scoped$resolved_by == "local" &
    scoped$owner %in% forbidden &
    scoped$owner != scoped$file

  list(violation = violation, ambiguous = rep(FALSE, n))
}

arch_violation_rows <- function(scoped, hit, rule_name) {
  if (!length(hit) || !any(hit)) {
    return(arch_empty_violations())
  }
  rows <- scoped[which(hit)]
  data.table::data.table(
    rule = rule_name,
    file = rows$file,
    line = rows$line,
    column = rows$column,
    enclosing_function = rows$enclosing_function,
    callee = rows$callee,
    owner = arch_owner_label(rows),
    resolved_by = rows$resolved_by,
    internal = rows$internal,
    source_text = rows$source_text
  )
}

arch_ambiguous_rows <- function(scoped, hit, rule_name) {
  if (!length(hit) || !any(hit)) {
    return(arch_empty_ambiguous())
  }
  rows <- scoped[which(hit)]
  data.table::data.table(
    rule = rule_name,
    file = rows$file,
    line = rows$line,
    column = rows$column,
    enclosing_function = rows$enclosing_function,
    callee = rows$callee,
    candidates = vapply(
      rows$candidates, paste, character(1), collapse = "|"
    ),
    source_text = rows$source_text
  )
}

arch_owner_label <- function(rows) {
  ifelse(
    rows$resolved_by == "ambiguous",
    vapply(rows$candidates, paste, character(1), collapse = "|"),
    rows$owner
  )
}
