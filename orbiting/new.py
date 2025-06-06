#pip install databricks-sql-connector

import os
from dotenv import load_dotenv
from databricks import sql
import pandas as pd
load_dotenv()

host = os.getenv("DATABRICKS_HOST")
token = os.getenv("DATABRICKS_TOKEN")
schema = "end-to-end"
catalog = "sol_eng_demo_nickp"
http_path = "/sql/1.0/warehouses/b71952ebceb705ce"

con = sql.connect(host, http_path, token, catalog = catalog, schema = schema)
con_cursor = con.cursor()
con_cursor.execute("select * from loans_full_schema TABLESAMPLE (100 ROWS) REPEATABLE (999);")
col_names = [desc[0] for desc in con_cursor.description]
res = con_cursor.fetchall()
full_df = pd.DataFrame(res, columns=col_names)

# Modeling

from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LinearRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split

use_col_names = ["interest_rate", "annual_income", "total_credit_lines", "loan_amount", "term"]
df = full_df[use_col_names]

outcome = df["interest_rate"]
predictors = df.drop("interest_rate", axis=1)

pred_train, pred_test, out_train, out_test = train_test_split(
    predictors, outcome, test_size=20, random_state=999
)
use_col_names.remove("interest_rate")

pipeline = Pipeline(
    [
        ("preprocess", ColumnTransformer([("scaler", StandardScaler(with_std=False), use_col_names)],
                                        remainder="passthrough")),
        ("linear_regression", LinearRegression()),
    ]
)

pipeline.fit(pred_train, out_train)

import orbitalml
import orbitalml.types

orbital_pipeline = orbitalml.parse_pipeline(pipeline, features={
    "annual_income": orbitalml.types.DoubleColumnType(),
    "total_credit_lines": orbitalml.types.DoubleColumnType(),
    "loan_amount": orbitalml.types.DoubleColumnType(),    
    "term": orbitalml.types.DoubleColumnType(),
    "loan_id": orbitalml.types.Int32ColumnType(),
    "emp_title": orbitalml.types.StringColumnType(),
    "loan_amount": orbitalml.types.DoubleColumnType(),
    "balance": orbitalml.types.DoubleColumnType(),
    "application_type": orbitalml.types.StringColumnType(),
    "interest_rate": orbitalml.types.DoubleColumnType()
})

print(orbital_pipeline)

pred_sql = orbitalml.export_sql(
    table_name="loans_full_schema", 
    pipeline=orbital_pipeline, 
    projection= orbitalml.ResultsProjection(["loan_amount", "term"]),
    dialect="databricks"
    )


con_cursor = con.cursor()
con_cursor.execute(f"select * from ({pred_sql}) where interest_rate - variable > 15 and variable > 0")
col_names = [desc[0] for desc in con_cursor.description]
res = con_cursor.fetchall()
df = pd.DataFrame(res, columns=col_names)
df


schema = "end-to-end"
catalog = "sol_eng_demo_nickp"


from databricks.sdk import WorkspaceClient
w = WorkspaceClient()

srcs = w.data_sources.list()
warehouse_id = srcs[0].warehouse_id

from databricks.sdk.service import sql as sdk_sql

db_request_query = sdk_sql.CreateQueryRequestQuery(
        query_text="SELECT * from loans_full_schema limit 10",
        catalog=catalog, 
        schema=schema,
        display_name=f"Interest rate differences",
        warehouse_id=warehouse_id,
        description="Find differences in interest rate",        
    )

new_query = w.queries.create(query=db_request_query)

from databricks.sdk.service import jobs  as sdk_jobs

db_sql_task_query = sdk_jobs.SqlTaskQuery(
    query_id = new_query.id
    )

db_sql_task = sdk_jobs.SqlTask(
    query=db_sql_task_query, 
    warehouse_id=warehouse_id
    )

db_task = sdk_jobs.Task(
    sql_task=db_sql_task,
    description="Int rate diffs", 
    task_key="run_sql"
    )

# https://www.quartz-scheduler.org/documentation/quartz-2.3.0/tutorials/crontrigger.html

db_schedule = sdk_jobs.CronSchedule(
    quartz_cron_expression="0 0 12 * * ?",
    timezone_id="CST"
    )

new_job = w.jobs.create(
    name="Daily check interest differences",
    tasks=[db_task],    
    schedule=db_schedule
    )
