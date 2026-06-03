source("R/constants.R")
source("R/validate.R")
source("R/standardize.R")
source("R/i07.R")
source("R/feather_river.R")

build_warnings <- character(0)
record_warning <- function(w) {
  build_warnings <<- c(build_warnings, conditionMessage(w))
}

format_manifest_notes <- function(warnings) {
  if (length(warnings) == 0) {
    return("No build warnings were reported.")
  }

  clean_issue <- function(issue) {
    issue <- gsub("\\s+- run st_make_valid\\(\\) to repair$", "", issue)
    issue <- gsub("\\bis missing \\(NA\\) in row\\(s\\):", "is missing in rows:", issue)
    issue <- gsub("\\brow\\(s\\):", "rows:", issue)
    issue <- gsub("\\bin row\\b", "in row", issue)
    issue
  }

  notes <- character(0)
  for (msg in unique(warnings)) {
    lines <- trimws(strsplit(msg, "\n", fixed = TRUE)[[1]])
    lines <- lines[nzchar(lines)]
    if (length(lines) == 0) next

    validation_source <- sub(
      "^[0-9]+ validation warning\\(s\\) in:\\s*",
      "",
      lines[1]
    )
    if (!identical(validation_source, lines[1])) {
      issues <- sub("^[-*]\\s*", "", lines[-1])
      issues <- clean_issue(issues)
      notes <- c(notes, paste0("Validation issues in ", validation_source, ":"))
      notes <- c(notes, paste0("- ", issues))
    } else {
      notes <- c(notes, lines)
    }
  }

  paste(c("Build warnings:", notes), collapse = "\n")
}

submission_date <- "2026-06-03"
submission_version <- "v01"
submission_stem <- paste(submission_date, submission_version, sep = "_")
submission_gpkg <- file.path("data-final", paste0(submission_stem, ".gpkg"))
submission_manifest <- file.path("data-final", "submission_manifest.json")
source_provenance <- file.path("data-final", "dwr_hrl_restoration_projects_sources.yaml")

withCallingHandlers({
  # Clean, validate, and standardize each source
  i07 <- clean_i07() |> standardize() |> validate()
  feather_river <- clean_feather_river() |> standardize() |> validate()

  # Combine
  combined <- dplyr::bind_rows(i07, feather_river)

  metadata_paths <- c(
    "data-raw/i07_Habitat_Restoration_Polygons/metadata.yaml",
    "data-raw/Feather River/metadata.yaml"
  )

  # Warn on duplicate (project_name, lead_entity) pairs
  key  <- paste(combined$project_name, combined$lead_entity, sep = " | ")
  dups <- unique(key[duplicated(key)])
  if (length(dups) > 0) {
    warning("Duplicate project name and lead entity pairs:\n  ", paste(dups, collapse = "\n  "))
  }

  # Generate provenance log
  message("\nSources:")
  provenance <- list()
  for (path in metadata_paths) {
    entries <- yaml::read_yaml(path)
    if (!is.null(entries$source_name)) entries <- list(entries)
    for (m in entries) {
      m$raw_directory <- dirname(path)
      m$metadata_path <- path
      provenance[[length(provenance) + 1]] <- m
      message("  ", m$source_name, " | received ", m$received_date, " by ", m$received_by)
    }
  }

  # Write output
  dir.create("data-final", showWarnings = FALSE)

  sf::st_write(
    combined,
    submission_gpkg,
    layer = "restoration_projects",
    delete_layer = TRUE,
    quiet = TRUE
  )

  yaml::write_yaml(provenance, source_provenance)

  manifest <- list(
    submission_id = paste0("dwr_restoration-projects_", submission_stem),
    date_received = submission_date,
    uploaded_by = "Lucy Andrews",
    submitted_by = list(
      name = "Lucy Andrews",
      organization = "California Department of Water Resources",
      email = ""
    ),
    agency = "DWR",
    dataset_name = "restoration-projects",
    submission_type = "new",
    supersedes_submission_id = NULL,
    expected_schema = list(
      schema_name = "hrl-restoration-schema",
      schema_version = "v1.0.0"
    ),
    files = list(
      list(
        file_name = basename(submission_gpkg),
        file_type = "GeoPackage",
        relative_path = basename(submission_gpkg),
        description = "Final standardized spatial file submitted by DWR.",
        is_primary = TRUE
      )
    ),
    spatial_info = list(
      geometry_type_expected = "Polygon or MultiPolygon",
      crs_expected = "EPSG:3310",
      spatial_extent_description = "California HRL restoration project areas"
    ),
    data_content = list(
      feature_type = "restoration_project"
    ),
    access_and_sensitivity = list(
      contains_sensitive_data = FALSE,
      sensitivity_notes = "",
      sharing_constraints = "",
      license_or_use_constraints = ""
    ),
    processing_status = list(
      status = "ready_for_submission",
      validation_status = "completed",
      standardization_status = "completed"
    ),
    storage_location = list(
      storage_account = "hrldatalakedev",
      container = "raw-submissions",
      path = paste0("dwr/", submission_stem, "/")
    ),
    notes = format_manifest_notes(build_warnings)
  )

  jsonlite::write_json(manifest, submission_manifest, auto_unbox = TRUE, pretty = TRUE, null = "null")

  message("\nWrote ", nrow(combined), " features -> ", submission_gpkg)
  message("Wrote source provenance -> ", source_provenance)
  message("Wrote submission manifest -> ", submission_manifest)
}, warning = record_warning)
