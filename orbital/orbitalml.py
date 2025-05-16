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
df = pd.DataFrame(res, columns=col_names)
df

# Modeling

from sklearn.model_selection import train_test_split

outcome = df["interest_rate"]
predictors = df.drop("interest_rate", axis=1)

pred_train, pred_test, out_train, out_test = train_test_split(
    predictors, outcome, test_size=20, random_state=999
)

from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LinearRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

col_names.remove("interest_rate")

pipeline = Pipeline(
    [
        ("preprocess", ColumnTransformer([("scaler", StandardScaler(with_std=False), col_names)],
                                        remainder="passthrough")),
        ("linear_regression", LinearRegression()),
    ]
)
pipeline.fit(pred_train, out_train)

