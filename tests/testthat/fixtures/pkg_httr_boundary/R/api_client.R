fetch_user <- function(id) {
  httr::GET(paste0("https://api.example.com/users/", id))
}
