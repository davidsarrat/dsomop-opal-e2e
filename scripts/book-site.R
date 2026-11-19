# The site consumes committed, precomputed Markdown; no connection is opened.
stopifnot(length(list.files("vignettes", "^book-.*\\.Rmd$")) == 25L)
for (path in list.files("vignettes", "^book-.*\\.Rmd$", full.names=TRUE)) {
  stopifnot(!any(grepl("^```\\{r", readLines(path))))
}
# With article names, refresh only changed pages after a complete site build.
articles <- commandArgs(trailingOnly=TRUE)
# Remove retired entry paths from previous site builds.
unlink(file.path("docs/articles", outer(c("v01_getting_started", "v05_multi_server"),
  c(".html", ".md"), paste0)))
# Drop obsolete numbered book output only for a complete article build.
if (!length(articles)) unlink(list.files("docs/articles", "^book-.*[.](html|md)$", full.names=TRUE))
if (length(articles)) {
  for (article in articles) pkgdown::build_article(article, new_process=FALSE, lazy=FALSE)
  pkgdown::build_llm_docs()
} else pkgdown::build_site(new_process=FALSE, examples=FALSE, install=FALSE, lazy=FALSE)

# The reader site has a current release summary; preserve the package's full NEWS.
local({
  pkg <- pkgdown::as_pkgdown(".")
  news_dir <- tempfile("book-news-")
  dir.create(news_dir)
  on.exit(unlink(news_dir, recursive=TRUE))
  stopifnot(file.copy("pkgdown/NEWS.md", file.path(news_dir, "NEWS.md")))
  pkg$src_path <- normalizePath(news_dir)
  pkgdown::build_news(pkg, override=list(news=list(cran_dates=FALSE)))
})
pkgdown::build_llm_docs()

# Readers connect to an existing Opal server: no helper downloads are published.
unlink("docs/downloads", recursive=TRUE)

# Some pkgdown stages restore cached assets after init_site(). Ship the exact
# reviewed book assets, including new capability-card styles, at the end.
stopifnot(all(file.copy(c("pkgdown/extra.css", "pkgdown/extra.js"), "docs", overwrite=TRUE)))
file.create("docs/.nojekyll")

# Printed R output can include padding; it has no Markdown meaning.
for (path in list.files("docs", "[.]md$", recursive=TRUE, full.names=TRUE)) {
  lines <- readLines(path, warn=FALSE)
  printed <- grepl("^[ \t]*#>", lines)
  lines[printed] <- sub("[ \t]+$", "", lines[printed])
  writeLines(lines, path)
}
