library(tools)
library(utils)

ui <- fluidPage(
  titlePanel("Sales")
)

server <- function(input, output) {
  output$table <- renderTable(load_sales())
}
