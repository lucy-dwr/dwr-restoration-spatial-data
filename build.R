source("R/constants.R")
source("R/validate.R")
source("R/standardize.R")
source("R/i07.R")
# source("R/<source2>.R")

# Clean, validate, and standardize each source 
i07 <- clean_i07() |> standardize() |> validate()
# source2 <- clean_source2() |> standardize() |> validate()

# Combine 
combined <- dplyr::bind_rows(i07)
# combined <- dplyr::bind_rows(i07, source2)

# Warn on duplicate (project_name, lead_entity) pairs 
key  <- paste(combined$project_name, combined$lead_entity, sep = " | ")
dups <- unique(key[duplicated(key)])
if (length(dups) > 0) {
  warning("Duplicate (project_name, lead_entity) pairs:\n  ", paste(dups, collapse = "\n  "))
}

# Provenance log 
message("\nSources:")
for (path in c(
  "data-raw/i07_Habitat_Restoration_Polygons/metadata.yaml"
  # add a path here for each new source
)) {
  entries <- yaml::read_yaml(path)
  if (!is.null(entries$source_name)) entries <- list(entries)
  for (m in entries) {
    message("  ", m$source_name, " | received ", m$received_date, " by ", m$received_by)
  }
}

# Write output 
dir.create("data-final", showWarnings = FALSE)
sf::st_write(combined, "data-final/dwr_hrl_restoration_projects.gpkg",
         layer = "restoration_projects", delete_layer = TRUE, quiet = TRUE)
message("\nWrote ", nrow(combined), " features -> data-final/dwr_hrl_restoration_projects.gpkg")
