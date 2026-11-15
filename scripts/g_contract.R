# Pure harness contract helpers; tests run without an Opal service or R packages.
g_status_call <- function(server_version = "2.10.3") {
  if (utils::compareVersion(server_version, "2.10.3") < 0) return(call("omopDpStatusDS"))
  call("omopDpStatusDS", "dsomop-protected-release-v1")
}

# A failed bootstrap must never become an upgrade baseline with an NA key.
# Keep only public identity and file metadata; never read the root's contents.
g_root_baseline <- function(version, status, files) {
  key <- if (isTRUE(status$ok) && is.list(status$value) && length(status$value) == 1L &&
             is.list(status$value[[1L]])) status$value[[1L]]$noise_key_id else NULL
  if (!is.character(key) || length(key) != 1L || is.na(key) ||
      !nzchar(trimws(key)) || identical(key, "NA"))
    stop("A1b harness baseline failed: DP status did not return a noise key id.")
  root <- grep("^secrets/dp_noise_root \\|", files, value = TRUE)
  if (inherits(files, "rock_error") || length(root) != 1L)
    stop("A1b harness baseline failed: expected exactly one persistent DP noise root file.")
  c(paste0("version=", version), paste0("noise_key_id=", key), paste0("file=", files))
}
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

# Only signed noisy components count as redraw evidence. Public bin numbers,
# concept IDs, bounds and allocations are invariant metadata, not draws.
g_component_values <- function(frame) {
  rel <- attr(frame, "dsomop_release", exact = TRUE)
  if (!is.list(rel) || !length(rel$owners)) return(NULL)
  out <- list()
  for (owner in rel$owners) {
    if (!is.character(owner$owner) || length(owner$owner) != 1L) return(NULL)
    for (component in c(if (!is.null(owner$root)) list(c(list(stratum = "<root>"), owner$root)),
                        owner$components)) {
      if (!is.character(component$stratum) || length(component$stratum) != 1L) return(NULL)
      prefix <- paste(owner$owner, component$stratum, sep = "\r")
      for (field in intersect(c("n", "s", "q", "h"), names(component))) {
        value <- component[[field]]
        if (is.null(value)) next
        if (!is.numeric(value) || any(!is.finite(value))) return(NULL)
        for (i in seq_along(value)) out[[paste(prefix, field, i, sep = "\r")]] <- value[[i]]
      }
    }
  }
  if (!length(out)) return(NULL)
  unlist(out[order(names(out))], use.names = TRUE)
}
g_component_changes <- function(a, b) {
  a <- g_component_values(a)
  b <- g_component_values(b)
  if (is.null(a) || is.null(b) || !identical(names(a), names(b)))
    return(c(cells = NA_real_, changed = NA_real_))
  c(cells = length(a), changed = sum(a != b))
}
g_measurement_params <- function() list(concept_id = "3004410")

# An unavailable result needs an actual explanation, not merely a column name
# or an unrelated mention of "unavailable" somewhere in its metadata.
g_has_unavailable_reason <- function(frame) {
  if (!is.data.frame(frame) || !nrow(frame)) return(FALSE)
  fields <- c("unavailable_reason", "withheld_reason", "masked_reason", "reason")
  label <- attr(frame, "dsomop_protection", exact = TRUE)
  nonempty <- function(x) is.character(x) && any(!is.na(x) & nzchar(trimws(x)))
  any(vapply(c(frame[intersect(fields, names(frame))],
               if (is.list(label)) label[intersect(fields, names(label))]),
             nonempty, logical(1L)))
}

# Several client discovery/read helpers return partial results with ds_errors
# instead of throwing. A method audit must not count these calls as PASS.
g_check_site_errors <- function(result) {
  errors <- if (isTRUE(result$ok)) attr(result$value, "ds_errors", exact = TRUE) else NULL
  if (length(errors)) {
    result$ok <- FALSE
    result$error <- paste(unlist(errors, use.names = TRUE), collapse = " | ")
  }
  result
}
