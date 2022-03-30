resource "random_string" "pgsql_user_password" {
  length  = 16
  special = false
}

locals {
  pgsql_user_password = random_string.pgsql_user_password.result
}
