# Pure harness contract helpers; tests run without an Opal service or R packages.
g_status_call <- function() call("omopDpStatusDS", "dsomop-protected-release-v1")
g_pooled_effect <- function(r) {
  if (!isTRUE(r$ok) || !is.data.frame(r$value$pooled)) return(NA_real_)
  cols <- intersect(c("estimate_fixed", "estimate_random"), names(r$value$pooled))
  if (!length(cols)) return(NA_real_)
  as.numeric(unlist(r$value$pooled[cols], use.names = FALSE))
}
g_new_log_lines <- function(before, after) {
  if (length(after) >= length(before) && identical(head(after, length(before)), before))
    return(tail(after, length(after) - length(before)))
  after # Rock rotated/truncated its log rather than appending to it.
}
g_private_hex <- function(lines) {
  # The attack probe itself supplies this literal. Exclude only that field,
  # not other hex values or private data elsewhere on the very same audit line.
  injected <- paste0('"data_generation":"', strrep("0", 64), '"')
  grepl("[0-9a-f]{40,}", gsub(injected, '"data_generation":"<analyst-injected>"', lines, fixed = TRUE))
}
