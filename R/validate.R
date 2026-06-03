validate <- function(sf_obj) {
  source_label <- attr(sf_obj, "source")
  if (is.null(source_label)) source_label <- "unknown source"

  errors <- character(0)

  # CRS
  if (is.na(sf::st_crs(sf_obj))) {
    errors <- c(errors, "CRS is undefined; the submitted file must include a defined coordinate reference system")
  }

  # Geometry types
  geom_types <- unique(as.character(sf::st_geometry_type(sf_obj)))
  bad_geom <- setdiff(geom_types, c("POLYGON", "MULTIPOLYGON", "POINT", "MULTIPOINT"))
  if (length(bad_geom) > 0) {
    errors <- c(errors, paste0("Invalid geometry type(s): ", paste(bad_geom, collapse = ", "),
                               " - allowed: POLYGON, MULTIPOLYGON, POINT, MULTIPOINT"))
  }

  # Required fields
  missing_fields <- setdiff(REQUIRED_SUBMISSION_FIELDS, names(sf_obj))
  for (f in missing_fields) {
    alias <- names(FIELD_NAME_MAP)[FIELD_NAME_MAP == f]
    alias_note <- if (length(alias) > 0) paste0(" (shapefile alias: ", alias, ")") else ""
    errors <- c(errors, paste0("Missing required field: ", f, alias_note))
  }

  if (length(errors) > 0) warning(format_issues(source_label, errors))

  n <- nrow(sf_obj)
  if (n == 0) {
    warning(format_issues(source_label, "Submission contains 0 features - check that atlas_name values match the source file"))
    return(sf_obj)
  }

  # Contact_email format
  bad_email <- !grepl("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", sf_obj$contact_email, perl = TRUE)
  if (any(bad_email)) {
    errors <- c(errors, paste0("Invalid contact_email in row(s): ", paste(which(bad_email), collapse = ", ")))
  }

  # Enum and range checks
  errors <- c(errors, check_enum(sf_obj, "project_stage",  PROJECT_STAGE_VALUES))
  errors <- c(errors, check_enum(sf_obj, "project_type",   PROJECT_TYPE_VALUES))
  errors <- c(errors, check_enum(sf_obj, "target_species", TARGET_SPECIES_VALUES))

  bad_system <- sf_obj$system[!sf_obj$system %in% SYSTEM_VALUES]
  if (length(bad_system) > 0) {
    errors <- c(errors, paste0("Invalid system value(s): ", paste(unique(bad_system), collapse = ", ")))
  }

  errors <- c(errors, check_year_range(sf_obj, "construction_start_year",      2018, 2035))
  errors <- c(errors, check_year_range(sf_obj, "construction_completion_year", 2018, 2040))

  for (f in c("estimated_budget", "funding_secured", "acreage",
              "acreage_bypass_floodplain", "acreage_fish_food",
              "acreage_tributary_floodplain", "acreage_tributary_rearing",
              "acreage_tributary_spawning", "acreage_tidal_wetland")) {
    errors <- c(errors, check_nonneg(sf_obj, f))
  }

  # Acreage required unless project is only fish screen / fish passage
  project_types_list <- strsplit(as.character(sf_obj$project_type), ";\\s*", perl = TRUE)
  if (!"acreage" %in% names(sf_obj)) {
    needs_acreage <- vapply(project_types_list, function(types) {
      !all(trimws(types) %in% ACREAGE_EXEMPT_TYPES)
    }, logical(1))
    if (any(needs_acreage)) {
      errors <- c(errors, paste0("acreage field is required for row(s) with non-exempt project_type: ",
                                 paste(which(needs_acreage), collapse = ", ")))
    }
  } else {
    for (i in seq_len(n)) {
      if (!all(trimws(project_types_list[[i]]) %in% ACREAGE_EXEMPT_TYPES) && is.na(sf_obj$acreage[i])) {
        errors <- c(errors, paste0("acreage is NA in row ", i, " (project_type: ", sf_obj$project_type[i], ")"))
      }
    }
  }

  # Geometry validity
  if (!is.na(sf::st_crs(sf_obj))) {
    valid_geom <- sf::st_is_valid(sf_obj)
    if (any(!valid_geom, na.rm = TRUE)) {
      errors <- c(errors, paste0("Invalid geometry in row(s): ",
                                 paste(which(!valid_geom), collapse = ", "),
                                 " - run st_make_valid() to repair"))
    }

    bbox <- sf::st_bbox(sf::st_transform(sf_obj, 4326))
    ca   <- c(xmin = -125.5, ymin = 31.5, xmax = -113.1, ymax = 43.0)
    if (!anyNA(bbox) &&
        (bbox["xmin"] < ca["xmin"] || bbox["xmax"] > ca["xmax"] ||
         bbox["ymin"] < ca["ymin"] || bbox["ymax"] > ca["ymax"])) {
      errors <- c(errors, "Spatial extent falls outside California bounds - check CRS and coordinates")
    }
  }

  # Duplicate geometry check
  wkt      <- sf::st_as_text(sf::st_geometry(sf_obj))
  dup_rows <- which(duplicated(wkt))
  if (length(dup_rows) > 0) {
    errors <- c(errors, paste0("Duplicate geometry in row(s): ", paste(dup_rows, collapse = ", ")))
  }

  if (length(errors) > 0) {
    warning(format_issues(source_label, errors))
  } else {
    message("Validation passed: ", source_label, " (", n, " feature(s))")
  }
  sf_obj
}

check_enum <- function(sf_obj, field, allowed) {
  errors <- character(0)
  raw    <- as.character(sf_obj[[field]])
  for (i in seq_along(raw)) {
    if (is.na(raw[i]) || nchar(trimws(raw[i])) == 0) {
      errors <- c(errors, paste0("Missing value for ", field, " in row ", i))
      next
    }
    bad <- setdiff(trimws(strsplit(raw[i], ";\\s*", perl = TRUE)[[1]]), allowed)
    if (length(bad) > 0) {
      errors <- c(errors, paste0("Invalid ", field, " value(s) in row ", i, ": ", paste(bad, collapse = ", ")))
    }
  }
  errors
}

check_year_range <- function(sf_obj, field, min_val, max_val) {
  errors  <- character(0)
  orig    <- sf_obj[[field]]
  v       <- suppressWarnings(as.integer(orig))
  na_orig <- is.na(orig)
  na_conv <- is.na(v) & !na_orig
  if (any(na_orig)) {
    errors <- c(errors, paste0(field, " is missing (NA) in row(s): ", paste(which(na_orig), collapse = ", ")))
  }
  if (any(na_conv)) {
    errors <- c(errors, paste0(field, " has non-integer value(s) in row(s): ", paste(which(na_conv), collapse = ", ")))
  }
  out_of_range <- !is.na(v) & (v < min_val | v > max_val)
  if (any(out_of_range)) {
    errors <- c(errors, paste0(field, " out of range [", min_val, ", ", max_val, "] in row(s): ",
                               paste(which(out_of_range), collapse = ", ")))
  }
  errors
}

check_nonneg <- function(sf_obj, field) {
  if (!field %in% names(sf_obj)) return(character(0))
  v   <- suppressWarnings(as.numeric(sf_obj[[field]]))
  neg <- !is.na(v) & v < 0
  if (any(neg)) {
    return(paste0(field, " has negative value(s) in row(s): ", paste(which(neg), collapse = ", ")))
  }
  character(0)
}

format_issues <- function(source_label, errors) {
  paste0(length(errors), " validation warning(s) in: ", source_label, "\n",
         paste0("  - ", errors, collapse = "\n"))
}
