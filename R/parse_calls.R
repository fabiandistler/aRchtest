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

arch_parse_file <- function(abs_path, rel_path) {
  blank <- list(
    ok = TRUE,
    reason = NA_character_,
    calls = arch_empty_calls(),
    defs = arch_empty_defs(),
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
      defs = arch_empty_defs(),
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

  list(
    ok = TRUE,
    reason = NA_character_,
    calls = calls,
    defs = data.table::data.table(
      file = rep(rel_path, length(defs$defined)),
      name = defs$defined
    ),
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

  named <- vapply(def_ids, function(d) arch_definition_name(d, nav), character(1))
  names(named) <- as.character(def_ids)

  list(
    names = named,
    defined = sort(unique(named[!is.na(named)]), method = "radix")
  )
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
  rows <- which(pd$token == "SYMBOL_FUNCTION_CALL" & pd$text %in% c("library", "require"))
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
    middle <- if (line2 - line1 > 1L) lines[(line1 + 1L):(line2 - 1L)] else character()
    last <- substr(lines[line2], 1L, col2)
    text <- paste(trimws(c(first, middle, last)), collapse = " ")
  }
  text <- gsub("[[:space:]]+", " ", trimws(text))
  if (nchar(text) > arch_source_text_limit) {
    text <- paste0(substr(text, 1L, arch_source_text_limit), "...")
  }
  text
}
