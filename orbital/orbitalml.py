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
con_cursor.execute("select * from loans_full_schema TABLESAMPLE (10 ROWS) REPEATABLE (999);")
col_names = [desc[0] for desc in con_cursor.description]
res = con_cursor.fetchall()
df = pd.DataFrame(res, columns=col_names)
df

