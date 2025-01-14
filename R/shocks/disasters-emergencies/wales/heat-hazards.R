# ---- Load ----
library(tidyverse)
library(sf)
library(geographr)
library(demographr)

source("R/utils.R")

raw <-
  read_sf("data/on-disk/heat-hazard-raw/england/LSOA_England_Heat_Hazard_v1.shp")

# ---- Prep ----
lsoa_pop <-
  population_lsoa_20_codes_11 |>
  select(lsoa_code = lsoa_11_code, total_population)

lookup_lsoa_lad <-
  lookup_lsoa11_ltla21 |>
  select(lsoa_code = lsoa11_code, lad_code = ltla21_code) |>
  filter(str_detect(lsoa_code, "^W"))

heat_hazard_raw <-
  raw |>
  st_drop_geometry() |>
  select(
    lsoa_code = LSOA11CD,
    mean_temp = mean_std_t
  ) |>
  filter(str_detect(lsoa_code, "^W"))

# ---- Join ----
heat_hazard_raw_joined <-
  heat_hazard_raw |>
  left_join(lookup_lsoa_lad) |>
  relocate(lad_code, .after = lsoa_code) |>
  left_join(lsoa_pop) |>
  select(-lsoa_code)

# ---- Compute extent scores ----
extent <-
  heat_hazard_raw_joined |>
  calculate_extent(
    var = mean_temp,
    higher_level_geography = lad_code,
    population = total_population,
    weight_high_scores = TRUE
  )

# ---- Normalise, rank, & quantise ----
heat_hazard_quantiles <-
  extent |>
  normalise_indicators() |>
  mutate(rank = rank(extent)) |>
  mutate(quantiles = quantise(rank, 5)) |>
  select(lad_code, heat_hazard_quintiles = quantiles)

# ---- Save ----
heat_hazard_quantiles |>
  write_rds("data/shocks/disasters-emergencies/wales/heat-hazard.rds")