# ---- Load libraries ----
library(tidyverse)
library(readxl)
library(httr)

# ---- Load data ----
# Functions
source("functions.R")

# Spending power
# Source: https://commonslibrary.parliament.uk/local-authority-data-finances/
GET("https://data.parliament.uk/resources/constituencystatistics/Local-government-finance.xlsx",
    write_disk(tf <- tempfile(fileext = ".xlsx")))

spending <- read_excel(tf, sheet = "Spending power", skip = 2)  # check the sheet name is still valid if you're updating the URL above
unlink(tf); rm(tf)

# Popoulation estimates
pop <- read_csv("data/population estimates msoa11 lad17 lad19 tacticall cell.csv")

# Lookup table for LA's
# Source: https://github.com/tomalrussell/uklad-changes/blob/master/lad_nmcd_changes.csv
lookup_la <- read_csv("https://raw.githubusercontent.com/tomalrussell/uklad-changes/master/lad_nmcd_changes.csv")

# ---- Clean data ----
pop <-
  pop %>% 
  distinct(LAD17CD, LAD19CD, pop_lad19)

lookup_la <-
  lookup_la %>% 
  select(lad11cd, lad17cd)

# Remove footer from spreadsheet, select only relevant years
clean_spending <-
  spending %>% 
  slice(-353:-355) %>% 
  select(lad11cd = `ONS code`,
         spend_1718 = `2017/18`,
         spend_1819 = `2018/19`,
         spend_1920 = `2019/20`,
         spend_2021 = `2020/21`) %>% 
  mutate(spend_1920 = as.double(spend_1920),
         spend_2021 = as.double(spend_2021))

# Keep only the most updated financial spend data
clean_spending <-
  clean_spending %>% 
  mutate(spend_millions = case_when(
    !is.na(spend_2021) ~ spend_2021,
    is.na(spend_2021) & !is.na(spend_1920) ~ spend_1920,
    is.na(spend_2021) & is.na(spend_1920) ~ spend_1819
  )) %>% 
  select(lad11cd, spend_millions)
  
# The financial spending data uses 2011 LA codes. These codes need to be realigned with the 2019 codes
# being used throughout the analysis
# First, Separate the 2017 and 2019 LA codes
spending_lad17cd <-
  clean_spending %>% 
  left_join(lookup_la, by = "lad11cd") %>% 
  filter(!str_detect(lad11cd, "^E1")) %>% 
  filter(!is.na(lad17cd)) %>% 
  select(LAD17CD = lad17cd,
         spend_millions)

spending_lad19cd <-
  clean_spending %>% 
  left_join(lookup_la, by = "lad11cd") %>% 
  filter(!str_detect(lad11cd, "^E1")) %>% 
  filter(is.na(lad17cd)) %>% 
  select(LAD19CD = lad11cd,
         spend_millions)

# Join spending data to pop data and merge codes
spend_pop17 <- 
  spending_lad17cd %>% 
  left_join(pop, by = "LAD17CD") %>% 
  select(LAD19CD, spend_millions, pop_lad19) %>% 
  group_by(LAD19CD) %>% 
  # Aggregate across repeat LA codes
  mutate(spend_millions = sum(spend_millions),
         pop_lad19 = sum(pop_lad19)) %>% 
  ungroup() %>% 
  distinct(LAD19CD, .keep_all = TRUE)

spend_pop19 <-
  spending_lad19cd %>% 
  left_join(pop, by = "LAD19CD") %>% 
  select(-LAD17CD) %>% 
  group_by(LAD19CD) %>% 
  # Aggregate across repeat LA codes
  mutate(spend_millions = sum(spend_millions),
         pop_lad19 = sum(pop_lad19)) %>% 
  ungroup() %>% 
  distinct(LAD19CD, .keep_all = TRUE)

spend_pop <-
  bind_rows(spend_pop17,
            spend_pop19)

# Function to invert rank
normalised_spending <-
  spend_pop %>% 
  mutate(spend_weighted = spend_millions/pop_lad19,
         spend_ranked = rank(spend_weighted),
         spend_rank_inverted = invert_this(spend_ranked)) %>% 
  select(LAD19CD,
         `LA spending power (£m)` = spend_millions,
         # population = pop_lad19,
         `LA spending power (£m per capita)` = spend_weighted,
         `LA spending power rank` = spend_rank_inverted)

# Save
write_csv(normalised_spending, "data/processed/LA spending power.csv")
