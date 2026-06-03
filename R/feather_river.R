clean_feather_river <- function() {
  workbook <- "data-raw/Feather River/Feather River Gravel Enhancement Project Data.xlsx"

  # The workbook has one tab per project, with schema labels in column A and
  # submitted values in column B
  attrs_2024 <- feather_river_read_sheet(workbook, "2024")
  attrs_p68  <- feather_river_read_sheet(workbook, "P68")

  # The 2024 geometry is embedded in the extracted ArcGIS Pro project package;
  # the P68 geometry came as two as-built shapefiles
  geom_2024 <- feather_river_read_project_geometry(
    "data-raw/Feather River/2025 Gravel Project Projected Site Map/commondata/onedrive_2_5-18-2026/In_River_Activity_2025_Projected_spawning_gravel.shp"
  )
  geom_p68 <- feather_river_read_project_geometry(c(
    "data-raw/Feather River/2023_FRSHIP_As_Built/Bedrock_As-Built_Boundary/Bedrock_As-Built_Boundary.shp",
    "data-raw/Feather River/2023_FRSHIP_As_Built/Upper_Riffles/Upper_Riffles.shp"
  ))

  result <- dplyr::bind_rows(
    feather_river_add_project_attributes(geom_2024, attrs_2024),
    feather_river_add_project_attributes(geom_p68, attrs_p68)
  )

  attr(result, "source") <- workbook
  result
}

feather_river_read_sheet <- function(path, sheet) {
  raw <- readxl::read_excel(
    path,
    sheet = sheet,
    col_names = FALSE,
    na = c("", "NA"),
    .name_repair = "minimal"
  )

  labels <- trimws(as.character(raw[[1]]))
  values <- raw[[2]]

  # Pull values by the human-readable schema label, not by row number, so small
  # template edits do not shift fields silently
  value_for <- function(label) {
    value <- values[match(label, labels)]
    if (length(value) == 0) NA else value[[1]]
  }

  estimated_budget <- feather_river_as_number(value_for("Estimated total budget"))
  funding_secured <- feather_river_as_number(value_for("Funding secured"))
  funding_gap <- feather_river_as_number(value_for("Funding gap"))

  # The submission profile requires estimated_budget and funding_secured, but
  # funding_gap is assigned downstream. If the source says the gap is zero, use
  # the populated budget field to fill the missing counterpart
  if (is.na(estimated_budget) && !is.na(funding_secured) && identical(funding_gap, 0)) {
    estimated_budget <- funding_secured
  }
  if (is.na(funding_secured) && !is.na(estimated_budget) && identical(funding_gap, 0)) {
    funding_secured <- estimated_budget
  }

  data.frame(
    project_name = feather_river_clean_text(value_for("Project name")),
    project_description = feather_river_clean_text(value_for("Project description")),
    project_stage = feather_river_normalize_stage(value_for("Project stage")),
    contact_name = feather_river_normalize_contact_name(value_for("Contact name")),
    contact_email = feather_river_normalize_contact_email(value_for("Contact email address")),
    lead_entity = feather_river_clean_text(value_for("Lead entity")),
    contractors = feather_river_semicolon_list(value_for("Contractor(s)")),
    early_implementation = feather_river_clean_text(value_for("Early implementation")),
    construction_start_year = as.integer(feather_river_as_number(value_for("Anticipated construction start year"))),
    construction_completion_year = as.integer(feather_river_as_number(value_for("Anticipated construction completion year"))),
    construction_completion_year_comments = feather_river_none_to_na(value_for("Comments on anticipated completion year")),
    estimated_budget = estimated_budget,
    estimated_budget_comments = feather_river_none_to_na(value_for("Comments on estimated total budget")),
    funding_secured = funding_secured,
    funding_sources = feather_river_semicolon_list(value_for("Funding sources")),
    system = "Feather",
    project_type = feather_river_normalize_project_type(value_for("Project type(s)")),
    acreage = feather_river_as_number(value_for("Total project acreage")),
    acreage_bypass_floodplain = feather_river_as_number(value_for("Bypass floodplain acreage")),
    acreage_fish_food = feather_river_as_number(value_for("Fish food production acreage")),
    acreage_tributary_floodplain = feather_river_as_number(value_for("Tributary floodplain habitat acreage")),
    acreage_tributary_rearing = feather_river_as_number(value_for("Tributary rearing habitat acreage")),
    acreage_tributary_spawning = feather_river_as_number(value_for("Tributary spawning habitat acreage")),
    acreage_tidal_wetland = feather_river_as_number(value_for("Tidal wetland habitat acreage")),
    target_species = feather_river_normalize_species(value_for("Target species")),
    stringsAsFactors = FALSE
  )
}

feather_river_read_project_geometry <- function(paths) {
  geoms <- lapply(paths, function(path) {
    sf::st_read(path, quiet = TRUE) |>
      sf::st_zm(drop = TRUE, what = "ZM") |>
      dplyr::select(geometry)
  })

  # Each input path represents part of one restoration project, so dissolve all
  # parts into a single feature before attaching project attributes
  combined <- dplyr::bind_rows(geoms)
  geometry <- sf::st_union(sf::st_geometry(combined))
  sf::st_sf(geometry = geometry, crs = sf::st_crs(combined)) |>
    sf::st_transform(3310)
}

feather_river_add_project_attributes <- function(geom, attrs) {
  for (name in names(attrs)) {
    geom[[name]] <- attrs[[name]]
  }
  geom
}

feather_river_clean_text <- function(x) {
  x <- trimws(as.character(x))
  ifelse(is.na(x) | x == "", NA_character_, x)
}

feather_river_none_to_na <- function(x) {
  x <- feather_river_clean_text(x)
  ifelse(tolower(x) %in% c("none", "n/a", "na"), NA_character_, x)
}

feather_river_as_number <- function(x) {
  x <- feather_river_clean_text(x)
  suppressWarnings(as.numeric(gsub("[,$]", "", x)))
}

feather_river_semicolon_list <- function(x) {
  x <- feather_river_clean_text(x)
  # Source entries use commas and "and" where the schema expects semicolons
  x <- gsub("\\s+(and|&)\\s+", "; ", x, ignore.case = TRUE)
  x <- gsub("\\s*,\\s*", "; ", x)
  x <- gsub("\\s*;\\s*", "; ", x)
  x
}

feather_river_normalize_stage <- function(x) {
  x <- tolower(feather_river_clean_text(x))
  if (is.na(x)) return(NA_character_)
  if (x == "completed") return("post-construction monitoring and science")
  if (grepl("construction", x)) return("construction")
  x
}

feather_river_normalize_project_type <- function(x) {
  x <- tolower(feather_river_clean_text(x))
  if (is.na(x)) return(NA_character_)
  if (grepl("gravel|spawning", x)) return("spawning habitat")
  x
}

feather_river_normalize_species <- function(x) {
  x <- tolower(feather_river_clean_text(x))
  if (is.na(x)) return(NA_character_)

  species <- character(0)
  if (grepl("chinook", x)) species <- c(species, "Chinook salmon")
  if (grepl("steelhead", x)) species <- c(species, "Steelhead trout")
  paste(species, collapse = ";")
}

feather_river_normalize_contact_name <- function(x) {
  x <- feather_river_clean_text(x)
  if (is.na(x)) return(NA_character_)
  # The schema has one primary contact field; keep the first listed contact
  trimws(strsplit(x, ",")[[1]][1])
}

feather_river_normalize_contact_email <- function(x) {
  x <- feather_river_clean_text(x)
  if (is.na(x)) return(NA_character_)
  # Keep the email aligned with the first listed contact
  trimws(strsplit(x, ",")[[1]][1])
}
