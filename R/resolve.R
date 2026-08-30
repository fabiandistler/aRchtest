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

arch_lookup <- function(index, symbol) {
  found <- index[[symbol]]
  if (is.null(found)) character() else sort(unique(found), method = "radix")
}

arch_resolve <- function(calls, local_index, declared_index, base_index) {
  n <- nrow(calls)
  owner <- rep(NA_character_, n)
  resolved_by <- rep("unresolved", n)
  candidates <- vector("list", n)

  for (i in seq_len(n)) {
    candidates[[i]] <- character()
    symbol <- calls$symbol[i]

    if (!is.na(calls$package[i])) {
      owner[i] <- calls$package[i]
      resolved_by[i] <- if (calls$internal[i]) "namespace_internal" else "namespace"
      next
    }

    if (calls$dynamic[i]) {
      next
    }

    local_files <- arch_lookup(local_index, symbol)
    if (length(local_files)) {
      owner[i] <- if (calls$file[i] %in% local_files) {
        calls$file[i]
      } else {
        local_files[1L]
      }
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
