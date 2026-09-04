library(tidymodels)
library(readmission)
library(tictoc)
library(future)
plan(multisession)

set.seed(231)
readmission_splits <- initial_split(readmission, strata = readmitted)

readmission_folds <- vfold_cv(training(readmission_splits), strata = readmitted)

recipe_basic <- recipe(readmitted ~ ., data = training(readmission_splits)) |>
  step_other(race, threshold = 0.1, other = "zzz") |>
  step_unknown(all_nominal_predictors()) |>
  step_YeoJohnson(all_numeric_predictors()) |>
  step_normalize(all_numeric_predictors()) |>
  step_dummy(all_nominal_predictors())

spec_bt <- boost_tree(
  mode = "classification",
  trees = 500,
  mtry = tune(),
  min_n = tune(),
  learn_rate = tune(),
  tree_depth = tune()
)

bt_grid <- grid_space_filling(
  mtry(range = c(5, 20)),
  min_n(),
  learn_rate(),
  tree_depth(),
  size = 100
)

tic()
local_results <- tune_grid(
  object = spec_bt,
  preprocessor = recipe_basic,
  resamples = readmission_folds,
  grid = bt_grid,
  control = control_grid()
)
toc()
