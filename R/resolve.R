arch_base_packages <- c(
  "base", "methods", "utils", "stats", "graphics", "grDevices", "datasets"
)

arch_symbol_index <- function(packages) {
  packages <- sort(unique(packages), method = "radix")
  exports <- list()
  unavailable <- character()

  for (pkg in packages) {
    found <- tryCatch(getNamespaceExports(pkg), error = function(e) NULL)
    if (is.null(found)) {
      unavailable <- c(unavailable, pkg)
      next
    }
    exports[[pkg]] <- found
  }

  index <- if (length(exports)) {
    symbols <- unlist(exports, use.names = FALSE)
    owners <- rep(names(exports), lengths(exports))
    split(owners, symbols)
  } else {
    list()
  }

  list(index = index, unavailable = unavailable)
}

arch_local_index <- function(defs) {
  if (!nrow(defs)) {
    return(list())
  }
  split(defs$file, defs$name)
}

# A project may define the same top-level name in more than one file. R
# collates the files alphabetically when the project loads and later
# definitions override earlier ones in the enclosing environment, so the
# definition that runs is the one from the last collated file. A call from
# the file that defines the name still attributes to the calling file
# first: a module calling its own helper is attributable to itself even
# when another module redefines the name.
arch_local_owner <- function(local_files, file) {
  if (file %in% local_files) file else local_files[length(local_files)]
}

arch_lookup <- function(index, symbol) {
  found <- index[[symbol]]
  if (is.null(found)) character() else sort(unique(found), method = "radix")
}

# A definition nested inside another function shadows the project, declared
# and base indexes for calls issued by that function, so such calls stay
# attributed to the file that defines the nested helper instead of falling
# through to base (issue #20). Scoped awareness keys on the innermost
# enclosing function name by design: the parse tree cannot tell which
# intermediate scopes a call may evaluate in, so a call to a definition
# nested two levels deep resolves through the normal order instead.
arch_nested_index <- function(nested_defs) {
  if (!nrow(nested_defs)) {
    return(character())
  }
  files <- nested_defs$file
  names(files) <- paste(
    nested_defs$file, nested_defs$scope, nested_defs$symbol, sep = "\r"
  )
  files
}

arch_nested_owner <- function(index, file, scope, symbol) {
  nested_file <- index[paste(file, scope, symbol, sep = "\r")]
  if (is.na(nested_file)) NA_character_ else nested_file
}

arch_empty_value_sites <- function() {
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
    source_text = character(),
    owner = character(),
    resolved_by = character(),
    candidates = list()
  )
}

# A bare name passed as a value to a call is a dependency only when the
# project defines the name at top level; otherwise it is an ordinary variable
# read (a base function or an undeclared identifier) and produces no edge.
# Values resolve against the top-level definition index under the same owner
# rule as calls and are tagged distinctly so they stay visible in the output.
arch_value_sites <- function(value_uses, local_index) {
  if (!nrow(value_uses)) {
    return(arch_empty_value_sites())
  }
  keep <- vapply(
    value_uses$symbol,
    function(nm) length(arch_lookup(local_index, nm)) > 0L,
    logical(1)
  )
  if (!any(keep)) {
    return(arch_empty_value_sites())
  }
  kept <- value_uses[which(keep)]
  n <- nrow(kept)
  owner <- vapply(
    seq_len(n),
    function(i) {
      look <- arch_lookup(local_index, kept$symbol[i])
      arch_local_owner(look, kept$file[i])
    },
    character(1)
  )
  sites <- kept
  sites$owner <- owner
  sites$resolved_by <- rep("value", n)
  # An all-NULL list column looks like a NULL assignment to data.table's
  # $<- and would vanish instead of being created; empty vectors survive.
  sites$candidates <- lapply(seq_len(n), function(i) character())
  sites
}

arch_resolve <- function(
  calls, local_index, declared_index, base_index, nested_index
) {
  n <- nrow(calls)
  owner <- rep(NA_character_, n)
  resolved_by <- rep("unresolved", n)
  candidates <- vector("list", n)
  has_nested <- length(nested_index) > 0L

  for (i in seq_len(n)) {
    candidates[[i]] <- character()
    symbol <- calls$symbol[i]

    if (!is.na(calls$package[i])) {
      owner[i] <- calls$package[i]
      resolved_by[i] <- if (calls$internal[i]) {
        "namespace_internal"
      } else {
        "namespace"
      }
      next
    }

    if (calls$dynamic[i]) {
      next
    }

    if (has_nested && !is.na(calls$enclosing_function[i])) {
      nested_file <- arch_nested_owner(
        nested_index, calls$file[i], calls$enclosing_function[i], symbol
      )
      if (!is.na(nested_file)) {
        owner[i] <- nested_file
        resolved_by[i] <- "local"
        next
      }
    }

    local_files <- arch_lookup(local_index, symbol)
    if (length(local_files)) {
      owner[i] <- arch_local_owner(local_files, calls$file[i])
      resolved_by[i] <- "local"
      next
    }

    from_declared <- arch_lookup(declared_index, symbol)
    from_base <- arch_lookup(base_index, symbol)

    if (length(from_declared)) {
      pool <- sort(unique(c(from_declared, from_base)), method = "radix")
      if (length(pool) == 1L) {
        owner[i] <- pool
        resolved_by[i] <- "export"
      } else {
        resolved_by[i] <- "ambiguous"
        candidates[[i]] <- pool
      }
      next
    }

    if (length(from_base)) {
      if (length(from_base) == 1L) {
        owner[i] <- from_base
        resolved_by[i] <- "base"
      } else {
        resolved_by[i] <- "ambiguous"
        candidates[[i]] <- from_base
      }
    }
  }

  sites <- data.table::copy(calls)
  sites$owner <- owner
  sites$resolved_by <- resolved_by
  sites$candidates <- candidates
  sites
}
