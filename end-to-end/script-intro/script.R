library(pins)

board <- board_databricks("/Volumes/sol_eng_demo_nickp/end-to-end/my_volume")

df <- data.frame(x = 1, y = 2)

pin_write(board, df, "test")

pin_write(board, df, "test")

df <- data.frame(x = 1, y = 3)

pin_write(board, df, "test")

x_list <- list(x = 1, y = list(a = 4, b = 5))

pin_write(board, x_list, "list_data")

pin_write(board, df, "test2", metadata = list(my_tag = "something cool"))
