# Historical fixtures use codeload archives: Rock's GitHub package manager does
# not inherit the runner's GITHUB_PAT and can report success after an API 403.
# Keep credentials out of Rock and verify the actual service-library install.
historical_source <- function(ref, directory) {
  if (!is.character(ref) || length(ref) != 1L || is.na(ref) || !nzchar(ref))
    stop("Historical server ref must be one nonempty string.")
  archive <- file.path(directory, "dsOMOP-historical.tar.gz")
  url <- paste0("https://codeload.github.com/isglobal-brge/dsOMOP/tar.gz/", utils::URLencode(ref, reserved = TRUE))
  status <- utils::download.file(url, archive, mode = "wb", quiet = TRUE)
  if (!identical(status, 0L)) stop("Historical server archive download failed for ", ref)
  files <- utils::untar(archive, list = TRUE)
  desc <- grep("^[^./][^/]*/DESCRIPTION$", files, value = TRUE)
  if (length(desc) != 1L) stop("Historical server archive must contain exactly one package DESCRIPTION.")
  utils::untar(archive, files = desc, exdir = directory)
  d <- read.dcf(file.path(directory, desc))
  if (!identical(unname(d[1L, "Package"]), "dsOMOP")) stop("Historical archive is not dsOMOP.")
  version <- unname(d[1L, "Version"])
  tag <- sub("^refs/tags/", "", ref)
  tag <- sub("^v", "", tag)
  if (grepl("^[0-9]+[.][0-9]+[.][0-9]+$", tag) && !identical(version, tag))
    stop("Historical archive version does not match requested tag ", ref)
  list(archive = archive, version = version)
}

historical_install_code <- function(path) {
  # A subprocess supplies a clean namespace and a real exit status, with the
  # complete installation log retained in the path transcript on failure.
  expr <- 'options(repos = c(CRAN = "https://cloud.r-project.org")); args <- commandArgs(TRUE); remotes::install_local(args[1], lib = args[2], dependencies = NA, upgrade = "never", force = TRUE)'
  sprintf('local({ archive <- %s; log <- tempfile(); on.exit(unlink(c(archive, log))); status <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(%s), shQuote(archive), shQuote(.libPaths()[1])), stdout = log, stderr = log); list(status = status, library = .libPaths()[1], log = readLines(log, warn = FALSE)) })',
          encodeString(path, quote = '"'), encodeString(expr, quote = '"'))
}

install_historical_server <- function(o, ref) {
  directory <- tempfile("dsomop-historical-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  src <- historical_source(ref, directory)
  say("Historical dsOMOP source: ", ref, "; archive version ", src$version)
  r <- capture("dsadmin.install_local_package(o, historical archive)", dsadmin.install_local_package(o, src$archive))
  # As for candidate installs, even a 201 or an existing matching version does
  # not establish that the requested source was installed. Install this archive.
  remote <- paste0("/tmp/", basename(directory), ".tar.gz")
  copied <- system2("docker", c("cp", shQuote(src$archive), shQuote(paste0(Sys.getenv("ROCK"), ":", remote))))
  if (!identical(copied, 0L)) stop("Cannot copy the historical server archive to Rock")
  installed <- rock_eval(historical_install_code(remote))
  show("Rock historical installation (service R session and library)", installed)
  if (inherits(installed, "rock_error") || !is.list(installed) ||
      !identical(as.integer(installed$status), 0L))
    stop("Historical server installation failed; see the captured install log")
  actual <- rock_pkg_version("dsOMOP")
  if (!identical(actual, src$version))
    stop("Historical server installation failed: expected dsOMOP ", src$version,
         " for ", ref, "; Rock reports ", paste(actual, collapse = ", "))
  # The manager result remains in the transcript; the verified source install
  # determines setup success, including recovery from a manager no-op/error.
  list(ok = TRUE, version = actual, manager = r)
}
