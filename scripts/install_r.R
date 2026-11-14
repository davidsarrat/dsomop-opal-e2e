# The analyst's side: opalr (admin tasks), DSI + DSOpal, and dsOMOPClient at the requested ref.
options(Ncpus = 4)
install.packages(c("opalr", "DSI", "DSOpal", "remotes", "jsonlite", "yaml", "DBI", "RPostgres", "openssl", "dsBaseClient"), quiet = TRUE)
mode <- Sys.getenv("MODE", "public")
if (identical(mode, "candidate")) {
  remotes::install_local("pkgs/dsOMOPClient", upgrade = "never", dependencies = TRUE, quiet = TRUE)
} else {
  remotes::install_github("isglobal-brge/dsOMOPClient", ref = Sys.getenv("CLIENT_REF", "2.10.0"),
                          upgrade = "never", quiet = TRUE)
}
for (p in c("opalr", "DSI", "DSOpal", "dsOMOPClient")) cat(p, as.character(packageVersion(p)), "\n")
