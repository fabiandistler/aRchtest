arch_source_text_limit <- 200L

arch_empty_calls <- function() {
  data.table::data.table(
    file = character(),
    line = integer(),
    column = integer(),
    enclosing_function = character(),
    callee = character(),
    symbol = character(),
    package = character(),
    internal = logical(),
    dynamic = logical(),
    source_text = character()
  )
}

arch_empty_defs <- function() {
  data.table::data.table(file = character(), name = character())
}

arch_empty_nested_defs <- function() {
  data.table::data.table(
    file = character(),
    scope = character(),
    symbol = character()
  )
}

arch_parse_file <- function(abs_path, rel_path) {
  blank <- list(
    ok = TRUE,
    reason = NA_character_,
    calls = arch_empty_calls(),
    value_uses = arch_empty_calls(),
    defs = arch_empty_defs(),
    nested_defs = arch_empty_nested_defs(),
    libraries = character()
  )

  exprs <- tryCatch(
    parse(abs_path, keep.source = TRUE),
    error = function(e) e
  )
  if (inherits(exprs, "condition")) {
    return(list(
      ok = FALSE,
      reason = conditionMessage(exprs),
      calls = arch_empty_calls(),
      value_uses = arch_empty_calls(),
      defs = arch_empty_defs(),
      nested_defs = arch_empty_nested_defs(),
      libraries = character()
    ))
  }

  pd <- utils::getParseData(exprs)
  if (is.null(pd) || nrow(pd) == 0L) {
    return(blank)
  }

  lines <- tryCatch(
    readLines(abs_path, warn = FALSE),
    error = function(e) character()
  )

  nav <- arch_parse_nav(pd)
  defs <- arch_function_definitions(pd, nav)
  calls <- arch_call_sites(pd, nav, defs$names, lines, rel_path)
  value_uses <- arch_value_uses(pd, nav, defs$names, lines, rel_path)

  nested <- defs$nested[!is.na(defs$nested$scope), ]
  nested_defs <- data.table::data.table(
    file = rep(rel_path, nrow(nested)),
    scope = nested$scope,
    symbol = nested$symbol
  )

  list(
    ok = TRUE,
    reason = NA_character_,
    calls = calls,
    value_uses = value_uses,
    defs = data.table::data.table(
      file = rep(rel_path, length(defs$defined)),
      name = defs$defined
    ),
    nested_defs = nested_defs,
    libraries = arch_library_calls(pd, nav)
  )
}

arch_parse_nav <- function(pd) {
  by_parent <- split(seq_len(nrow(pd)), pd$parent)
  list(
    pd = pd,
    ids = pd$id,
    by_parent = by_parent
  )
}

arch_row_of <- function(nav, id) {
  match(id, nav$ids)
}

arch_children <- function(nav, id) {
  k <- nav$by_parent[[as.character(id)]]
  if (is.null(k)) integer() else k
}

arch_unquote <- function(x) {
  x <- sub("^[\"'`]", "", x)
  sub("[\"'`]$", "", x)
}

arch_function_definitions <- function(pd, nav) {
  is_fun <- pd$token == "FUNCTION" | (pd$terminal & pd$text == "\\")
  def_ids <- unique(pd$parent[is_fun])
  def_ids <- def_ids[!is.na(def_ids) & def_ids > 0L]

  named <- vapply(
    def_ids, function(d) arch_definition_name(d, nav), character(1)
  )
  names(named) <- as.character(def_ids)

  named_ok <- !is.na(named)
  top_level <- vapply(
    def_ids, function(d) arch_def_is_top_level(d, nav), logical(1)
  )
  names(top_level) <- as.character(def_ids)

  enclosing <- vapply(
    def_ids[named_ok], function(d) arch_enclosing_function(d, nav, named),
    character(1)
  )
  not_top <- !top_level[named_ok]
  nested <- data.table::data.table(
    scope = enclosing[not_top],
    symbol = named[named_ok][not_top]
  )

  list(
    # `names` keeps every named definition, nested or not: it locates the
    # function a call sits in. `defined` feeds the project-wide index and
    # therefore must hold top-level definitions only -- a nested `all <-
    # function(...)` inside build_site() would otherwise shadow every
    # `all()` call in the whole project (see issue #20). `nested` records
    # where nested definitions live, so their calls stay attributable
    # inside their enclosing function.
    names = named,
    defined = sort(unique(named[named_ok & top_level]), method = "radix"),
    nested = nested
  )
}

# A definition is top level when the expression that assigns the function is
# a statement of the file itself, optionally wrapped once in braces (braces
# do not create a scope in R). The walk from the assignment expression may
# therefore take at most two hops to reach the file root (the expr whose own
# parent id is 0), and the holding statement must not be an `if`, `while` or
# `for` statement, because a definition reached like that may never run and
# must not claim ownership across the project.
arch_def_is_top_level <- function(def_id, nav) {
  pd <- nav$pd
  r_def <- arch_row_of(nav, def_id)
  if (is.na(r_def)) {
    return(FALSE)
  }
  asgn_id <- pd$parent[r_def]
  current <- asgn_id
  for (hop in 1:2) {
    r_cur <- arch_row_of(nav, current)
    if (is.na(r_cur)) {
      return(FALSE)
    }
    if (pd$parent[r_cur] == 0L) {
      holder_tokens <- pd$token[arch_children(nav, pd$id[r_cur])]
      return(!any(holder_tokens %in% c("IF", "WHILE", "FOR")))
    }
    current <- pd$parent[r_cur]
  }
  FALSE
}

arch_definition_name <- function(def_id, nav) {
  pd <- nav$pd
  r <- arch_row_of(nav, def_id)
  if (is.na(r)) {
    return(NA_character_)
  }
  parent_id <- pd$parent[r]
  if (is.na(parent_id) || parent_id <= 0L) {
    return(NA_character_)
  }

  kids <- arch_children(nav, parent_id)
  if (!length(kids)) {
    return(NA_character_)
  }
  toks <- pd$token[kids]
  assign_at <- which(toks %in% c("LEFT_ASSIGN", "EQ_ASSIGN", "RIGHT_ASSIGN"))
  if (!length(assign_at)) {
    return(NA_character_)
  }

  at <- assign_at[1L]
  name_at <- if (identical(toks[at], "RIGHT_ASSIGN")) at + 1L else at - 1L
  if (name_at < 1L || name_at > length(kids)) {
    return(NA_character_)
  }

  arch_symbol_text(pd$id[kids[name_at]], nav)
}

arch_symbol_text <- function(id, nav) {
  pd <- nav$pd
  r <- arch_row_of(nav, id)
  if (!is.na(r) && pd$terminal[r]) {
    return(if (pd$token[r] %in% c("SYMBOL", "STR_CONST")) {
      arch_unquote(pd$text[r])
    } else {
      NA_character_
    })
  }
  kids <- arch_children(nav, id)
  if (!length(kids)) {
    return(NA_character_)
  }
  hit <- kids[pd$token[kids] %in% c("SYMBOL", "STR_CONST")]
  if (!length(hit)) {
    return(NA_character_)
  }
  arch_unquote(pd$text[hit[1L]])
}

arch_enclosing_function <- function(start_id, nav, def_names) {
  pd <- nav$pd
  keys <- names(def_names)
  current <- start_id
  for (step in seq_len(1000L)) {
    r <- arch_row_of(nav, current)
    if (is.na(r)) {
      return(NA_character_)
    }
    parent_id <- pd$parent[r]
    if (is.na(parent_id) || parent_id <= 0L) {
      return(NA_character_)
    }
    key <- as.character(parent_id)
    if (key %in% keys) {
      nm <- def_names[[key]]
      if (!is.na(nm)) {
        return(nm)
      }
    }
    current <- parent_id
  }
  NA_character_
}

arch_first_argument_id <- function(call_id, function_expr_id, nav) {
  pd <- nav$pd
  kids <- arch_children(nav, call_id)
  kids <- kids[pd$id[kids] != function_expr_id]
  if (!length(kids)) {
    return(NA_integer_)
  }
  expr_kids <- kids[pd$token[kids] %in% c("expr", "expr_or_assign_or_help")]
  if (!length(expr_kids)) {
    return(NA_integer_)
  }
  pd$id[expr_kids[1L]]
}

# Tokens that disqualify an ancestor chain from carrying a bare value use:
# a lambda or a control flow statement creates its own nesting or position,
# `pkg::` and `pkg:::` qualification turns the use into a qualified call that
# the namespace path owns, `$`/`@` mean the name selects a subelement rather
# than naming a value, and an assignment token means the name is written,
# not read. Named arguments inside a call use the parser's EQ_SUB token instead
# of EQ_ASSIGN, so a value set in a named argument stays readable and reaches
# the call below it.
arch_value_dirty_tokens <- c(
  "FUNCTION", "IF", "WHILE", "FOR", "NS_GET", "NS_GET_INT",
  "'$'", "'@'", "LEFT_ASSIGN", "EQ_ASSIGN", "RIGHT_ASSIGN"
)

arch_nearest_function_scope <- function(expr_id, nav, scope_keys) {
  pd <- nav$pd
  current <- expr_id
  for (step in seq_len(1000L)) {
    r <- arch_row_of(nav, current)
    if (is.na(r)) {
      return(0L)
    }
    if (as.character(current) %in% scope_keys) {
      return(as.integer(current))
    }
    next_id <- pd$parent[r]
    if (is.na(next_id) || next_id <= 0L) {
      return(0L)
    }
    current <- next_id
  }
  0L
}

# The name a plain assignment writes to, or NA when the target is not a
# simple variable binding (component writes like `x$y <- 1` do not bind a
# name). Only `<-`, `=` and `->` count; `<<-`, `->>` and `:=` write into
# another environment or a data.table column and are not local shadows.
arch_assigned_name <- function(assign_row, nav) {
  pd <- nav$pd
  kids <- arch_children(nav, pd$parent[assign_row])
  at <- match(assign_row, kids)
  if (is.na(at)) {
    return(NA_character_)
  }
  toks <- pd$token[kids]
  name_at <- if (identical(toks[at], "RIGHT_ASSIGN")) at + 1L else at - 1L
  if (name_at < 1L || name_at > length(kids)) {
    return(NA_character_)
  }
  target_id <- pd$id[kids[name_at]]
  r_target <- arch_row_of(nav, target_id)
  if (is.na(r_target)) {
    return(NA_character_)
  }
  target_kids <- arch_children(nav, target_id)
  if (length(target_kids) == 1L && pd$token[target_kids[1L]] == "SYMBOL") {
    arch_unquote(pd$text[target_kids[1L]])
  } else {
    NA_character_
  }
}

# The bindings that shadow a name inside a scope: function formal parameters
# (bound in the function's own scope), for-loop variables and plain
# assignments (bound in the nearest enclosing function scope, or 0 at file
# top level). `<<-`, `->>` and `:=` are excluded because they write into an
# environment outside the scope where they appear. Top-level assignments are
# excluded too: a name bound at file top level is exactly what the project
# definition index records, and reading its value as a shadow would suppress
# the file's own edges. Top-level for-loop variables are kept (scope 0),
# because after the loop runs they hold whatever it iterated over, not a
# function.
arch_local_binding_table <- function(pd, nav, scope_keys) {
  empty <- data.table::data.table(name = character(), scope = integer())

  formal_at <- which(pd$token == "SYMBOL_FORMALS")
  formal <- data.table::data.table(
    name = pd$text[formal_at],
    scope = vapply(
      formal_at,
      function(r) arch_nearest_function_scope(pd$parent[r], nav, scope_keys),
      integer(1)
    )
  )

  assign_at <- which(
    (pd$token == "LEFT_ASSIGN" & pd$text == "<-") |
      (pd$token == "EQ_ASSIGN" & pd$text == "=") |
      (pd$token == "RIGHT_ASSIGN" & pd$text == "->")
  )
  assign <- data.table::rbindlist(lapply(assign_at, function(r) {
    scope <- arch_nearest_function_scope(pd$parent[r], nav, scope_keys)
    if (scope == 0L) {
      return(NULL)
    }
    binding_name <- arch_assigned_name(r, nav)
    if (is.na(binding_name)) {
      return(NULL)
    }
    data.table::data.table(name = binding_name, scope = scope)
  }))

  for_at <- which(pd$token == "forcond")
  loop <- data.table::rbindlist(lapply(for_at, function(r) {
    loop_kids <- arch_children(nav, pd$id[r])
    loop_kids <- loop_kids[pd$token[loop_kids] == "SYMBOL"]
    if (!length(loop_kids)) {
      return(NULL)
    }
    scope <- arch_nearest_function_scope(pd$id[r], nav, scope_keys)
    data.table::data.table(name = pd$text[loop_kids], scope = scope)
  }))

  data.table::rbindlist(list(empty, formal, assign, loop))
}

# The scope ids of the functions a row of parse data sits inside, walking the
# ancestor chain up to the file root.
arch_function_scope_ancestors <- function(row, nav, scope_keys) {
  pd <- nav$pd
  scopes <- integer()
  current <- pd$parent[row]
  for (step in seq_len(1000L)) {
    r <- arch_row_of(nav, current)
    if (is.na(r)) {
      return(scopes)
    }
    if (as.character(current) %in% scope_keys) {
      scopes <- c(scopes, as.integer(current))
    }
    next_id <- pd$parent[r]
    if (is.na(next_id) || next_id <= 0L) {
      return(scopes)
    }
    current <- next_id
  }
  scopes
}

# A bare name read as a value is anchored where it reaches a call that takes
# it as an argument. Walking up from the symbol, every caller in between must
# be clean: only expression, argument-list and operator nodes may appear. The
# first ancestor that brackets an expr child with `'('` (after that expr) is
# the call; a grouped subexpression like a parenthesised argument is not one.
arch_value_use_call <- function(row, nav) {
  pd <- nav$pd
  current <- pd$parent[row]
  for (step in seq_len(1000L)) {
    r <- arch_row_of(nav, current)
    if (is.na(r)) {
      return(NA_integer_)
    }
    kids <- arch_children(nav, pd$id[r])
    toks <- pd$token[kids]
    if (any(toks %in% arch_value_dirty_tokens)) {
      return(NA_integer_)
    }
    opens <- which(toks == "'('")
    if (length(opens)) {
      exprs_before <- which(toks == "expr")
      if (length(exprs_before) && min(exprs_before) < opens[1L]) {
        return(pd$id[r])
      }
    }
    next_id <- pd$parent[r]
    if (is.na(next_id) || next_id <= 0L) {
      return(NA_integer_)
    }
    current <- next_id
  }
  NA_integer_
}

# Value uses are bare names passed to a call as an argument -- named or
# positional -- such as `lapply(x,
# helper)`, `purrr::map(x, helper)`, `Reduce(helper, x)`, `formals(helper)`,
# `switch(type, pass =
# helper)`. Each use names a candidate dependency whose ownership is decided
# project-wide in arch_resolve(), once the definition index is known; the
# parser can only rule out what is *not* such a use.
arch_value_uses <- function(pd, nav, def_names, lines, rel_path) {
  rows <- which(pd$token == "SYMBOL")
  if (!length(rows)) {
    return(arch_empty_calls())
  }

  is_fun <- pd$token == "FUNCTION" | (pd$terminal & pd$text == "\\")
  scope_ids <- unique(pd$parent[is_fun])
  scope_ids <- as.integer(scope_ids[!is.na(scope_ids) & scope_ids > 0L])
  scope_keys <- as.character(scope_ids)

  bindings <- arch_local_binding_table(pd, nav, scope_keys)

  use_rows <- rows[which(vapply(rows, function(row) {
    symbol <- pd$text[row]
    # No binding anywhere in the file with this name: nothing can shadow it.
    if (!any(bindings$name == symbol)) {
      return(TRUE)
    }
    # A local binding of the name in any enclosing scope, or at file top
    # level, means the runtime reads that binding here, not a function of
    # the project.
    scopes <- c(arch_function_scope_ancestors(row, nav, scope_keys), 0L)
    !any(bindings$name == symbol & bindings$scope %in% scopes)
  }, logical(1)))]

  if (!length(use_rows)) {
    return(arch_empty_calls())
  }

  n <- length(use_rows)
  out_anchor <- integer(n)
  out_symbol <- character(n)
  for (i in seq_len(n)) {
    row <- use_rows[i]
    out_symbol[i] <- pd$text[row]
    call_id <- arch_value_use_call(row, nav)
    out_anchor[i] <- if (is.na(call_id)) 0L else call_id
  }

  anchored <- out_anchor > 0L
  if (!any(anchored)) {
    return(arch_empty_calls())
  }
  use_rows <- use_rows[anchored]
  out_symbol <- out_symbol[anchored]
  out_anchor <- out_anchor[anchored]
  n <- length(use_rows)

  anchor_rows <- vapply(out_anchor, arch_row_of, integer(1), nav = nav)

  calls <- data.table::data.table(
    file = rep(rel_path, n),
    line = as.integer(pd$line1[anchor_rows]),
    column = as.integer(pd$col1[anchor_rows]),
    enclosing_function = vapply(
      out_anchor,
      function(call_id) arch_enclosing_function(call_id, nav, def_names),
      character(1)
    ),
    callee = out_symbol,
    symbol = out_symbol,
    package = rep(NA_character_, n),
    internal = rep(FALSE, n),
    dynamic = rep(FALSE, n),
    source_text = vapply(
      seq_len(n),
      function(i) {
        arch_slice_source(
          lines,
          pd$line1[anchor_rows[i]],
          pd$col1[anchor_rows[i]],
          pd$line2[anchor_rows[i]],
          pd$col2[anchor_rows[i]]
        )
      },
      character(1)
    )
  )
  calls[order(calls$line, calls$column), ]
}

arch_call_sites <- function(pd, nav, def_names, lines, rel_path) {
  rows <- which(pd$token == "SYMBOL_FUNCTION_CALL")
  if (!length(rows)) {
    return(arch_empty_calls())
  }

  n <- length(rows)
  out_line <- integer(n)
  out_column <- integer(n)
  out_enclosing <- character(n)
  out_callee <- character(n)
  out_symbol <- character(n)
  out_package <- character(n)
  out_internal <- logical(n)
  out_dynamic <- logical(n)
  out_source <- character(n)

  for (i in seq_len(n)) {
    row <- rows[i]
    symbol <- arch_unquote(pd$text[row])
    function_expr_id <- pd$parent[row]

    kids <- arch_children(nav, function_expr_id)
    toks <- pd$token[kids]
    texts <- pd$text[kids]

    qualified <- any(toks %in% c("NS_GET", "NS_GET_INT"))
    internal <- any(toks == "NS_GET_INT")
    dynamic <- any(pd$terminal[kids] & texts %in% c("$", "@"))

    package <- NA_character_
    if (qualified) {
      sp <- kids[toks == "SYMBOL_PACKAGE"]
      if (length(sp)) {
        package <- arch_unquote(pd$text[sp[1L]])
      }
    }

    fr <- arch_row_of(nav, function_expr_id)
    call_id <- if (!is.na(fr) && !is.na(pd$parent[fr]) && pd$parent[fr] > 0L) {
      pd$parent[fr]
    } else {
      function_expr_id
    }
    cr <- arch_row_of(nav, call_id)
    if (is.na(cr)) {
      cr <- row
      call_id <- pd$id[row]
    }

    out_line[i] <- pd$line1[cr]
    out_column[i] <- pd$col1[cr]
    out_enclosing[i] <- arch_enclosing_function(call_id, nav, def_names)
    out_symbol[i] <- symbol
    out_package[i] <- package
    out_internal[i] <- internal
    out_dynamic[i] <- dynamic
    out_callee[i] <- if (qualified && !is.na(package)) {
      paste0(package, if (internal) ":::" else "::", symbol)
    } else {
      symbol
    }
    out_source[i] <- arch_slice_source(
      lines, pd$line1[cr], pd$col1[cr], pd$line2[cr], pd$col2[cr]
    )
  }

  data.table::data.table(
    file = rep(rel_path, n),
    line = as.integer(out_line),
    column = as.integer(out_column),
    enclosing_function = out_enclosing,
    callee = out_callee,
    symbol = out_symbol,
    package = out_package,
    internal = out_internal,
    dynamic = out_dynamic,
    source_text = out_source
  )
}

arch_library_calls <- function(pd, nav) {
  rows <- which(
    pd$token == "SYMBOL_FUNCTION_CALL" & pd$text %in% c("library", "require")
  )
  if (!length(rows)) {
    return(character())
  }

  found <- vapply(rows, function(row) {
    function_expr_id <- pd$parent[row]
    fr <- arch_row_of(nav, function_expr_id)
    if (is.na(fr) || is.na(pd$parent[fr]) || pd$parent[fr] <= 0L) {
      return(NA_character_)
    }
    arg_id <- arch_first_argument_id(pd$parent[fr], function_expr_id, nav)
    if (is.na(arg_id)) {
      return(NA_character_)
    }
    arch_symbol_text(arg_id, nav)
  }, character(1))

  found <- found[!is.na(found) & nzchar(found)]
  sort(unique(found), method = "radix")
}

arch_slice_source <- function(lines, line1, col1, line2, col2) {
  if (!length(lines) || is.na(line1) || line1 < 1L || line1 > length(lines)) {
    return(NA_character_)
  }
  line2 <- min(line2, length(lines))
  if (line1 == line2) {
    text <- substr(lines[line1], col1, col2)
  } else {
    first <- substring(lines[line1], col1)
    middle <- if (line2 - line1 > 1L) {
      lines[(line1 + 1L):(line2 - 1L)]
    } else {
      character()
    }
    last <- substr(lines[line2], 1L, col2)
    text <- paste(trimws(c(first, middle, last)), collapse = " ")
  }
  text <- gsub("[[:space:]]+", " ", trimws(text))
  if (nchar(text) > arch_source_text_limit) {
    text <- paste0(substr(text, 1L, arch_source_text_limit), "...")
  }
  text
}
