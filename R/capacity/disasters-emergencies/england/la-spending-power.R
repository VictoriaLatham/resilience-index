# Load packages
library(geographr)
library(sf)
library(tidyverse)
library(readxl)

source("R/utils.R")

# Spending power data ----
# Source: https://commonslibrary.parliament.uk/local-authority-data-finances/
tf <- download_file("https://data.parliament.uk/resources/constituencystatistics/Local-government-finance-2021.xlsx", ".xlsx")

raw <- read_excel(tf, sheet = "Spending power", skip = 3)

clean <- raw |>
  select(lad_code = `ONS code`, 
         lad_name = `Local authority`, 
         geo_type = `Local authority class`, 
         cps_millions = `2021/22`)

clean |>
  distinct(geo_type)
# There are a mix og geographic types in the data so will take each in turn

# LTLA -----

# Load in population data
lad_pop <-
  population_lad |>
  select(lad_code, 
         pop = total_population) |>
  filter(str_detect(lad_code, "^E"))

# Check if using 2021 LAD codes
if (
  anti_join(
    lad_pop,
    lookup_lad_over_time,
    by = c("lad_code" = "LAD21CD")
  ) |>
    pull(lad_code) |>
    length() != 0
) {
  stop("Lad codes need changing to 2021 - check if 2019 or 2020")
}

# Update population from 2020 to 2021
# Aggregation only of LADs between 2019 to 2021

# Distinct table foe 2020 - 2021 due to E06000060
lookup_lad_over_time_2020 <- lookup_lad_over_time |>
  distinct(LAD20CD, LAD21CD)

lad_pop_update <- lad_pop |>
  left_join(lookup_lad_over_time_2020, by = c("lad_code" = "LAD20CD")) |>
  group_by(LAD21CD) |>
  summarise(across(where(is.numeric), sum))

ltla_cps <- lad_pop_update |>
  left_join(clean, by = c("LAD21CD" = "lad_code")) |>
  select(LAD21CD, cps_millions)

# Check any LTLAs not in the data
lad_pop_update |>
  anti_join(clean, by = c("LAD21CD" = "lad_code"))
# None missing

remaining_ltla <- clean |>
  anti_join(lad_pop_update, by = c("lad_code" = "LAD21CD"))

# Fire & Rescue Authorities ----
fire_cps <- remaining_ltla |>
  filter(geo_type == "Fire authority") |>
  rename(fra_code = lad_code, 
         fra_name = lad_name)

# FRA to LAD lookup data
# Source: https://geoportal.statistics.gov.uk/datasets/ons::local-authority-district-to-fire-and-rescue-authority-april-2021-lookup-in-england-and-wales/about
response <- httr::GET("https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services/LAD21_FRA21_EW_LU/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=json")
content <- httr::content(response, type = "application/json", simplifyVector = TRUE)

fra_lad_lookup <- content$features$attributes |>
  select(ltla_code = LAD21CD, 
         ltla_name = LAD21NM, 
         fra_code = FRA21CD, 
         fra_name = FRA21NM) |>
  filter(!str_detect(fra_name, "Wales"))

# Check if all FRS in the data
fra_lad_lookup |>
  anti_join(fire_cps, by = "fra_code") |>
  distinct(fra_name)
# 15 of the of the 44 FRAs are not in the spending power data
# Reply from Papers@parliament.uk on this: 
# In the case of the fire authorities which are not in this data set, 
# the fire and rescue service is run directly by the County Council, so it is funded 
# via those councils’ settlements (and so are included in the data via the rows for the UTLA).
# The fire authorities DLUHC lists in its data are those which are separate 
# from their local councils for funding purposes, and receive their own settlements.

ltla_fire_cps <- fire_cps |>
  inner_join(fra_lad_lookup, by = "fra_code") |>
  left_join(lad_pop_update, by = c("ltla_code" = "LAD21CD")) |>
  group_by(fra_code) |>
  mutate(pop_weighted_cps = pop / sum(pop) * cps_millions) |>
  ungroup() |>
  select(LAD21CD = ltla_code, 
         cps_millions = pop_weighted_cps)

remaining_fire <- remaining_ltla |>
  filter(geo_type != "Fire authority")

# UTLAs -----

utla_pop <- population_counties_ua |>
  select(county_ua_code, pop = total_population)

utla_cps <- remaining_fire |>
  inner_join(utla_pop, by = c("lad_code" = "county_ua_code")) |>
  select(county_ua_code = lad_code, 
         county_ua_name = lad_name, 
         cps_millions)
# Only 16 UTLAs have spending power
# Reply from Papers@parliament.uk on this: 
# The upper-tier local authorities which have lower-tier authorities within them are the shire counties – in these areas, 
# local government responsibilities are split between the two tiers, so the councils in each tier get their own funding
# settlements and have their own spending power figures. Other areas (such as Greater London) are covered by single-tier 
# councils which take on all the responsibilities of both upper-tier and lower-tier authorities, but confusingly 
# these are generally also referred to as upper-tier authorities. There isn;t double counting of spending power
# it just depends on the area whether the responsibility is funded via the LTLA or UTLA. 

ltla_utla_cps <- utla_cps |>
  left_join(lookup_counties_ua_lad, by = "county_ua_code") |>
  left_join(lad_pop_update, by = c("lad_code" = "LAD21CD")) |>
  group_by(county_ua_code) |>
  mutate(pop_weighted_cps = ifelse(cps_millions == 0, 0, pop / sum(pop) * cps_millions)) |>
  ungroup() |>
  select(lad_code, 
         cps_millions = pop_weighted_cps)

# Update to 2021 LAD codes
ltla_utla_cps_updated <- ltla_utla_cps |>
  left_join(lookup_lad_over_time_2020, by = c("lad_code" = "LAD20CD")) |>
  group_by(LAD21CD) |>
  summarise(across(where(is.numeric), sum))

# Check if these LTLAs from splitting UTLAs are already in the data as LTLAs
ltla_utla_cps_updated |>
  inner_join(ltla_cps, by = "LAD21CD")
# Yes they are already in the LTLA level data so this spending power is in addition
# to the LTLA level spending power

remaining_utla <- remaining_fire |>
  anti_join(utla_cps, by = c("lad_code" = "county_ua_code"))
# These are all inactive codes (with spending as zero)
# except 'Greater Manchester Combined Authority' and 'Greater London Authority

# Combined Authority ----
# Combined Authority lookup source: https://geoportal.statistics.gov.uk/datasets/ons::local-authority-district-to-combined-authority-december-2020-lookup-in-england/about
response <- httr::GET("https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services/LAD20_CAUTH20_EN_LU/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=json")
content <- httr::content(response, type = "application/json", simplifyVector = TRUE)

combined_auth_lookup <- content$features$attributes |>
  select(-column4, 
         -FID)

# There are no changes between 2020 and 2021 LAD codes for Greater Manchester LTLAs
combined_auth_ltla_cps <- remaining_utla |>
  inner_join(combined_auth_lookup, by = c("lad_code" = "CAUTH20CD")) |>
  left_join(lad_pop_update, by = c("LAD20CD" = "LAD21CD")) |>
  mutate(pop_weighted_cps = pop / sum(pop) * cps_millions) |>
  select(LAD21CD = LAD20CD, 
         cps_millions)

# Check if these LTLAs from splitting UTLAs are already in the data as LTLAs
combined_auth_ltla_cps |>
  inner_join(ltla_cps, by = "LAD21CD")
# Yes they are already in the LTLA level data so this spending power is in addition
# to the LTLA level spending power

# Greater London Authority ----
# Source: https://data.london.gov.uk/dataset/london-borough-profiles
# Issues with column names having special characters
gla_clean <- read_csv("https://data.london.gov.uk/download/london-borough-profiles/c1693b82-68b1-44ee-beb2-3decf17dc1f8/london-borough-profiles.csv",
  col_names = FALSE
)

# Cleaning and removing any cumulative areas that are just combinations of the LTLAs
gla_lad_codes <- gla_clean |>
  select(lad_code = X1, 
         area = X2, 
         inner_outer = X3) |>
  slice(-1) |>
  filter(!is.na(inner_outer))

gla_lad_codes |>
  anti_join(lad_pop_update, by = c("lad_code" = "LAD21CD"))

gla_cps_value <- remaining_utla |>
  filter(lad_name == "Greater London Authority") |>
  pull(cps_millions)

gla_ltla_cps <- gla_lad_codes |>
  mutate(cps_millions = gla_cps_value) |>
  left_join(lad_pop_update, by = c("lad_code" = "LAD21CD")) |>
  mutate(pop_weighted_cps = pop / sum(pop) * cps_millions) |>
  select(LAD21CD = lad_code, 
         cps_millions = pop_weighted_cps)

# Check if these LTLAs from splitting GLA are already in the data as LTLAs
gla_ltla_cps |>
  inner_join(ltla_cps, by = "LAD21CD")
# Yes they are already in the LTLA level data so this spending power is in addition
# to the LTLA level spending power

# Combining all the data sets ---
combined <- ltla_cps |>
  bind_rows(ltla_fire_cps) |>
  bind_rows(ltla_utla_cps_updated) |>
  bind_rows(combined_auth_ltla_cps) |>
  bind_rows(gla_ltla_cps) |>
  group_by(lad_code = LAD21CD) |>
  summarise(cps_millions = sum(cps_millions))

# Save data ----
combined |>
  write_rds("data/capacity/disasters-emergencies/england/la-spending-power.rds")

