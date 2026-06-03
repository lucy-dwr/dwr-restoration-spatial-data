clean_i07 <- function() {
  geojson <- "data-raw/i07_Habitat_Restoration_Polygons/i07_Habitat_Restoration_Polygons.geojson"
  csv     <- "data-raw/i07_Habitat_Restoration_Polygons/i07_attributes.csv"

  attrs <- read.csv(csv, na.strings = c("", "NA"), stringsAsFactors = FALSE) |>
    dplyr::mutate(
      early_implementation         = as.logical(early_implementation),
      construction_start_year      = dplyr::na_if(as.integer(construction_start_year), 0L),
      construction_completion_year = dplyr::na_if(as.integer(construction_completion_year), 0L),
    )

  geom <- sf::st_read(geojson, quiet = TRUE) |>
    dplyr::mutate(atlas_name = trimws(project_name)) |>
    dplyr::filter(atlas_name %in% attrs$atlas_name) |>
    dplyr::select(atlas_name)

  result <- dplyr::left_join(geom, attrs, by = "atlas_name") |>
    dplyr::select(-atlas_name, -atlas_id)
  attr(result, "source") <- geojson
  result
}
