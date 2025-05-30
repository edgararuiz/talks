import polars as pl
import mall

wine_url = "https://raw.githubusercontent.com/rfordatascience/tidytuesday/main/data/2019/2019-05-28/winemag-data-130k-v2.csv"

wine = pl.read_csv(wine_url)

wine.describe

wine.llm.use("ollama", model = "llama3.2")