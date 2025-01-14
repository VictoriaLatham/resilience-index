# Fire station response time is not included for now (17/03) as don't have LTLA level data 
# (only FRA level). Include again when get this from Gov. 

# ---- Load libraries and Functions ----
library(tidyverse)
library(demographr)

source("https://raw.githubusercontent.com/britishredcrosssociety/resilience-index/main/R/utils.R")

# ---- Load indicators ----
indicators <-
  load_indicators(
    path = "data/capacity/disasters-emergencies/england",
    key = "lad_code"
  )

# # Check entry for all 2021 LAD codes
# lads_21 <- lookup_lad_counties_21 |>
#   filter(str_detect(lad_21_code, "^E")) |>
#   distinct(lad_code = lad_21_code) 

# lads_21 |>
#   anti_join(indicators, by = "lad_code")

# indicators |>
#   anti_join(lads_21, by = "lad_code")

# indicators |>
#   dplyr::filter(if_any(everything(), ~is.na(.x))) 
# # City of London & Isle of Scilly are both missing civic assests & engagement
# # Assumption: drop these LADs due to too many missing variables. 

indicators_complete <- indicators |>
  drop_na()

# Align direction so that high score = low capacity 
indicators_aligned <- indicators_complete |>
  mutate(cps_millions = cps_millions * -1)

# ---- Build Index ----

# Check distribution
indicators_aligned |>
  normalise_indicators() |> 
  summary()

de <-
  indicators_aligned |>
  normalise_indicators() |>
  calculate_domain_scores(domain_name = "de") 

# Inverting ranks and deciles so that higher scores = higher capacity
de_invert <- de |>
  mutate(de_domain_rank = inverse_rank(de_domain_rank),
         de_domain_quantiles = invert_this(de_domain_quantiles))

# Save index
de_invert |>
  write_csv("data/capacity/disasters-emergencies/england/de-index.csv")




