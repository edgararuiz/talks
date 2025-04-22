library(tidyverse)
library(tidymodels)
library(pins)

lendingclub_dat <- read_csv("endtoend/loans_full_schema.csv")

set.seed(1234)

train_test_split <- initial_split(lendingclub_dat)
lend_train <- training(train_test_split)
lend_test <- testing(train_test_split)

red_rec_obj <- recipe(interest_rate ~ ., data = lend_train) |>
  step_mutate(homeownership = factor(homeownership, levels = c("MORTGAGE", "RENT", "OWN"))) |> 
  step_rm(emp_title, state, state, application_type, verified_income, 
          verification_income_joint, loan_purpose, application_type, grade, sub_grade,
          issue_month, loan_status, initial_listing_status, disbursement_method) |> 
  step_zv(all_predictors()) |>   
  step_integer(homeownership) |> 
  step_normalize(all_numeric_predictors()) |>
  step_impute_mean(all_numeric_predictors())

lend_linear <- 
  linear_reg()

lend_linear_wflow <-
  workflow() |>
  add_model(lend_linear) |>
  add_recipe(red_rec_obj)

lend_linear_fit <-
  lend_linear_wflow |>
  fit(data = lend_train)


board <- board_databricks("/Volumes/sol_eng_demo_nickp/end-to-end/r-models")
pin_write(board, lend_linear_fit, "lending-model-linear")


library(tidyverse)
library(tidymodels)
library(pins)
board <- board_databricks("/Volumes/sol_eng_demo_nickp/end-to-end/r-models")
model <- pin_read(board, "lending-model-linear")
lendingclub_dat <- read_csv("endtoend/loans_full_schema.csv")
predict(model, lendingclub_dat)


# ----------------------------- data from table -------------------------------
library(tidymodels)
library(sparklyr)
library(dplyr)
library(pins)

sc <- spark_connect(method = "databricks_connect", version = "15.4")

tbl_lending <- tbl(sc, I("sol_eng_demo_nickp.`end-to-end`.loans_full_schema"))

local_lending <- tbl_lending |> 
  sample_n(1000) |> 
  collect()


set.seed(1234)

clean_lending <- local_lending |> 
  select(
    interest_rate, paid_total, 
    paid_interest, paid_late_fees, annual_income,
    accounts_opened_24m, num_satisfactory_accounts,
    current_accounts_delinq, current_installment_accounts
    ) 

train_test_split <- initial_split(clean_lending)
lend_train <- training(train_test_split)
lend_test <- testing(train_test_split)

red_rec_obj <- recipe(interest_rate ~ ., data = lend_train) |>
  step_zv(all_predictors()) |>   
  step_filter_missing(all_numeric_predictors()) |> 
  step_normalize(all_numeric_predictors()) |>
  step_impute_mean(all_numeric_predictors())

lend_linear <- linear_reg()

lend_linear_wflow <- workflow() |>
  add_model(lend_linear) |>
  add_recipe(red_rec_obj)

lend_linear_fit <- lend_linear_wflow |>
  fit(data = lend_train)

lend_linear_fit

predict(lend_linear_fit, lend_test)  |> 
  ggplot() +
  geom_histogram(aes(.pred))

predict(lend_linear_fit, local_lending) |> 
  ggplot() +
  geom_histogram(aes(.pred))


board <- board_databricks("/Volumes/sol_eng_demo_nickp/end-to-end/r-models")
pin_write(board, lend_linear_fit, "lending-model-linear")

meta <- pin_meta(board, "lending-model-linear")

url_pin <- paste(board$folder_url, "lending-model-linear", meta$local$version, meta$file, sep = "/")
url_pin

lending_predict <- function(local_lending) {
  library(tidymodels)
  library(tidyverse)
  library(pins)
  url_pin <- "/Volumes/sol_eng_demo_nickp/end-to-end/r-models/lending-model-linear/20250421T150450Z-321f3/lending-model-linear.rds"
  if(file.exists(url_pin)) {
    model <- readRDS(url_pin)  
  } else {
    board <- board_databricks("/Volumes/sol_eng_demo_nickp/end-to-end/r-models")
    model <- pin_read(board, "lending-model-linear")
  }
  preds <- predict(model, local_lending)
  local_lending |> 
    bind_cols(preds)
}
lending_predict(local_lending)

#------------------------------------ prediction -----------------------------

pak::pak("mlverse/pysparklyr")

library(tidymodels)
library(sparklyr)
library(dplyr)
library(pins)

sc <- spark_connect(method = "databricks_connect")

tbl_lending <- tbl(sc, I("sol_eng_demo_nickp.`end-to-end`.loans_full_schema"))

board <- board_databricks("/Volumes/sol_eng_demo_nickp/end-to-end/r-models")

model <- pin_read(board, "lending-model-linear")

tbl_result <- tbl_lending |> 
  head(100) |> 
  spark_apply(lending_predict) |> 
  collect()

tbl_result |> 
  ggplot() +
    geom_histogram(aes(x = `_pred`), binwidth = 10)

tbl_result |> 
  ggplot() +
  geom_histogram(aes(x = interest_rate), binwidth = 10)


tbl_lending |> 
  spark_apply(lending_predict) |> 
  dbplot::dbplot_histogram(`_pred`)


library(tidymodels)

tbl_selected <- tbl_result |> 
  select(
    paid_total, 
    paid_late_fees, annual_income,
    accounts_opened_24m, num_satisfactory_accounts,
    current_accounts_delinq, current_installment_accounts
  ) |> 
  mutate(match = 1) |> 
  head(1)


tbl_paid_int <- tibble(paid_interest = paid_interest <- c(100, c(1:8) * 500), match = 1)


board <- board_databricks("/Volumes/sol_eng_demo_nickp/end-to-end/r-models")
model <- pin_read(board, "lending-model-linear")

full_table <- tbl_paid_int |> 
  full_join(tbl_selected, by = "match") |> 
  mutate(annual_income = 15000)

preds <- predict(model, full_table)

full_table |> 
  bind_cols(preds) |> 
  ggplot(aes(x = paid_interest, `.pred`)) +
  geom_line(color = "#ddd") +
  geom_text(aes(label = format(.pred, digits = 4)), nudge_y = 0.5, size = 3) +
  theme_minimal() +
  scale_y_continuous(limits = c(0, 35)) +
  theme(panel.grid = element_blank()) 
  


