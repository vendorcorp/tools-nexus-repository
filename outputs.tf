output "pgsql_username" {
  value = local.pgsql_username
}

output "pgsql_password" {
  value     = local.pgsql_user_password
  sensitive = true
}
