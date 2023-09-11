# Databricks with R - Presentation

```r
app_files <- fs::dir_ls()
app_files <- app_files[!grepl("qmd", app_files)]
app_files <- app_files[!grepl("rsconnect", app_files)]
rsconnect::writeManifest(
  appPrimaryDoc = "posit-conf-databricks.html",
  appFiles = app_files
)
```
