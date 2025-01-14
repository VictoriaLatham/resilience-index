# Load packages
library(tidyverse)
library(readxl)
library(geographr)

source("https://raw.githubusercontent.com/britishredcrosssociety/resilience-index/main/R/utils.R") # for download_file() & calculate_extent()


# OSCI Community Needs Index data ----
# Prepare the Community Needs Index, showing the Index and its domains for all Wards, along with which are the left-behind areas
# More info: https://ocsi.uk/2019/10/21/community-needs-index-measuring-social-and-cultural-factors/
# The data isn't public but OCSI can provide it to social purpose organisations - email them for info
# Data is at 2017 ward level
osci <- read_excel("data/on-disk/OSCI/community-needs-index/Community Needs Index domain scores.xlsx")

civic_assests <- osci |>
  select(
    ward_code = "Ward Code",
    lad_name = "LA Name",
    lad_code = "LA code",
    civic_assests_score = "Civic Assets score",
    civic_assets_rank = "Civic Assets rank"
  )
# Higher score and therefore lower rank is the LACK of assets so HIGH SCORE/LOW RANK = LOW CAPABILITIES
# Civic assets + Engagement + Connectness = Community Need score (high score = high need)

# Method used in COVID-VI -----
# Code here https://github.com/britishredcrosssociety/covid-19-vulnerability/blob/master/prep%20community%20needs%20index.r
# Output here https://raw.githubusercontent.com/britishredcrosssociety/covid-19-vulnerability/master/data/community-needs-LA.csv
# 'Proportion of wards with greatest community needs' column used in resilience index part: https://github.com/britishredcrosssociety/covid-19-vulnerability/blob/bccb08ef4da822d7beb01e56e4a26610bed33b11/bespoke%20vulnerability%20index%20-%20resilience/create%20resilience%20index%20-%20LA.r#L27
# Rest of the columns used in vulnerability index part (although wasn't used in the end build and only in resilience part) https://github.com/britishredcrosssociety/covid-19-vulnerability/blob/bccb08ef4da822d7beb01e56e4a26610bed33b11/create%20vulnerability%20index%20-%20LA.r#L113
# Interested in 'Proportion of wards with worst Community Assets scores' column as this is 'Civic assets'

# Method used:
# Reverse ranks (so highest rank reflects most vulnerable)
# Joined a 2017 to 2019 LAD look up
# Calculated those with ranks in the lowest 5% (quintile) i.e. 'most vulnerable'
# Then aggregated up to LADs using by calculating the % of wards that are 'most vulnerable' within a LAD


# Alternative method to use calculate_extent() with ward population ----
# Use this method for consistency across other indicators in the Index

# 2017 ward population counts
# Use 2017 figure since OSCI data uses 2017 ward codes and these change over time
# Source: https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/datasets/wardlevelmidyearpopulationestimatesexperimental
tf <- download_file(
  "https://www.ons.gov.uk/file?uri=%2fpeoplepopulationandcommunity%2fpopulationandmigration%2fpopulationestimates%2fdatasets%2fwardlevelmidyearpopulationestimatesexperimental%2fmid2017sape20dt8/sape20dt8mid2017ward2017syoaestimatesunformatted1.zip",
  ".zip"
)

tf |>
  unzip(exdir = tempdir())

raw <- read_excel(paste0(tempdir(), "/SAPE20DT8-mid-2017-ward-2017-syoa-estimates-unformatted.xls"),
  sheet = "Mid-2017 Persons",
  skip = 3
)

ward_pop <- raw |>
  select(
    ward_code = "Ward Code 1",
    population = "All Ages"
  )

# Check wards if any wards with no pop data
civic_assests |>
  left_join(ward_pop, by = "ward_code") |>
  filter(is.na(population))

# Read in LAD17 to LAD19 lookup (unsure of source of this data but used in COVID-VI) ----
raw_lad_lookup <- read_csv("https://raw.githubusercontent.com/britishredcrosssociety/covid-19-vulnerability/master/data/lookup%20mosa11%20to%20lad17%20to%20lad19%20to%20tactical%20cell.csv")

lad_lookup_17_19 <- raw_lad_lookup |>
  distinct(LAD17CD, LAD19CD) |>
  filter(str_detect(LAD17CD, "^E"))

lad_lookup_19_21 <- lookup_lad_lad |>
  distinct(lad_19_code, lad_21_code)

lad_lookup <- lad_lookup_17_19 |>
  left_join(lad_lookup_19_21, by = c("LAD19CD" = "lad_19_code")) |>
  distinct(lad_17_code = LAD17CD, lad_21_code)

# Check changes between 2017 to 2021 are always aggregation rather than disaggregation
# As would mean different approaches
lad_lookup |>
  group_by(lad_17_code) |>
  summarise(count = n()) |>
  filter(count > 1)

lad_lookup |>
  group_by(lad_21_code) |>
  summarise(count = n()) |>
  filter(count > 1)
# Only aggregation from multiple 2017 codes to a single 2021 code

# Check any missing LADs
lad_lookup |>
  anti_join(civic_assests, by = c("lad_17_code" = "lad_code"))
# 2 LADs not in dataset (Isle of Scilly & Inner London)

# Join datasets & calculate extent ----
# Note: high score (i.e. lowest rank) reflects low capability
civic_assests_lad <- civic_assests |>
  left_join(ward_pop, by = "ward_code") |>
  left_join(lad_lookup, by = c("lad_code" = "lad_17_code")) |>
  calculate_extent(
    var = civic_assests_score,
    higher_level_geography = lad_21_code,
    population = population,
    weight_high_scores = TRUE #  TRUE when a highest variable score equates to a lower capacity
  ) |>
  rename(lad_code = lad_21_code, civic_assests_extent = extent)

# Bind on missing values for Isle of Scilly & Inner London otherwise then don't get included into 
civic_assests_lad_update <- civic_assests_lad |>
  bind_rows(tibble(lad_code = c("E06000053", "E09000001")))

civic_assests_lad |>
  ggplot(aes(x = civic_assests_extent)) +
  geom_boxplot()

# Save data -----
civic_assests_lad_update |>
  write_rds("data/capacity/disasters-emergencies/england/community-assets.rds")
