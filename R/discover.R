arch_excluded_dirs <- c(
  ".git", ".Rproj.user", ".svn", "renv", "packrat", "revdep", ".quarto"
)

arch_discover <- function(root) {
  if (is.null(root)) {
    root <- arch_find_root(getwd())
  }
  if (!is.character(root) || length(root) != 1L || is.na(root)) {
    stop("`root` must be a single path.", call. = FALSE)
  }
  if (!dir.exists(root)) {
    stop("Project root does not exist: ", root, call. = FALSE)
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)

  description <- file.path(root, "DESCRIPTION")
  is_package <- file.exists(description) &&
    arch_is_package_description(description)

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

# The project root a check runs against when the caller names none: the
# nearest directory at or above `start` holding a DESCRIPTION or an .Rproj
# file. testthat runs test files from tests/testthat, so the working directory
# itself is rarely the root. Under R CMD check the tests run in
# <pkg>.Rcheck/tests/testthat, beside a copy of the sources in
# <pkg>.Rcheck/00_pkg_src/<pkg>; that copy is the root there. With no marker
# anywhere above, the working directory is the root (a script project).
arch_find_root <- function(start) {
  dir <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (arch_is_project_root(dir)) {
      return(dir)
    }
    checked_source <- arch_checked_source(dir)
    if (!is.na(checked_source)) {
      return(checked_source)
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) {
      return(start)
    }
    dir <- parent
  }
}

arch_is_project_root <- function(dir) {
  description <- file.path(dir, "DESCRIPTION")
  (file.exists(description) && !dir.exists(description)) ||
    length(list.files(dir, pattern = "\\.Rproj$")) > 0L
}

arch_checked_source <- function(dir) {
  if (!endsWith(basename(dir), ".Rcheck")) {
    return(NA_character_)
  }
  package <- sub("\\.Rcheck$", "", basename(dir))
  source <- file.path(dir, "00_pkg_src", package)
  if (!file.exists(file.path(source, "DESCRIPTION"))) {
    return(NA_character_)
  }
  normalizePath(source, winslash = "/", mustWork = TRUE)
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
  joined <- paste(dcf[1L, fields], collapse = ",")
  raw <- unlist(strsplit(joined, ",", fixed = TRUE))
  pkgs <- trimws(sub("\\(.*", "", raw))
  pkgs <- pkgs[nzchar(pkgs) & pkgs != "R" & !is.na(pkgs)]
  sort(unique(pkgs), method = "radix")
}
