# AGENTS.md

## Purpose

This repository contains vector spatial data delineating the boundaries of California Department of Water Resources (DWR) Healthy Rivers and Landscapes (HRL) program restoration projects. It cleans and integrates raw, varied source data into a single standardized GeoPackage conforming to the **RestorationProjectSubmission** profile of the HRL schema — DWR's submission to the program-wide Azure-hosted dataset. Program-assigned fields (`project_id`, `update_date`) and derived fields (`funding_gap`) are added downstream by the program-wide ingestion pipeline, not here.

## Repository structure

```
build.R                                     # Run this: Rscript build.R
R/
  constants.R                               # Enum values, field name map, required fields
  validate.R                                # validate(): accepts an sf object, warns on issues
  standardize.R                             # standardize(): reproject, clean, format fields
  i07.R                                     # clean_i07(): reads i07 source, returns sf object
data-raw/
  <original_name>/                          # Directory named as received (original source name)
    *.shp  *.shx  *.dbf  *.prj  [...]       # Shapefile sidecar files — OR *.gpkg / *.geojson
    metadata.yaml                           # Provenance sidecar (required for all sources)
data-final/
  dwr_hrl_restoration_projects.gpkg         # Submission dataset — all projects, EPSG:3310,
                                            # RestorationProjectSubmission schema
schemas/
  hrl_restoration_project.yaml             # LinkML schema, updated with each tagged schema release
```

## Schema

All attributes must conform to the LinkML schema at:
`https://github.com/lucy-dwr/hrl-restoration-schema/blob/main/schemas/hrl_restoration_project.yaml`

The schema defines two record profiles. This repository produces data conforming to **RestorationProjectSubmission**. The downstream program-wide pipeline extends it to **RestorationProjectCanonicalRecord** by adding `project_id`, `update_date`, and requiring `funding_gap`.

`schemas/hrl_restoration_project.yaml` is kept in sync automatically: when a release is published in `lucy-dwr/hrl-restoration-schema`, a GitHub Actions workflow in that repo opens a pull request here copying the schema file from the release tag. Review and merge that PR before re-running `build.R` if enum values or required fields have changed.

## Field rules (submission profile)

### Required fields

- `project_name`
- `project_description`
- `project_stage`
- `contact_name`
- `contact_email`
- `lead_entity`
- `early_implementation`
- `construction_start_year`
- `construction_completion_year`
- `estimated_budget`
- `funding_secured`
- `system`
- `project_type`
- `target_species`
- `geometry`

### Controlled vocabularies (enums)

Enum fields are normalized for case and common aliases at standardization time before validation (e.g. `Construction` → `construction`, `Post-Construction` → `post-construction monitoring and science`, whitespace around semicolons trimmed). Values that cannot be normalized to a valid enum are flagged as a warning. The canonical allowed values are:

| Field | Allowed values |
|---|---|
| `project_stage` | `concept/feasibility`, `CEQA`, `permitting`, `design`, `construction`, `post-construction monitoring and science` |
| `system` | `American`, `Delta`, `Feather`, `Mokelumne`, `Putah`, `Sacramento`, `Sutter Bypass`, `Tuolumne`, `Yolo Bypass`, `Yuba`, `Other` |
| `project_type` | `bypass floodplain habitat`, `fish food production`, `fish passage improvement`, `fish screen installation or improvement`, `rearing habitat`, `spawning habitat`, `tidal habitat`, `tributary floodplain habitat`, `other` |
| `target_species` | See `TargetSpeciesEnum` in schema for the full list of 25 native fish species |

Multivalued fields (`project_stage`, `project_type`, `target_species`, `contractors`, `funding_sources`) are semicolon-delimited in submitted shapefiles; store as semicolon-delimited strings in the submission GeoPackage.

### Numeric constraints

| Field | Min | Max |
|---|---|---|
| `construction_start_year` | 2018 | 2035 |
| `construction_completion_year` | 2018 | 2040 |
| `estimated_budget` | 0 | — |
| `funding_secured` | 0 | — |
| `acreage` and all `acreage_*` fields | 0 | — |

### Text length limits

| Field | Max characters |
|---|---|
| `project_description` | 500 (truncate on ingest) |
| `construction_completion_year_comments` | 250 (truncate on ingest) |
| `estimated_budget_comments` | 500 (truncate on ingest) |

`contact_email` must match `^[^@\s]+@[^@\s]+\.[^@\s]+$`.

### Acreage rule

`acreage` is required unless `project_type` contains only `fish screen installation or improvement` and/or `fish passage improvement`.

## Geometry rules

- Accepted input types: `POLYGON`, `MULTIPOLYGON`, `POINT`, `MULTIPOINT`
- All polygon features must be stored as `MULTIPOLYGON`; all point features as `MULTIPOINT` (upgrade single-part geometries on ingest)
- Submitted data may use any common California projected CRS or WGS84; all features in `data-final/` must be in **NAD83 / California Albers, EPSG:3310**
- Every submitted file must carry a defined CRS (warns if `.prj` is missing or CRS is undefined)
- Validate: geometry validity, CRS presence, extent within California, slivers, duplicate geometries, and project-type-specific geometry rules (e.g., point geometry for fish passage/screen projects is acceptable; polygon required for habitat acreage projects)

## Shapefile field names

Shapefile `.dbf` files limit column names to 10 characters. Submitters must use the following short aliases; the pipeline renames them to canonical schema names before validation and storage. Using geopackages is preferred when possible to avoid this character limit.

| Shapefile alias | Canonical field name |
|---|---|
| `proj_name` | `project_name` |
| `proj_desc` | `project_description` |
| `stage` | `project_stage` |
| `con_name` | `contact_name` |
| `con_email` | `contact_email` |
| `lead_ent` | `lead_entity` |
| `contractor` | `contractors` |
| `early_impl` | `early_implementation` |
| `start_yr` | `construction_start_year` |
| `compl_yr` | `construction_completion_year` |
| `compl_cmts` | `construction_completion_year_comments` |
| `est_budget` | `estimated_budget` |
| `bdgt_cmts` | `estimated_budget_comments` |
| `fund_sec` | `funding_secured` |
| `fund_srcs` | `funding_sources` |
| `proj_type` | `project_type` |
| `ac_bypass` | `acreage_bypass_floodplain` |
| `ac_fish_fd` | `acreage_fish_food` |
| `ac_trib_fp` | `acreage_tributary_floodplain` |
| `ac_trib_re` | `acreage_tributary_rearing` |
| `ac_trib_sp` | `acreage_tributary_spawning` |
| `ac_tidal` | `acreage_tidal_wetland` |
| `tgt_spp` | `target_species` |
| `system` | `system` (no alias needed) |
| `acreage` | `acreage` (no alias needed) |

## Pipeline

### Environment setup

To set up the environment for the first time:

```r
install.packages(c("sf", "dplyr", "yaml"))

# Initialize renv and capture the lockfile
renv::init()
```

To restore a previously snapshotted environment:

```r
renv::restore()
```

### Running the pipeline

```bash
Rscript build.R
```

`build.R` is the single entrypoint. It sources the helper files in `R/`, calls each source's `clean_*()` function, standardizes and then validates the result, combines all sources, and writes `data-final/dwr_hrl_restoration_projects.gpkg`.

### Adding a new source

Every source directory requires a `metadata.yaml` provenance sidecar. Copy the template and fill it in:

```bash
cp data-raw/metadata_template.yaml data-raw/<original_name>/metadata.yaml
```

Required fields:

| Field | Description | Allowed values |
|---|---|---|
| `source_type` | How the data was obtained | `agol`, `email`, `sharepoint`, `cnra_portal`, `other` |
| `source_name` | Human-readable source description | free text |
| `original_filename` | Filename as received, before copying here | free text |
| `received_date` | Date data was received | `YYYY-MM-DD` |
| `received_by` | Name of person who added the data | free text |
| `content` | Narrative description of what the file contains | free text |
| `notes` | Optional additional context (caveats, known issues, etc.) | free text or `~` |

Then:

1. Copy source files into `data-raw/<original_name>/`
2. Fill in `data-raw/<original_name>/metadata.yaml`
3. Write `R/<name>.R` with a `clean_<name>()` function that reads the source, applies any custom filtering or attribute joining, and returns an sf object with canonical column names. Set `attr(result, "source")` to the primary source file path (used in validation error messages).
4. Add to `build.R`:
   - `source("R/<name>.R")`
   - `<name> <- clean_<name>() |> standardize() |> validate()`
   - Add `<name>` to the `bind_rows(...)` call
   - Add the `metadata.yaml` path to the provenance log loop

### What the pipeline enforces

- Standardization runs before validation: enum normalization, reprojection, geometry upgrade, and text truncation all happen first so that validation checks the final form of the data
- Enum fields (`project_stage`, `project_type`, `system`, `target_species`) are normalized for case and common aliases; whitespace around semicolons is trimmed
- Text fields are truncated to schema limits at standardization time
- Geometry is reprojected to EPSG:3310 and upgraded to MULTI types
- `early_implementation` is normalized to a logical value regardless of how the source encodes it
- Validation issues are reported as warnings — the pipeline always produces output; review warnings before submitting to the program pipeline
- A warning is issued if the same `(project_name, lead_entity)` pair appears in more than one source — resolve before submitting to the program pipeline
- Raw source data is never modified; `data-final/` is always fully regenerated from `data-raw/`

### Never do

- Do not edit `data-final/` by hand; all changes must flow through the pipeline
- Do not add `project_id` or `update_date` to source data; those are program-assigned downstream

## Git workflow

- **Core maintainers** may push directly to `main`
- **External contributors** must open a pull request; do not merge until validation passes
- Commit messages: `add: <original_name>` for new submissions, `update: <original_name> <brief reason>` for edits to existing source data
- Do not commit large binary shapefiles without confirming with the maintainer that LFS is configured

## Azure publication

`data-final/dwr_hrl_restoration_projects.gpkg` is DWR's submission to the program-wide Azure dataset. Any push to `main` that modifies `data-final/` should be treated as a potential submission event. The program-wide pipeline is responsible for assigning `project_id` and `update_date`, calculating `funding_gap`, and producing the canonical record.
