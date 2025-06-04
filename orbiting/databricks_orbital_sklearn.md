# Databricks + Scikit Learn + Orbital
Edgar Ruiz - Posit
2025-05-20

- [Use case](#use-case)
- [Approach](#approach)
- [Download sample](#download-sample)
- [Fit locally](#fit-locally)
- [Convert to SQL using Orbital](#convert-to-sql-using-orbital)
- [Automate in Databricks](#automate-in-databricks)
- [Appendix](#appendix)
  - [Data in example](#data-in-example)
  - [Python environment](#python-environment)
  - [Full code](#full-code)

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
of the table into our Python session, fit a model using a Scikit Learn
pipeline, and then use Orbital to translate the steps and estimates into
a SQL statement. Finally, we will use that SQL statement as the base to
compare the current interest against the prediction, and download the
loans that had a large difference. Thanks to the integrated environment
in Databricks, the resulting SQL statement will be saved in the
Databricks Workspace, and used to run on a schedule via a [Databricks
Job](https://docs.databricks.com/aws/en/jobs/).

<div id="fig-diagram">

``` mermaid
flowchart LR
  A[1-Full Table] --Download--> B(2-Sample) 
  B--Scikit Learn fit-->C(3-Model)
  C--Orbital parse-->D(4-SQL)
  D--Automate-->E(5-Job)
  E--Predict-->A
```

Figure 1: Diagram of the approach used for this use case

</div>

## Download sample

1.  Load necessary libraries. Make sure to have
    `databricks-sql-connector` installed in your environment, that is
    the source of `databricks`.

    ``` python
    from dotenv import load_dotenv
    from databricks import sql
    import pandas as pd
    import os
    ```

2.  Load the credentials to be used via their respective environment
    variables.

    ``` python
    load_dotenv()
    host = os.getenv("DATABRICKS_HOST")
    token = os.getenv("DATABRICKS_TOKEN")
    ```

3.  For simplicity’s sake, the table’s catalog, schema and HTTP path
    into variables.

    ``` python
    schema = "end-to-end"
    catalog = "sol_eng_demo_nickp"
    http_path = "/sql/1.0/warehouses/b71952ebceb705ce"
    ```

4.  Establish the database connection using the defined variables

    ``` python
    con = sql.connect(host, http_path, token, catalog = catalog, schema = schema)
    ```

5.  Using `TABLESAMPLE`, download 100 rows. `REPEATABLE` is used for
    purposes of reproducibility.

    ``` python
    con_cursor = con.cursor()
    con_cursor.execute(
      "select * from loans_full_schema TABLESAMPLE (100 ROWS) REPEATABLE (999);"
      )
    ```

        <databricks.sql.client.Cursor at 0x116666ae0>

6.  Iterate through the field descriptions to extract their respective
    names

    ``` python
    col_names = [desc[0] for desc in con_cursor.description]
    ```

7.  Convert the downloaded data into Pandas

    ``` python
    res = con_cursor.fetchall()
    full_df = pd.DataFrame(res, columns=col_names)
    ```

## Fit locally

1.  Load the appropriate Scikit Learn modules

    ``` python
    from sklearn.model_selection import train_test_split
    from sklearn.linear_model import LinearRegression
    from sklearn.preprocessing import StandardScaler
    from sklearn.compose import ColumnTransformer
    from sklearn.pipeline import Pipeline
    ```

2.  Select the fields that will be used for predictors, and add them to
    a list called `pred_names`.

    ``` python
    pred_names = ["annual_income", "total_credit_lines", "loan_amount",  "term"]
    ```

3.  Subset the data into a new variable (`predictors`)

    ``` python
    predictors = full_df[pred_names]
    ```

4.  Pull the interest rate field from the data into a new variable
    (`outcome`)

    ``` python
    outcome = full_df["interest_rate"]
    ```

5.  Split the rows into train and test

    ``` python
    pred_train, pred_test, out_train, out_test = train_test_split(
        predictors, outcome, test_size=20, random_state=999
    )
    ```

6.  Create the pipeline. Use `pre_names` to define the fields to run the
    scaler against

    ``` python
    pipeline = Pipeline(
        [("preprocess", 
          ColumnTransformer(
            [("scaler", StandardScaler(with_std=False), pred_names)],
            remainder="passthrough")
            ),
        ("linear_regression", LinearRegression())]
    )
    ```

7.  Fit the pipeline

    ``` python
    pipeline.fit(pred_train, out_train)
    ```

    <style>#sk-container-id-1 {
      /* Definition of color scheme common for light and dark mode */
      --sklearn-color-text: #000;
      --sklearn-color-text-muted: #666;
      --sklearn-color-line: gray;
      /* Definition of color scheme for unfitted estimators */
      --sklearn-color-unfitted-level-0: #fff5e6;
      --sklearn-color-unfitted-level-1: #f6e4d2;
      --sklearn-color-unfitted-level-2: #ffe0b3;
      --sklearn-color-unfitted-level-3: chocolate;
      /* Definition of color scheme for fitted estimators */
      --sklearn-color-fitted-level-0: #f0f8ff;
      --sklearn-color-fitted-level-1: #d4ebff;
      --sklearn-color-fitted-level-2: #b3dbfd;
      --sklearn-color-fitted-level-3: cornflowerblue;
    &#10;  /* Specific color for light theme */
      --sklearn-color-text-on-default-background: var(--sg-text-color, var(--theme-code-foreground, var(--jp-content-font-color1, black)));
      --sklearn-color-background: var(--sg-background-color, var(--theme-background, var(--jp-layout-color0, white)));
      --sklearn-color-border-box: var(--sg-text-color, var(--theme-code-foreground, var(--jp-content-font-color1, black)));
      --sklearn-color-icon: #696969;
    &#10;  @media (prefers-color-scheme: dark) {
        /* Redefinition of color scheme for dark theme */
        --sklearn-color-text-on-default-background: var(--sg-text-color, var(--theme-code-foreground, var(--jp-content-font-color1, white)));
        --sklearn-color-background: var(--sg-background-color, var(--theme-background, var(--jp-layout-color0, #111)));
        --sklearn-color-border-box: var(--sg-text-color, var(--theme-code-foreground, var(--jp-content-font-color1, white)));
        --sklearn-color-icon: #878787;
      }
    }
    &#10;#sk-container-id-1 {
      color: var(--sklearn-color-text);
    }
    &#10;#sk-container-id-1 pre {
      padding: 0;
    }
    &#10;#sk-container-id-1 input.sk-hidden--visually {
      border: 0;
      clip: rect(1px 1px 1px 1px);
      clip: rect(1px, 1px, 1px, 1px);
      height: 1px;
      margin: -1px;
      overflow: hidden;
      padding: 0;
      position: absolute;
      width: 1px;
    }
    &#10;#sk-container-id-1 div.sk-dashed-wrapped {
      border: 1px dashed var(--sklearn-color-line);
      margin: 0 0.4em 0.5em 0.4em;
      box-sizing: border-box;
      padding-bottom: 0.4em;
      background-color: var(--sklearn-color-background);
    }
    &#10;#sk-container-id-1 div.sk-container {
      /* jupyter's `normalize.less` sets `[hidden] { display: none; }`
         but bootstrap.min.css set `[hidden] { display: none !important; }`
         so we also need the `!important` here to be able to override the
         default hidden behavior on the sphinx rendered scikit-learn.org.
         See: https://github.com/scikit-learn/scikit-learn/issues/21755 */
      display: inline-block !important;
      position: relative;
    }
    &#10;#sk-container-id-1 div.sk-text-repr-fallback {
      display: none;
    }
    &#10;div.sk-parallel-item,
    div.sk-serial,
    div.sk-item {
      /* draw centered vertical line to link estimators */
      background-image: linear-gradient(var(--sklearn-color-text-on-default-background), var(--sklearn-color-text-on-default-background));
      background-size: 2px 100%;
      background-repeat: no-repeat;
      background-position: center center;
    }
    &#10;/* Parallel-specific style estimator block */
    &#10;#sk-container-id-1 div.sk-parallel-item::after {
      content: "";
      width: 100%;
      border-bottom: 2px solid var(--sklearn-color-text-on-default-background);
      flex-grow: 1;
    }
    &#10;#sk-container-id-1 div.sk-parallel {
      display: flex;
      align-items: stretch;
      justify-content: center;
      background-color: var(--sklearn-color-background);
      position: relative;
    }
    &#10;#sk-container-id-1 div.sk-parallel-item {
      display: flex;
      flex-direction: column;
    }
    &#10;#sk-container-id-1 div.sk-parallel-item:first-child::after {
      align-self: flex-end;
      width: 50%;
    }
    &#10;#sk-container-id-1 div.sk-parallel-item:last-child::after {
      align-self: flex-start;
      width: 50%;
    }
    &#10;#sk-container-id-1 div.sk-parallel-item:only-child::after {
      width: 0;
    }
    &#10;/* Serial-specific style estimator block */
    &#10;#sk-container-id-1 div.sk-serial {
      display: flex;
      flex-direction: column;
      align-items: center;
      background-color: var(--sklearn-color-background);
      padding-right: 1em;
      padding-left: 1em;
    }
    &#10;
    /* Toggleable style: style used for estimator/Pipeline/ColumnTransformer box that is
    clickable and can be expanded/collapsed.
    - Pipeline and ColumnTransformer use this feature and define the default style
    - Estimators will overwrite some part of the style using the `sk-estimator` class
    */
    &#10;/* Pipeline and ColumnTransformer style (default) */
    &#10;#sk-container-id-1 div.sk-toggleable {
      /* Default theme specific background. It is overwritten whether we have a
      specific estimator or a Pipeline/ColumnTransformer */
      background-color: var(--sklearn-color-background);
    }
    &#10;/* Toggleable label */
    #sk-container-id-1 label.sk-toggleable__label {
      cursor: pointer;
      display: flex;
      width: 100%;
      margin-bottom: 0;
      padding: 0.5em;
      box-sizing: border-box;
      text-align: center;
      align-items: start;
      justify-content: space-between;
      gap: 0.5em;
    }
    &#10;#sk-container-id-1 label.sk-toggleable__label .caption {
      font-size: 0.6rem;
      font-weight: lighter;
      color: var(--sklearn-color-text-muted);
    }
    &#10;#sk-container-id-1 label.sk-toggleable__label-arrow:before {
      /* Arrow on the left of the label */
      content: "▸";
      float: left;
      margin-right: 0.25em;
      color: var(--sklearn-color-icon);
    }
    &#10;#sk-container-id-1 label.sk-toggleable__label-arrow:hover:before {
      color: var(--sklearn-color-text);
    }
    &#10;/* Toggleable content - dropdown */
    &#10;#sk-container-id-1 div.sk-toggleable__content {
      max-height: 0;
      max-width: 0;
      overflow: hidden;
      text-align: left;
      /* unfitted */
      background-color: var(--sklearn-color-unfitted-level-0);
    }
    &#10;#sk-container-id-1 div.sk-toggleable__content.fitted {
      /* fitted */
      background-color: var(--sklearn-color-fitted-level-0);
    }
    &#10;#sk-container-id-1 div.sk-toggleable__content pre {
      margin: 0.2em;
      border-radius: 0.25em;
      color: var(--sklearn-color-text);
      /* unfitted */
      background-color: var(--sklearn-color-unfitted-level-0);
    }
    &#10;#sk-container-id-1 div.sk-toggleable__content.fitted pre {
      /* unfitted */
      background-color: var(--sklearn-color-fitted-level-0);
    }
    &#10;#sk-container-id-1 input.sk-toggleable__control:checked~div.sk-toggleable__content {
      /* Expand drop-down */
      max-height: 200px;
      max-width: 100%;
      overflow: auto;
    }
    &#10;#sk-container-id-1 input.sk-toggleable__control:checked~label.sk-toggleable__label-arrow:before {
      content: "▾";
    }
    &#10;/* Pipeline/ColumnTransformer-specific style */
    &#10;#sk-container-id-1 div.sk-label input.sk-toggleable__control:checked~label.sk-toggleable__label {
      color: var(--sklearn-color-text);
      background-color: var(--sklearn-color-unfitted-level-2);
    }
    &#10;#sk-container-id-1 div.sk-label.fitted input.sk-toggleable__control:checked~label.sk-toggleable__label {
      background-color: var(--sklearn-color-fitted-level-2);
    }
    &#10;/* Estimator-specific style */
    &#10;/* Colorize estimator box */
    #sk-container-id-1 div.sk-estimator input.sk-toggleable__control:checked~label.sk-toggleable__label {
      /* unfitted */
      background-color: var(--sklearn-color-unfitted-level-2);
    }
    &#10;#sk-container-id-1 div.sk-estimator.fitted input.sk-toggleable__control:checked~label.sk-toggleable__label {
      /* fitted */
      background-color: var(--sklearn-color-fitted-level-2);
    }
    &#10;#sk-container-id-1 div.sk-label label.sk-toggleable__label,
    #sk-container-id-1 div.sk-label label {
      /* The background is the default theme color */
      color: var(--sklearn-color-text-on-default-background);
    }
    &#10;/* On hover, darken the color of the background */
    #sk-container-id-1 div.sk-label:hover label.sk-toggleable__label {
      color: var(--sklearn-color-text);
      background-color: var(--sklearn-color-unfitted-level-2);
    }
    &#10;/* Label box, darken color on hover, fitted */
    #sk-container-id-1 div.sk-label.fitted:hover label.sk-toggleable__label.fitted {
      color: var(--sklearn-color-text);
      background-color: var(--sklearn-color-fitted-level-2);
    }
    &#10;/* Estimator label */
    &#10;#sk-container-id-1 div.sk-label label {
      font-family: monospace;
      font-weight: bold;
      display: inline-block;
      line-height: 1.2em;
    }
    &#10;#sk-container-id-1 div.sk-label-container {
      text-align: center;
    }
    &#10;/* Estimator-specific */
    #sk-container-id-1 div.sk-estimator {
      font-family: monospace;
      border: 1px dotted var(--sklearn-color-border-box);
      border-radius: 0.25em;
      box-sizing: border-box;
      margin-bottom: 0.5em;
      /* unfitted */
      background-color: var(--sklearn-color-unfitted-level-0);
    }
    &#10;#sk-container-id-1 div.sk-estimator.fitted {
      /* fitted */
      background-color: var(--sklearn-color-fitted-level-0);
    }
    &#10;/* on hover */
    #sk-container-id-1 div.sk-estimator:hover {
      /* unfitted */
      background-color: var(--sklearn-color-unfitted-level-2);
    }
    &#10;#sk-container-id-1 div.sk-estimator.fitted:hover {
      /* fitted */
      background-color: var(--sklearn-color-fitted-level-2);
    }
    &#10;/* Specification for estimator info (e.g. "i" and "?") */
    &#10;/* Common style for "i" and "?" */
    &#10;.sk-estimator-doc-link,
    a:link.sk-estimator-doc-link,
    a:visited.sk-estimator-doc-link {
      float: right;
      font-size: smaller;
      line-height: 1em;
      font-family: monospace;
      background-color: var(--sklearn-color-background);
      border-radius: 1em;
      height: 1em;
      width: 1em;
      text-decoration: none !important;
      margin-left: 0.5em;
      text-align: center;
      /* unfitted */
      border: var(--sklearn-color-unfitted-level-1) 1pt solid;
      color: var(--sklearn-color-unfitted-level-1);
    }
    &#10;.sk-estimator-doc-link.fitted,
    a:link.sk-estimator-doc-link.fitted,
    a:visited.sk-estimator-doc-link.fitted {
      /* fitted */
      border: var(--sklearn-color-fitted-level-1) 1pt solid;
      color: var(--sklearn-color-fitted-level-1);
    }
    &#10;/* On hover */
    div.sk-estimator:hover .sk-estimator-doc-link:hover,
    .sk-estimator-doc-link:hover,
    div.sk-label-container:hover .sk-estimator-doc-link:hover,
    .sk-estimator-doc-link:hover {
      /* unfitted */
      background-color: var(--sklearn-color-unfitted-level-3);
      color: var(--sklearn-color-background);
      text-decoration: none;
    }
    &#10;div.sk-estimator.fitted:hover .sk-estimator-doc-link.fitted:hover,
    .sk-estimator-doc-link.fitted:hover,
    div.sk-label-container:hover .sk-estimator-doc-link.fitted:hover,
    .sk-estimator-doc-link.fitted:hover {
      /* fitted */
      background-color: var(--sklearn-color-fitted-level-3);
      color: var(--sklearn-color-background);
      text-decoration: none;
    }
    &#10;/* Span, style for the box shown on hovering the info icon */
    .sk-estimator-doc-link span {
      display: none;
      z-index: 9999;
      position: relative;
      font-weight: normal;
      right: .2ex;
      padding: .5ex;
      margin: .5ex;
      width: min-content;
      min-width: 20ex;
      max-width: 50ex;
      color: var(--sklearn-color-text);
      box-shadow: 2pt 2pt 4pt #999;
      /* unfitted */
      background: var(--sklearn-color-unfitted-level-0);
      border: .5pt solid var(--sklearn-color-unfitted-level-3);
    }
    &#10;.sk-estimator-doc-link.fitted span {
      /* fitted */
      background: var(--sklearn-color-fitted-level-0);
      border: var(--sklearn-color-fitted-level-3);
    }
    &#10;.sk-estimator-doc-link:hover span {
      display: block;
    }
    &#10;/* "?"-specific style due to the `<a>` HTML tag */
    &#10;#sk-container-id-1 a.estimator_doc_link {
      float: right;
      font-size: 1rem;
      line-height: 1em;
      font-family: monospace;
      background-color: var(--sklearn-color-background);
      border-radius: 1rem;
      height: 1rem;
      width: 1rem;
      text-decoration: none;
      /* unfitted */
      color: var(--sklearn-color-unfitted-level-1);
      border: var(--sklearn-color-unfitted-level-1) 1pt solid;
    }
    &#10;#sk-container-id-1 a.estimator_doc_link.fitted {
      /* fitted */
      border: var(--sklearn-color-fitted-level-1) 1pt solid;
      color: var(--sklearn-color-fitted-level-1);
    }
    &#10;/* On hover */
    #sk-container-id-1 a.estimator_doc_link:hover {
      /* unfitted */
      background-color: var(--sklearn-color-unfitted-level-3);
      color: var(--sklearn-color-background);
      text-decoration: none;
    }
    &#10;#sk-container-id-1 a.estimator_doc_link.fitted:hover {
      /* fitted */
      background-color: var(--sklearn-color-fitted-level-3);
    }
    </style><div id="sk-container-id-1" class="sk-top-container"><div class="sk-text-repr-fallback"><pre>Pipeline(steps=[(&#x27;preprocess&#x27;,
                     ColumnTransformer(remainder=&#x27;passthrough&#x27;,
                                       transformers=[(&#x27;scaler&#x27;,
                                                      StandardScaler(with_std=False),
                                                      [&#x27;annual_income&#x27;,
                                                       &#x27;total_credit_lines&#x27;,
                                                       &#x27;loan_amount&#x27;, &#x27;term&#x27;])])),
                    (&#x27;linear_regression&#x27;, LinearRegression())])</pre><b>In a Jupyter environment, please rerun this cell to show the HTML representation or trust the notebook. <br />On GitHub, the HTML representation is unable to render, please try loading this page with nbviewer.org.</b></div><div class="sk-container" hidden><div class="sk-item sk-dashed-wrapped"><div class="sk-label-container"><div class="sk-label fitted sk-toggleable"><input class="sk-toggleable__control sk-hidden--visually" id="sk-estimator-id-1" type="checkbox" ><label for="sk-estimator-id-1" class="sk-toggleable__label fitted sk-toggleable__label-arrow"><div><div>Pipeline</div></div><div><a class="sk-estimator-doc-link fitted" rel="noreferrer" target="_blank" href="https://scikit-learn.org/1.6/modules/generated/sklearn.pipeline.Pipeline.html">?<span>Documentation for Pipeline</span></a><span class="sk-estimator-doc-link fitted">i<span>Fitted</span></span></div></label><div class="sk-toggleable__content fitted"><pre>Pipeline(steps=[(&#x27;preprocess&#x27;,
                     ColumnTransformer(remainder=&#x27;passthrough&#x27;,
                                       transformers=[(&#x27;scaler&#x27;,
                                                      StandardScaler(with_std=False),
                                                      [&#x27;annual_income&#x27;,
                                                       &#x27;total_credit_lines&#x27;,
                                                       &#x27;loan_amount&#x27;, &#x27;term&#x27;])])),
                    (&#x27;linear_regression&#x27;, LinearRegression())])</pre></div> </div></div><div class="sk-serial"><div class="sk-item sk-dashed-wrapped"><div class="sk-label-container"><div class="sk-label fitted sk-toggleable"><input class="sk-toggleable__control sk-hidden--visually" id="sk-estimator-id-2" type="checkbox" ><label for="sk-estimator-id-2" class="sk-toggleable__label fitted sk-toggleable__label-arrow"><div><div>preprocess: ColumnTransformer</div></div><div><a class="sk-estimator-doc-link fitted" rel="noreferrer" target="_blank" href="https://scikit-learn.org/1.6/modules/generated/sklearn.compose.ColumnTransformer.html">?<span>Documentation for preprocess: ColumnTransformer</span></a></div></label><div class="sk-toggleable__content fitted"><pre>ColumnTransformer(remainder=&#x27;passthrough&#x27;,
                      transformers=[(&#x27;scaler&#x27;, StandardScaler(with_std=False),
                                     [&#x27;annual_income&#x27;, &#x27;total_credit_lines&#x27;,
                                      &#x27;loan_amount&#x27;, &#x27;term&#x27;])])</pre></div> </div></div><div class="sk-parallel"><div class="sk-parallel-item"><div class="sk-item"><div class="sk-label-container"><div class="sk-label fitted sk-toggleable"><input class="sk-toggleable__control sk-hidden--visually" id="sk-estimator-id-3" type="checkbox" ><label for="sk-estimator-id-3" class="sk-toggleable__label fitted sk-toggleable__label-arrow"><div><div>scaler</div></div></label><div class="sk-toggleable__content fitted"><pre>[&#x27;annual_income&#x27;, &#x27;total_credit_lines&#x27;, &#x27;loan_amount&#x27;, &#x27;term&#x27;]</pre></div> </div></div><div class="sk-serial"><div class="sk-item"><div class="sk-estimator fitted sk-toggleable"><input class="sk-toggleable__control sk-hidden--visually" id="sk-estimator-id-4" type="checkbox" ><label for="sk-estimator-id-4" class="sk-toggleable__label fitted sk-toggleable__label-arrow"><div><div>StandardScaler</div></div><div><a class="sk-estimator-doc-link fitted" rel="noreferrer" target="_blank" href="https://scikit-learn.org/1.6/modules/generated/sklearn.preprocessing.StandardScaler.html">?<span>Documentation for StandardScaler</span></a></div></label><div class="sk-toggleable__content fitted"><pre>StandardScaler(with_std=False)</pre></div> </div></div></div></div></div><div class="sk-parallel-item"><div class="sk-item"><div class="sk-label-container"><div class="sk-label fitted sk-toggleable"><input class="sk-toggleable__control sk-hidden--visually" id="sk-estimator-id-5" type="checkbox" ><label for="sk-estimator-id-5" class="sk-toggleable__label fitted sk-toggleable__label-arrow"><div><div>remainder</div></div></label><div class="sk-toggleable__content fitted"><pre>[]</pre></div> </div></div><div class="sk-serial"><div class="sk-item"><div class="sk-estimator fitted sk-toggleable"><input class="sk-toggleable__control sk-hidden--visually" id="sk-estimator-id-6" type="checkbox" ><label for="sk-estimator-id-6" class="sk-toggleable__label fitted sk-toggleable__label-arrow"><div><div>passthrough</div></div></label><div class="sk-toggleable__content fitted"><pre>passthrough</pre></div> </div></div></div></div></div></div></div><div class="sk-item"><div class="sk-estimator fitted sk-toggleable"><input class="sk-toggleable__control sk-hidden--visually" id="sk-estimator-id-7" type="checkbox" ><label for="sk-estimator-id-7" class="sk-toggleable__label fitted sk-toggleable__label-arrow"><div><div>LinearRegression</div></div><div><a class="sk-estimator-doc-link fitted" rel="noreferrer" target="_blank" href="https://scikit-learn.org/1.6/modules/generated/sklearn.linear_model.LinearRegression.html">?<span>Documentation for LinearRegression</span></a></div></label><div class="sk-toggleable__content fitted"><pre>LinearRegression()</pre></div> </div></div></div></div></div></div>

## Convert to SQL using Orbital

1.  Import Orbital

    ``` python
    import orbitalml
    import orbitalml.types
    ```

2.  Parse the pipeline with Orbital. At this stage, you can define the
    predictor’s field and types, as well as any other fields that need
    to be included in the final result set.

    ``` python
    orbital_pipeline = orbitalml.parse_pipeline(
      pipeline, 
      features={
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
    ```

3.  Convert the pipeline to SQL. By default, Orbital will exclude the
    predictor fields from the finalized SQL statement, so
    `ResultsProjection()` is used to force the loan amount and loan term
    to be included in the statement.

    ``` python
    pred_sql = orbitalml.export_sql(
        table_name="loans_full_schema", 
        pipeline=orbital_pipeline, 
        projection= orbitalml.ResultsProjection(["loan_amount", "term"]),
        dialect="databricks"
        )
    ```

4.  Preview the resulting SQL statement

    ``` python
    pred_sql
    ```

        'SELECT `t0`.`loan_id` AS `loan_id`, `t0`.`emp_title` AS `emp_title`, `t0`.`balance` AS `balance`, `t0`.`application_type` AS `application_type`, `t0`.`interest_rate` AS `interest_rate`, (`t0`.`annual_income` - 77239.975) * -3.004111806545882e-05 + 12.646 + (`t0`.`total_credit_lines` - 23.225) * 0.01950461625046961 + (`t0`.`loan_amount` - 16201.5625) * 2.9834429401503845e-05 + (`t0`.`term` - 45.9) * 0.19726277170596157 AS `variable`, `t0`.`loan_amount` AS `loan_amount`, `t0`.`term` AS `term` FROM `loans_full_schema` AS `t0`'

5.  Use the new SQL statement as the source to filter for any rate that
    is 15 points above the prediction

    ``` python
    final_sql = f"select * from ({pred_sql}) where interest_rate - variable > 15 and variable > 0"

    final_sql
    ```

        'select * from (SELECT `t0`.`loan_id` AS `loan_id`, `t0`.`emp_title` AS `emp_title`, `t0`.`balance` AS `balance`, `t0`.`application_type` AS `application_type`, `t0`.`interest_rate` AS `interest_rate`, (`t0`.`annual_income` - 77239.975) * -3.004111806545882e-05 + 12.646 + (`t0`.`total_credit_lines` - 23.225) * 0.01950461625046961 + (`t0`.`loan_amount` - 16201.5625) * 2.9834429401503845e-05 + (`t0`.`term` - 45.9) * 0.19726277170596157 AS `variable`, `t0`.`loan_amount` AS `loan_amount`, `t0`.`term` AS `term` FROM `loans_full_schema` AS `t0`) where interest_rate - variable > 15 and variable > 0'

6.  Execute the finalized SQL statement, and return it as a Pandas data
    frame

    ``` python
    con_cursor = con.cursor()
    con_cursor.execute(final_sql)
    pred_cols = [desc[0] for desc in con_cursor.description]
    res = con_cursor.fetchall()
    pred_df = pd.DataFrame(res, columns=pred_cols)
    pred_df
    ```

    <div>
    <style scoped>
        .dataframe tbody tr th:only-of-type {
            vertical-align: middle;
        }
    &#10;    .dataframe tbody tr th {
            vertical-align: top;
        }
    &#10;    .dataframe thead th {
            text-align: right;
        }
    </style>

    |  | loan_id | emp_title | balance | application_type | interest_rate | variable | loan_amount | term |
    |----|----|----|----|----|----|----|----|----|
    | 0 | 9802 | operational risk manager | 0.00 | individual | 26.77 | 6.268735 | 5000 | 36 |
    | 1 | 3935 | sr admin assistant | 19821.53 | individual | 30.79 | 15.271815 | 20600 | 60 |
    | 2 | 5068 | assistant | 10672.97 | individual | 30.17 | 15.048231 | 11100 | 60 |
    | 3 | 5967 | rn | 6768.73 | individual | 25.82 | 10.208089 | 7500 | 36 |
    | 4 | 9338 | vice president of operations | 9774.95 | individual | 30.17 | 14.033024 | 10000 | 60 |
    | 5 | 4535 | mechanical designer | 15896.16 | individual | 30.75 | 10.860353 | 16175 | 36 |
    | 6 | 4833 | president of media division | 34119.79 | individual | 26.30 | 8.808102 | 35000 | 60 |
    | 7 | 1649 | pilot | 29297.84 | individual | 28.72 | 12.486257 | 30000 | 60 |
    | 8 | 9430 | sr project manager | 0.00 | individual | 23.88 | 7.005178 | 17000 | 36 |
    | 9 | 5526 | teacher | 24253.68 | individual | 30.79 | 15.700122 | 25000 | 60 |
    | 10 | 5657 | None | 19243.97 | individual | 30.79 | 15.673809 | 20000 | 60 |
    | 11 | 8057 | account manager | 24250.66 | individual | 30.65 | 13.753280 | 25000 | 60 |
    | 12 | 7471 | server engineer | 0.00 | individual | 30.79 | 14.910085 | 25000 | 60 |
    | 13 | 7772 | insurance broker | 9192.11 | joint | 26.30 | 9.761687 | 9550 | 36 |
    | 14 | 7668 | assistant vice president | 23589.47 | individual | 26.77 | 9.867967 | 25000 | 36 |
    | 15 | 5340 | operations manager - core | 27585.12 | joint | 30.17 | 14.443606 | 28000 | 60 |
    | 16 | 1241 | physician | 0.00 | individual | 26.77 | 7.631215 | 10000 | 36 |
    | 17 | 2887 | cytotechnologist | 34398.52 | individual | 30.94 | 11.017999 | 35000 | 36 |
    | 18 | 2732 | None | 1805.00 | individual | 25.82 | 10.406061 | 2000 | 36 |
    | 19 | 1127 | director, support | 23579.25 | individual | 26.30 | 8.085005 | 25000 | 36 |
    | 20 | 6933 | attorney/shareholder | 33643.67 | individual | 21.45 | 3.264169 | 35000 | 60 |
    | 21 | 4453 | executive manger | 17849.23 | individual | 21.45 | 4.984362 | 19450 | 36 |
    | 22 | 36 | None | 1318.63 | individual | 24.84 | 8.510812 | 1400 | 36 |
    | 23 | 843 | registered nurse | 34386.09 | individual | 29.69 | 9.161281 | 35000 | 36 |
    | 24 | 9569 | income developement specialist | 33635.31 | joint | 29.69 | 12.900652 | 35000 | 60 |
    | 25 | 3351 | electrician | 34494.86 | joint | 23.87 | 8.651117 | 40000 | 36 |
    | 26 | 8720 | nurse | 27230.80 | joint | 26.30 | 10.871734 | 30150 | 36 |
    | 27 | 1159 | cip compliance specialist | 1081.34 | individual | 24.85 | 9.134140 | 1200 | 36 |
    | 28 | 7972 | program analyst | 2042.13 | individual | 30.65 | 9.103450 | 2200 | 36 |
    | 29 | 4390 | executive director | 18456.81 | individual | 25.82 | 10.264924 | 20000 | 36 |
    | 30 | 5845 | supervisor | 14552.19 | individual | 30.79 | 15.526647 | 15000 | 60 |
    | 31 | 6450 | rn | 24054.97 | individual | 30.79 | 14.395123 | 25000 | 60 |
    | 32 | 6586 | business analyst | 0.00 | individual | 26.30 | 10.714821 | 5000 | 36 |
    | 33 | 9765 | chief operating officer | 15164.37 | individual | 24.84 | 9.147561 | 16100 | 36 |
    | 34 | 3514 | None | 5755.81 | individual | 26.77 | 11.663725 | 6100 | 36 |
    | 35 | 7117 | administration | 23084.76 | individual | 26.30 | 10.359162 | 25000 | 36 |
    | 36 | 7839 | benefits/worklife manager | 23185.38 | individual | 30.65 | 15.281168 | 24100 | 60 |
    | 37 | 8509 | general manager | 14635.95 | individual | 19.03 | 2.791786 | 16000 | 36 |
    | 38 | 814 | underwriter | 0.00 | individual | 30.17 | 12.653358 | 22000 | 60 |
    | 39 | 1231 | general manager | 0.00 | individual | 26.30 | 9.049302 | 4375 | 36 |
    | 40 | 6398 | conusultant | 29295.97 | individual | 28.72 | 12.989556 | 30000 | 60 |
    | 41 | 2389 | warehouse manager | 8586.56 | joint | 26.77 | 11.301432 | 9100 | 36 |

    </div>

## Automate in Databricks

1.  `WorkspaceClient` is the main way to create and manage objects

    ``` python
    from databricks.sdk import WorkspaceClient

    w = WorkspaceClient()
    ```

2.  The SQL tasks require a warehouse ID. This code pull the ID from the
    first warehouse returned by the function that lists all of the
    sources.

    ``` python
    srcs = w.data_sources.list()
    warehouse_id = srcs[0].warehouse_id
    ```

3.  To start, a new
    [Query](https://docs.databricks.com/aws/en/sql/user/queries/) is
    created in the Databricks Workspace. To start, the query object is
    built using `CreateQueryRequestQuery()`. This is where the
    `final_sql` value is passed. Additionally, the catalog and schema
    are also defined via their respective arguments.

    ``` python
    from databricks.sdk.service import sql as sdk_sql

    db_request_query = sdk_sql.CreateQueryRequestQuery(
            query_text=final_sql,
            catalog=catalog, 
            schema=schema,
            display_name="Interest rate differences",
            warehouse_id=warehouse_id,
            description="Find differences in interest rate",        
        )
    ```

4.  `w.queries.create()` takes the request query object to create the
    new query. After executing the command, a new query named *“Interest
    rate differences”* will appear in the Queries section of the
    Databricks Web UI.

    ``` python
    new_query = w.queries.create(query=db_request_query)
    ```

5.  A Databricks Job can be used to orchestrate multiple tasks. The job
    being created for this example requires a single task. Tasks could
    be a variety of kinds such as a Notebook, Python script, SQL Queries
    and many others. The following starts building the SQL task. It uses
    the `new_query`’s ID to tie it to the query created in the previous
    step.

    ``` python
    from databricks.sdk.service import jobs  as sdk_jobs

    db_sql_task_query = sdk_jobs.SqlTaskQuery(
        query_id = new_query.id
        )
    ```

6.  To finish defining the SQL task object, `db_sql_task_query` is
    passed to SqlTask()

    ``` python
    db_sql_task = sdk_jobs.SqlTask(
        query=db_sql_task_query, 
        warehouse_id=warehouse_id
        )
    ```

7.  The SQL task object is used to create a formal Task. This is the
    point where the resulting task in the Databricks UI can be named and
    described

    ``` python
    db_task = sdk_jobs.Task(
        sql_task=db_sql_task,
        description="Int rate diffs", 
        task_key="run_sql"
        )
    ```

8.  For this example, the Job needs to have a schedule defined. And to
    do this, a `CronSchedule` object is needed. To define the schedule
    use a [CRON
    expression](https://www.quartz-scheduler.org/documentation/).

    ``` python
    db_schedule = sdk_jobs.CronSchedule(
        quartz_cron_expression="0 0 12 * * ?",
        timezone_id="CST"
        )
    ```

9.  Finally, the Job is created using the task and schedule objects.
    After running the following command, a new Job named *“Daily check
    interest differences”* will appear in the Jobs section of the
    Databricks Web UI.

    ``` python
    new_job = w.jobs.create(
        name="Daily check interest differences",
        tasks=[db_task],    
        schedule=db_schedule
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

### Python environment

The following library requirements were used to run the example:

``` bash
dotenv>=0.9.9
orbitalml>=0.2.0
pandas>=2.2.3
pip>=25.1.1
databricks-sql-connector
pyarrow
```

There is an issue with the `onnx` binary for Python 3.13, so for the
example Python 3.12 was used.

### Full code

``` python
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import StandardScaler
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from dotenv import load_dotenv
from databricks import sql
import orbitalml.types
import pandas as pd
import orbitalml
import os

load_dotenv()
host = os.getenv("DATABRICKS_HOST")
token = os.getenv("DATABRICKS_TOKEN")
schema = "end-to-end"
catalog = "sol_eng_demo_nickp"
http_path = "/sql/1.0/warehouses/b71952ebceb705ce"
con = sql.connect(host, http_path, token, catalog = catalog, schema = schema)
con_cursor = con.cursor()
con_cursor.execute(
  "select * from loans_full_schema TABLESAMPLE (100 ROWS) REPEATABLE (999);"
  )
col_names = [desc[0] for desc in con_cursor.description]
res = con_cursor.fetchall()
full_df = pd.DataFrame(res, columns=col_names)

pred_names = ["annual_income", "total_credit_lines", "loan_amount",  "term"]
predictors = full_df[pred_names]
outcome = full_df["interest_rate"]
pred_train, pred_test, out_train, out_test = train_test_split(
    predictors, outcome, test_size=20, random_state=999
)
pipeline = Pipeline(
    [("preprocess", 
      ColumnTransformer(
        [("scaler", StandardScaler(with_std=False), pred_names)],
        remainder="passthrough")
        ),
    ("linear_regression", LinearRegression())]
)
pipeline.fit(pred_train, out_train)

orbital_pipeline = orbitalml.parse_pipeline(
  pipeline, 
  features={
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
pred_sql = orbitalml.export_sql(
    table_name="loans_full_schema", 
    pipeline=orbital_pipeline, 
    projection= orbitalml.ResultsProjection(["loan_amount", "term"]),
    dialect="databricks"
    )

final_sql = f"select * from ({pred_sql}) where interest_rate - variable > 15 and variable > 0"
con_cursor.execute(final_sql)
pred_cols = [desc[0] for desc in con_cursor.description]
res = con_cursor.fetchall()
pred_df = pd.DataFrame(res, columns=pred_cols)
pred_df
```
