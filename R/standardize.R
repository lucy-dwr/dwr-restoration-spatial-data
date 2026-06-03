#' Standardize a validated submission sf object to the RestorationProjectSubmission profile.
#'
#' Steps applied in order:
#'   1. Reproject to NAD83 / California Albers (EPSG:3310)
#'   2. Upgrade POLYGON -> MULTIPOLYGON and POINT -> MULTIPOINT
#'   3. Normalize early_implementation to logical
#'   4. Normalize email casing and zero-valued habitat acreage fields
#'   5. Truncate over-length text fields
#'   6. Drop unrecognized columns and enforce submission field order
#'
#' Program-assigned fields (project_id, update_date, funding_gap) are not added
#' here — they are assigned downstream by the program-wide ingestion pipeline.
#'
#' @param sf_obj Validated sf object from validate_submission().
#' @return Standardized sf object conforming to RestorationProjectSubmission.
standardize <- function(sf_obj) {
  source_label <- attr(sf_obj, "source")

  # Reproject
  if (!isTRUE(sf::st_crs(sf_obj)$epsg == 3310)) {
    sf_obj <- sf::st_transform(sf_obj, 3310)
  }

  # Upgrade to MULTI geometry types
  geom_types <- unique(as.character(sf::st_geometry_type(sf_obj)))
  if (any(geom_types %in% c("POLYGON", "MULTIPOLYGON"))) {
    sf_obj <- sf::st_cast(sf_obj, "MULTIPOLYGON", warn = FALSE)
  } else if (any(geom_types %in% c("POINT", "MULTIPOINT"))) {
    sf_obj <- sf::st_cast(sf_obj, "MULTIPOINT", warn = FALSE)
  }

  # Normalize early_implementation to logical
  ei <- sf_obj$early_implementation
  if (!is.logical(ei)) {
    sf_obj$early_implementation <- tolower(trimws(as.character(ei))) %in%
      c("true", "t", "yes", "1")
  }

  # Normalize contact email casing
  sf_obj$contact_email <- tolower(trimws(as.character(sf_obj$contact_email)))

  # Habitat-specific acreage fields should only carry positive accounting values.
  habitat_acreage_fields <- c(
    "acreage_bypass_floodplain",
    "acreage_fish_food",
    "acreage_tributary_floodplain",
    "acreage_tributary_rearing",
    "acreage_tributary_spawning",
    "acreage_tidal_wetland"
  )
  for (field in intersect(habitat_acreage_fields, names(sf_obj))) {
    sf_obj[[field]] <- zero_to_na(sf_obj[[field]])
  }

  # Normalize enum fields: case-insensitive matching + known aliases
  sf_obj$project_stage  <- normalize_stage(sf_obj$project_stage)
  sf_obj$project_type   <- normalize_enum_tokens(sf_obj$project_type,   PROJECT_TYPE_VALUES)
  sf_obj$system         <- normalize_enum_tokens(sf_obj$system,          SYSTEM_VALUES)
  sf_obj$target_species <- normalize_enum_tokens(sf_obj$target_species,  TARGET_SPECIES_VALUES)

  # Truncate text fields
  sf_obj$project_description <- truncate_str(sf_obj$project_description, 500)
  if ("construction_completion_year_comments" %in% names(sf_obj)) {
    sf_obj$construction_completion_year_comments <-
      truncate_str(sf_obj$construction_completion_year_comments, 250)
  }
  if ("estimated_budget_comments" %in% names(sf_obj)) {
    sf_obj$estimated_budget_comments <-
      truncate_str(sf_obj$estimated_budget_comments, 500)
  }

  # Set column order with submission profile fields only
  submission_order <- c(
    "project_name",
    "project_description",
    "project_stage",
    "contact_name",
    "contact_email",
    "lead_entity",
    "contractors",
    "early_implementation", 
    "construction_start_year",
    "construction_completion_year",
    "construction_completion_year_comments",
    "estimated_budget",
    "estimated_budget_comments",
    "funding_secured",
    "funding_sources",
    "system",
    "project_type",
    "acreage",
    "acreage_bypass_floodplain",
    "acreage_fish_food",
    "acreage_tributary_floodplain",
    "acreage_tributary_rearing",
    "acreage_tributary_spawning",
    "acreage_tidal_wetland",
    "target_species"
  )
  present <- intersect(submission_order, names(sf_obj))
  extra <- setdiff(names(sf_obj), c(submission_order, attr(sf_obj, "sf_column")))
  if (length(extra) > 0) {
    message("Note: extra column(s) will be dropped: ", paste(extra, collapse = ", "))
  }
  result <- sf_obj[, present]
  attr(result, "source") <- source_label
  result
}

truncate_str <- function(x, max_len) {
  ifelse(!is.na(x) & nchar(x) > max_len, substr(x, 1, max_len), x)
}

zero_to_na <- function(x) {
  v <- suppressWarnings(as.numeric(x))
  v[!is.na(v) & v == 0] <- NA_real_
  v
}

# Known aliases for project_stage values that differ from the schema by more
# than case (e.g. "Post-Construction" is shorthand for the full enum value)
STAGE_ALIASES <- c(
  "post-construction"                    = "post-construction monitoring and science",
  "post construction"                    = "post-construction monitoring and science",
  "post-construction monitoring"         = "post-construction monitoring and science",
  "concept/feasibility"                  = "concept/feasibility",
  "concept / feasibility"                = "concept/feasibility"
)

normalize_stage <- function(x) {
  lower <- tolower(trimws(x))
  # Apply aliases first, then fall back to case-insensitive schema match
  aliased <- ifelse(lower %in% names(STAGE_ALIASES), STAGE_ALIASES[lower], lower)
  schema_lower <- tolower(PROJECT_STAGE_VALUES)
  idx <- match(aliased, schema_lower)
  ifelse(!is.na(idx), PROJECT_STAGE_VALUES[idx], x)
}

# Normalize a semicolon-delimited enum field: trim tokens, match
# case-insensitively against allowed values, rejoin with ";"
normalize_enum_tokens <- function(x, allowed) {
  schema_lower <- tolower(allowed)
  vapply(x, function(val) {
    if (is.na(val)) return(NA_character_)
    tokens <- trimws(strsplit(val, ";")[[1]])
    tokens <- vapply(tokens, function(t) {
      idx <- match(tolower(t), schema_lower)
      if (!is.na(idx)) allowed[idx] else t
    }, character(1))
    paste(tokens, collapse = ";")
  }, character(1))
}
