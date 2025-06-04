# Databricks + Tidymodels + Orbital
Edgar Ruiz - Posit
2025-05-22

- [Use case](#use-case)
- [Approach](#approach)
- [Download sample](#download-sample)
- [Fit locally](#fit-locally)
- [Convert to SQL using Orbital](#convert-to-sql-using-orbital)
- [Automate in Databricks](#automate-in-databricks)
- [Appendix](#appendix)
  - [Data in example](#data-in-example)

## Use case

Using loan data, we want to use a model that estimates an appropriate
interest rate, and then use that model to find out if the interest rate
for a given loan may have been too high. The loan data is in a table
located in the Databricks Unity Catalog. The ultimate objective of the
project, is to have it check on a daily basis to see what loans may an
issue.

## Approach

*“Fit small, predict big”*

To make it as close to a ‘real-life’ scenario, we will download a sample
of the table into our R session, fit a model using a Tidymodels, and
then use Orbital to translate the steps and estimates into a SQL
statement. Finally, we will use that SQL statement as the base to
compare the current interest against the prediction, and download the
loans that had a large difference. Thanks to the integrated environment
in Databricks, the resulting SQL statement will be saved in the
Databricks Workspace, and used to run on a schedule via a [Databricks
Job](https://docs.databricks.com/aws/en/jobs/).

<div id="fig-diagram">

``` mermaid
flowchart LR
  A[1-Full Table] --Download--> B(2-Sample) 
  B--Tidymodels fit-->C(3-Model)
  C--Orbital parse-->D(4-SQL)
  D--Automate-->E(5-Job)
  E--Predict-->A
```

Figure 1: Diagram of the approach used for this use case

</div>

## Download sample

1.  The
    [`odbc::databricks()`](https://odbc.r-dbi.org/reference/databricks.html)
    function provides lots of convenient features that handle
    essentially everything needed to establish a connection to
    Databricks. The only thing to provide is the `httpPath` in order to
    succeed. The connection is established via `DBI`.

    ``` r
    library(DBI)

    con <- dbConnect(
      drv = odbc::databricks(), 
      httpPath = "/sql/1.0/warehouses/b71952ebceb705ce"
      )
    ```

2.  Because they will be used in multiple locations in this example, the
    `catalog`, `schema`, and `table` name are loaded to variables

    ``` r
    catalog <- "sol_eng_demo_nickp"
    schema <- "end-to-end"
    table <- "loans_full_schema"
    ```

3.  Sample the database table using the `TABLESAMPLE` SQL function.
    `REPEATABLE` is used to aid with reproducibility. The `glue_sql()`
    function is used to compile the SQL statement.

    ``` r
    library(glue)

    sample_sql <- glue_sql(
      "SELECT * ", 
      "FROM ",
      "{`catalog`}.{`schema`}.{`table`}",
      "TABLESAMPLE (100 ROWS) REPEATABLE (999)",
      .con = con
      )

    sample_sql
    ```

        <SQL> SELECT * FROM `sol_eng_demo_nickp`.`end-to-end`.`loans_full_schema`TABLESAMPLE (100 ROWS) REPEATABLE (999)

4.  The sample is downloaded by executing the SQL statement via
    `dbGetQuery()`.

    ``` r
    sample_lending <- dbGetQuery(
      conn = con, 
      statement = sample_sql
      )
    ```

## Fit locally

1.  Load `tidymodels` and set the seed

    ``` r
    library(tidymodels)
    set.seed(999)
    ```

2.  Currently, **certain fields are downloaded from Databricks as
    Integer 64 type. These are not supported by R in general**. The
    easiest solution is to convert them to double. This needs to only be
    done in the local copy, since goal is to have a SQL statement that
    will run inside Databricks. To make the data transformation easy, we
    will use `dplyr`.

    ``` r
    library(dplyr)

    sample_lending <- sample_lending |> 
      mutate(
        total_credit_lines = as.double(total_credit_lines),
        loan_amount = as.double(loan_amount),
        term = as.double(term)
        )
    ```

3.  Split the data into training and testing.

    ``` r
    split_lending <- initial_split(sample_lending)

    lending_training <- training(split_lending)
    ```

4.  Create a `recipe` that defines the predictors and outcome fields,
    and includes a normalization step. For this example, we will use the
    `annual_income`, `total_credit_lines`, `loan_amount` and `term`
    fields for predictors.

    ``` r
    rec_lending <- recipe(
      interest_rate ~ annual_income + total_credit_lines + loan_amount + term, 
      data = lending_training
      ) |> 
      step_normalize(all_numeric_predictors())
    ```

5.  Define a linear regression model spec.

    ``` r
    lm_spec <- linear_reg()
    ```

6.  Create the workflow by combining the recipe and the defined model
    spec.

    ``` r
    wf_spec <- workflow(rec_lending, lm_spec)
    ```

7.  Fit the workflow using the training data, and preview

    ``` r
    wf_fit <- fit(wf_spec, lending_training)

    wf_fit
    ```

        ══ Workflow [trained] ══════════════════════════════════════════════════════════
        Preprocessor: Recipe
        Model: linear_reg()

        ── Preprocessor ────────────────────────────────────────────────────────────────
        1 Recipe Step

        • step_normalize()

        ── Model ───────────────────────────────────────────────────────────────────────

        Call:
        stats::lm(formula = ..y ~ ., data = data)

        Coefficients:
               (Intercept)       annual_income  total_credit_lines         loan_amount  
                   12.1961             -0.3791             -0.2425             -0.9216  
                      term  
                    2.0547  

## Convert to SQL using Orbital

1.  Load and use `orbital` to read the fitted workflow. In Databricks,
    names with dots (“.”) are not acceptable, and `.pred` is the default
    name that `orbital` gives the prediction. To fix, use the `prefix`
    to override.

    ``` r
    library(orbital)

    lending_orbital <-  orbital(wf_fit, prefix = "pred")

    lending_orbital
    ```


        ── orbital Object ──────────────────────────────────────────────────────────────
        • annual_income = (annual_income - 71942.79) / 42292.87
        • total_credit_lines = (total_credit_lines - 22.49333) / 11.66813
        • loan_amount = (loan_amount - 14928.33) / 9958.628
        • term = (term - 44.32) / 11.49872
        • pred = 12.19613 + (annual_income * -0.3791282) + (total_credit_lines * ...
        ────────────────────────────────────────────────────────────────────────────────
        5 equations in total.

2.  Load `dbplyr`, and use `tbl` to create a reference to the lending
    table in the R session. To pass the fully qualified name, we can use
    `glue` and `I()`.

    ``` r
    library(dbplyr)

    tbl_lending <- tbl(con, I(glue("{catalog}.`{schema}`.{table}")))

    tbl_lending
    ```

        # Source:   table<sol_eng_demo_nickp.`end-to-end`.loans_full_schema> [?? x 56]
        # Database: Spark SQL 3.1.1[token@Spark SQL/hive_metastore]
           emp_title        emp_length state homeownership annual_income verified_income
           <chr>            <chr>      <chr> <chr>                 <dbl> <chr>          
         1 "global config … 3          NJ    MORTGAGE              90000 Verified       
         2 "warehouse offi… 10         HI    RENT                  40000 Not Verified   
         3 "assembly"       3          WI    RENT                  40000 Source Verified
         4 "customer servi… 1          PA    RENT                  30000 Not Verified   
         5 "security super… 10         CA    RENT                  35000 Verified       
         6  <NA>            NA         KY    OWN                   34000 Not Verified   
         7 "hr "            10         MI    MORTGAGE              35000 Source Verified
         8 "police"         10         AZ    MORTGAGE             110000 Source Verified
         9 "parts"          10         NV    MORTGAGE              65000 Source Verified
        10 "4th person"     3          IL    RENT                  30000 Not Verified   
        # ℹ more rows
        # ℹ 50 more variables: debt_to_income <chr>, annual_income_joint <chr>,
        #   verification_income_joint <chr>, debt_to_income_joint <chr>,
        #   delinq_2y <int64>, months_since_last_delinq <chr>,
        #   earliest_credit_line <int64>, inquiries_last_12m <int64>,
        #   total_credit_lines <int64>, open_credit_lines <int64>,
        #   total_credit_limit <int64>, total_credit_utilized <int64>, …

3.  In order to make the predictions part of a larger set of fields
    returned by the final query, the `orbital_inline()` function is
    used. This allows for it to be passed inside a `dplyr` `mutate()`
    call. `orbital_inline()` will modify the predictor fields based on
    the steps from the recipe, which in the example’s case, is the
    normalization step. A quick way to retain the original values, if
    they are to be part of the final result, is to simply create copies
    of them via `mutate()`. Finally, since it is not necessary to return
    all of the fields, we reduce them via a `select()` call.

    ``` r
    tbl_prep <- tbl_lending |> 
      mutate(o_annual_income = annual_income, 
             o_total_credit_lines = total_credit_lines,
             o_loan_amount = loan_amount, 
             o_term = term
             ) |> 
      mutate(!!! orbital_inline(lending_orbital)) |> 
      select(
        pred, interest_rate, emp_title, balance, application_type,
        o_annual_income, o_total_credit_lines, o_loan_amount, o_term
      )
    ```

4.  Preview the top rows from the initial transformations.

    ``` r
    tbl_prep |> 
      head()
    ```

        # Source:   SQL [?? x 9]
        # Database: Spark SQL 3.1.1[token@Spark SQL/hive_metastore]
           pred interest_rate emp_title         balance application_type o_annual_income
          <dbl>         <dbl> <chr>               <dbl> <chr>                      <dbl>
        1  13.5         14.1  "global config e…  27016. individual                 90000
        2  11.8         12.6  "warehouse offic…   4651. individual                 40000
        3  12.0         17.1  "assembly"          1825. individual                 40000
        4  10.9          6.72 "customer servic…  18853. individual                 30000
        5  10.3         14.1  "security superv…  21430. joint                      35000
        6  11.8          6.72  <NA>               4257. individual                 34000
        # ℹ 3 more variables: o_total_credit_lines <int64>, o_loan_amount <int64>,
        #   o_term <int64>

5.  An additional step is added to only keep the rows that have an
    current interest rate is 15 points higher than the prediction.

    ``` r
    tbl_final <- tbl_prep |> 
      filter(interest_rate - pred > 15, pred > 0)
    ```

6.  Preview the results

    ``` r
    tbl_final
    ```

        # Source:   SQL [?? x 9]
        # Database: Spark SQL 3.1.1[token@Spark SQL/hive_metastore]
            pred interest_rate emp_title        balance application_type o_annual_income
           <dbl>         <dbl> <chr>              <dbl> <chr>                      <dbl>
         1  10.5          26.8 operational ris…      0  individual                210000
         2  14.0          30.8 sr admin assist…  19822. individual                 95731
         3  14.3          30.8 firefighter       24254. individual                 50000
         4  15.0          30.2 vice president …   9775. individual                118000
         5  10.6          30.8 mechanical desi…  15896. individual                 71500
         6  10.8          26.3 president of me…  34120. individual                320000
         7  12.5          28.7 pilot             29298. individual                190000
         8  13.9          30.8 teacher           24254. individual                 80000
         9  14.0          30.8 <NA>              19244. individual                 85000
        10  13.1          30.6 account manager   24251. individual                150000
        # ℹ more rows
        # ℹ 3 more variables: o_total_credit_lines <int64>, o_loan_amount <int64>,
        #   o_term <int64>

7.  Preview the actual SQL that will be sent using `show_query()`.

    ``` r
    tbl_final |> 
      show_query()
    ```

        <SQL>
        SELECT `q01`.*
        FROM (
          SELECT
            (((12.1961333333333 + (`annual_income` * -0.379128214967168)) + (`total_credit_lines` * -0.242483849568646)) + (`loan_amount` * -0.921560182698075)) + (`term` * 2.05467819018834) AS `pred`,
            `interest_rate`,
            `emp_title`,
            `balance`,
            `application_type`,
            `o_annual_income`,
            `o_total_credit_lines`,
            `o_loan_amount`,
            `o_term`
          FROM (
            SELECT
              `emp_title`,
              `emp_length`,
              `state`,
              `homeownership`,
              (`annual_income` - 71942.7866666667) / 42292.8687411871 AS `annual_income`,
              `verified_income`,
              `debt_to_income`,
              `annual_income_joint`,
              `verification_income_joint`,
              `debt_to_income_joint`,
              `delinq_2y`,
              `months_since_last_delinq`,
              `earliest_credit_line`,
              `inquiries_last_12m`,
              (`total_credit_lines` - 22.4933333333333) / 11.6681286085312 AS `total_credit_lines`,
              `open_credit_lines`,
              `total_credit_limit`,
              `total_credit_utilized`,
              `num_collections_last_12m`,
              `num_historical_failed_to_pay`,
              `months_since_90d_late`,
              `current_accounts_delinq`,
              `total_collection_amount_ever`,
              `current_installment_accounts`,
              `accounts_opened_24m`,
              `months_since_last_credit_inquiry`,
              `num_satisfactory_accounts`,
              `num_accounts_120d_past_due`,
              `num_accounts_30d_past_due`,
              `num_active_debit_accounts`,
              `total_debit_limit`,
              `num_total_cc_accounts`,
              `num_open_cc_accounts`,
              `num_cc_carrying_balance`,
              `num_mort_accounts`,
              `account_never_delinq_percent`,
              `tax_liens`,
              `public_record_bankrupt`,
              `loan_purpose`,
              `application_type`,
              (`loan_amount` - 14928.3333333333) / 9958.62753532771 AS `loan_amount`,
              (`term` - 44.32) / 11.4987190825996 AS `term`,
              `interest_rate`,
              `installment`,
              `grade`,
              `sub_grade`,
              `issue_month`,
              `loan_status`,
              `initial_listing_status`,
              `disbursement_method`,
              `balance`,
              `paid_total`,
              `paid_principal`,
              `paid_interest`,
              `paid_late_fees`,
              `loan_id`,
              `o_annual_income`,
              `o_total_credit_lines`,
              `o_loan_amount`,
              `o_term`
            FROM (
              SELECT
                `loans_full_schema`.*,
                `annual_income` AS `o_annual_income`,
                `total_credit_lines` AS `o_total_credit_lines`,
                `loan_amount` AS `o_loan_amount`,
                `term` AS `o_term`
              FROM sol_eng_demo_nickp.`end-to-end`.loans_full_schema
            ) `q01`
          ) `q01`
        ) `q01`
        WHERE ((`interest_rate` - `pred`) > 15.0) AND (`pred` > 0.0)

8.  `show_query()` is mostly geared towards having a nice output to the
    R console. To capture the SQL in a variable, use `remote_query()`.

    ``` r
    final_sql <- remote_query(tbl_final)
    ```

9.  As a way to confirm that the SQL will run as returned by
    `remote_query`, use `dbQuery()` to run the statement against the
    database.

    ``` r
    res <- dbGetQuery(con, final_sql)
    head(res)
    ```

              pred interest_rate                    emp_title  balance application_type
        1 10.48399         26.77     operational risk manager     0.00       individual
        2 13.95838         30.79           sr admin assistant 19821.53       individual
        3 14.25211         30.79                  firefighter 24253.68       individual
        4 15.00983         30.17 vice president of operations  9774.95       individual
        5 10.58753         30.75          mechanical designer 15896.16       individual
        6 10.78165         26.30  president of media division 34119.79       individual
          o_annual_income o_total_credit_lines o_loan_amount o_term
        1          210000                   18          5000     36
        2           95731                   37         20600     60
        3           50000                   23         25000     60
        4          118000                   24         10000     60
        5           71500                   23         16175     36
        6          320000                   29         35000     60

## Automate in Databricks

1.  The easiest to create the new task is via the Databricks Python SDK,
    and the easiest way to access Python components in R is via
    `reticulate`. Using `py_require()` allow for `reticulate`, via
    [`uv`](https://docs.astral.sh/uv/), to install Python (if needed)
    and the needed `databricks.sdk` library.

    ``` r
    library(reticulate)
    py_require("databricks.sdk")
    ```

2.  `WorkspaceClient` is the main way to create and manage objects

    ``` r
    db_sdk <- import("databricks.sdk")
    w <- db_sdk$WorkspaceClient()
    ```

3.  The SQL tasks require a warehouse ID. This code pull the ID from the
    first warehouse returned by the function that lists all of the
    sources.

    ``` r
    srcs <- w$data_sources$list()
    warehouse_id <- srcs[[1]]$warehouse_id
    ```

4.  To start, a new
    [Query](https://docs.databricks.com/aws/en/sql/user/queries/) is
    created in the Databricks Workspace. To start, the query object is
    built using `CreateQueryRequestQuery()`. This is where the
    `final_sql` value is passed. Additionally, the catalog and schema
    are also defined via their respective arguments.

    ``` r
    db_request_query <- db_sdk$service$sql$CreateQueryRequestQuery(
      query_text = final_sql,
      catalog = catalog,
      schema = schema,
      display_name = "Interest rate differences",
      warehouse_id = warehouse_id,
      description = "Find differences in interest rate"
    )
    ```

5.  `w$queries$create()` takes the request query object to create the
    new query. After executing the command, a new query named *“Interest
    rate differences”* will appear in the Queries section of the
    Databricks Web UI.

    ``` r
    new_query <- w$queries$create(query = db_request_query)
    ```

6.  A Databricks Job can be used to orchestrate multiple tasks. The job
    being created for this example requires a single task. Tasks could
    be a variety of kinds such as a Notebook, Python script, SQL Queries
    and many others. The following starts building the SQL task. It uses
    the `new_query`’s ID to tie it to the query created in the previous
    step.

    ``` r
    sdk_jobs <- db_sdk$service$jobs

    db_sql_task_query <- sdk_jobs$SqlTaskQuery(
        query_id = new_query$id
        )
    ```

7.  To finish defining the SQL task object, `db_sql_task_query` is
    passed to SqlTask()

    ``` r
    db_sql_task <- sdk_jobs$SqlTask(
        query = db_sql_task_query, 
        warehouse_id = warehouse_id
        )
    ```

8.  The SQL task object is used to create a formal Task. This is the
    point where the resulting task in the Databricks UI can be named and
    described

    ``` r
    db_task <- sdk_jobs$Task(
        sql_task = db_sql_task,
        description = "Int rate diffs", 
        task_key = "run_sql"
        )
    ```

9.  For this example, the Job needs to have a schedule defined. And to
    do this, a `CronSchedule` object is needed. To define the schedule
    use a [CRON
    expression](https://www.quartz-scheduler.org/documentation/).

    ``` r
    db_schedule = sdk_jobs$CronSchedule(
        quartz_cron_expression = "0 0 12 * * ?",
        timezone_id = "CST"
        )
    ```

10. Finally, the Job is created using the task and schedule objects.
    After running the following command, a new Job named *“Daily check
    interest differences”* will appear in the Jobs section of the
    Databricks Web UI.

    ``` r
    new_job <- w$jobs$create(
        name = "Daily check interest differences",
        tasks = list(db_task),    
        schedule = db_schedule
        )
    ```

## Appendix

### Data in example

The data used for this example was downloaded from OpenIntro. The page
containing the description of the data and the download link are
available here:
[loans_full_schema](https://www.openintro.org/data/index.php?data=loans_full_schema).
The CSV file was manually [uploaded to the Databricks Unity
Catalog](https://docs.databricks.com/aws/en/ingestion/file-upload/upload-to-volume).

The `loan_id` field is not included in the data file. That was created
using the following two SQL commands. This one to create the field:

``` sql
ALTER TABLE sol_eng_demo_nickp.`end-to-end`.loans_full_schema 
ADD COLUMN loan_id BIGINT;
```

This is the SQL command to populate the table with a sequential number:

``` sql
WITH cte AS (
  SELECT
    loan_id,
    ROW_NUMBER() OVER (ORDER BY debt_to_income) AS new_loan_id
  FROM
    sol_eng_demo_nickp.`end-to-end`.loans_full_schema
)
MERGE INTO sol_eng_demo_nickp.`end-to-end`.loans_full_schema AS target
USING cte
ON target.debt_to_income = cte.debt_to_income
WHEN MATCHED THEN
  UPDATE SET target.loan_id = cte.new_loan_id;
```
