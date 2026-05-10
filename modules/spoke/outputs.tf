#--------------------------------------------------------------
# PostgreSQL Outputs
#--------------------------------------------------------------

output "postgres_fqdns" {
  description = "FQDNs des serveurs PostgreSQL par environnement"
  value = {
    for env in var.environments : env => azurerm_postgresql_flexible_server.postgres[env].fqdn
  }
}

output "postgres_server_ids" {
  description = "IDs des serveurs PostgreSQL par environnement"
  value = {
    for env in var.environments : env => azurerm_postgresql_flexible_server.postgres[env].id
  }
}

output "postgres_server_names" {
  description = "Noms des serveurs PostgreSQL par environnement"
  value = {
    for env in var.environments : env => azurerm_postgresql_flexible_server.postgres[env].name
  }
}