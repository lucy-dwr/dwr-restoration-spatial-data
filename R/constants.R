# Enum vectors and required-field list are derived from the LinkML schema so
# they stay in sync automatically when a new schema release is dropped into
# schemas/ via a GitHub Action from the schema repo. Must be run from the
# project root (build.R always does this).
schema <- yaml::read_yaml("schemas/hrl_restoration_project.yaml")

PROJECT_STAGE_VALUES  <- names(schema$enums$ProjectStageEnum$permissible_values)
SYSTEM_VALUES         <- names(schema$enums$SystemEnum$permissible_values)
PROJECT_TYPE_VALUES   <- names(schema$enums$ProjectTypeEnum$permissible_values)
TARGET_SPECIES_VALUES <- names(schema$enums$TargetSpeciesEnum$permissible_values)

# geometry is excluded: it is a spatial column, not a regular attribute field.
REQUIRED_SUBMISSION_FIELDS <- setdiff(
  names(Filter(
    function(x) isTRUE(x$required),
    schema$classes$RestorationProjectRecord$slot_usage
  )),
  "geometry"
)

# Project types exempt from the acreage requirement. This rule appears only in
# schema prose, not as a machine-readable annotation; keep it hardcoded until
# the schema gains a structured acreage_exempt flag.
ACREAGE_EXEMPT_TYPES <- c(
  "fish screen installation or improvement",
  "fish passage improvement"
)

# Shapefile .dbf column names are limited to 10 characters. Submitters must
# use these short aliases. The pipeline renames them to canonical schema names
# before validation and storage.
#
# Key: shapefile column name (<=10 chars)
# Value: canonical schema field name
FIELD_NAME_MAP <- c(
  proj_name   = "project_name",
  proj_desc   = "project_description",
  stage       = "project_stage",
  con_name    = "contact_name",
  con_email   = "contact_email",
  lead_ent    = "lead_entity",
  contractor  = "contractors",
  early_impl  = "early_implementation",
  start_yr    = "construction_start_year",
  compl_yr    = "construction_completion_year",
  compl_cmts  = "construction_completion_year_comments",
  est_budget  = "estimated_budget",
  bdgt_cmts   = "estimated_budget_comments",
  fund_sec    = "funding_secured",
  fund_srcs   = "funding_sources",
  proj_type   = "project_type",
  ac_bypass   = "acreage_bypass_floodplain",
  ac_fish_fd  = "acreage_fish_food",
  ac_trib_fp  = "acreage_tributary_floodplain",
  ac_trib_re  = "acreage_tributary_rearing",
  ac_trib_sp  = "acreage_tributary_spawning",
  ac_tidal    = "acreage_tidal_wetland",
  tgt_spp     = "target_species"
  # Fields that need no aliasing (already <=10 chars and match canonical name):
  # system (6), acreage (7)
)
