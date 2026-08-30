arch_excluded_dirs <- c(
  ".git", ".Rproj.user", ".svn", "renv", "packrat", "revdep", ".quarto"
)

arch_discover <- function(root) {
  if (!is.character(root) || length(root) != 1L || is.na(root)) {
    stop("`root` must be a single path.", call. = FALSE)
  }
  if (!dir.exists(root)) {
    stop("Project root does not exist: ", root, call. = FALSE)
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)

  description <- file.path(root, "DESCRIPTION")
  is_package <- file.exists(description) && arch_is_package_description(description)

  search_root <- if (is_package) file.path(root, "R") else root
  files <- if (dir.exists(search_root)) {
    list.files(
      search_root,
      pattern = "\\.[Rr]$",
      recursive = TRUE,
      full.names = TRUE,
      all.files = FALSE
    )
  } else {
    character()
  }

  files <- normalizePath(files, winslash = "/", mustWork = FALSE)
  rel <- arch_relative_to(files, root)
  rel <- rel[!arch_in_excluded_dir(rel)]
  rel <- sort(unique(rel), method = "radix")

  list(
    root = root,
    is_package = is_package,
    description = if (is_package) description else NA_character_,
    files = rel
  )
}

arch_is_package_description <- function(path) {
  fields <- tryCatch(
    read.dcf(path, fields = "Package"),
    error = function(e) NULL
  )
  !is.null(fields) && nrow(fields) > 0L && !is.na(fields[1L, "Package"])
}

arch_relative_to <- function(paths, root) {
  prefix <- paste0(sub("/$", "", root), "/")
  ifelse(startsWith(paths, prefix), substring(paths, nchar(prefix) + 1L), paths)
}

arch_in_excluded_dir <- function(rel) {
  parts <- strsplit(rel, "/", fixed = TRUE)
  vapply(
    parts,
    function(p) any(p %in% arch_excluded_dirs) || any(startsWith(p, ".")),
    logical(1)
  )
}

arch_declared_from_description <- function(path) {
  dcf <- tryCatch(read.dcf(path), error = function(e) NULL)
  if (is.null(dcf) || nrow(dcf) == 0L) {
    return(character())
  }
  fields <- intersect(c("Depends", "Imports"), colnames(dcf))
  if (length(fields) == 0L) {
    return(character())
  }
  raw <- unlist(strsplit(paste(dcf[1L, fields], collapse = ","), ",", fixed = TRUE))
  pkgs <- trimws(sub("\\(.*", "", raw))
  pkgs <- pkgs[nzchar(pkgs) & pkgs != "R" & !is.na(pkgs)]
  sort(unique(pkgs), method = "radix")
}
