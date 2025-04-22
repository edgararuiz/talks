library(tidymodels)
library(tidyverse)
library(shiny)
library(pins)

board <- board_databricks("/Volumes/sol_eng_demo_nickp/end-to-end/r-models")
model <- pin_read(board, "lending-model-linear")

ui <- fluidPage(
  titlePanel("Lending Club Model"),
  sidebarLayout(
    sidebarPanel(
      sliderInput(
        "int_paid",
        "Interest paid:",
        min = 10000,
        max = 200000,
        value = 100000
      ), 
      textInput("curr_del", "Current Account Delinquent", 0)
    ),

    # Show a plot of the generated distribution
    mainPanel(
      plotOutput("distPlot")
    )
  )
)

server <- function(input, output) {
  output$distPlot <- renderPlot({
    tbl_selected <- tibble(
      paid_late_fees = 0,
      accounts_opened_24m = 5,
      num_satisfactory_accounts = 10,
      current_accounts_delinq = 0,
      current_installment_accounts = as.numeric(input$curr_del),
      annual_income = as.numeric(input$int_paid),
      paid_total = 1999,
      match = 1
    )

    tbl_paid_int <- tibble(paid_interest = paid_interest <- c(100, c(1:8) * 500), match = 1)

    full_table <- tbl_paid_int |>
      full_join(tbl_selected, by = "match") 

    preds <- predict(model, full_table)

    full_table |>
      bind_cols(preds) |>
      ggplot(aes(x = paid_interest, `.pred`)) +
      geom_line(color = "#ddd") +
      geom_text(aes(label = format(.pred, digits = 3)), nudge_y = 0.5, size = 3) +
      theme_minimal() +
      scale_y_continuous(limits = c(0, 35)) +
      theme(panel.grid = element_blank())
  })
}

shinyApp(ui = ui, server = server)
