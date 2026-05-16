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

#--------------------------------------------------------------
# VM Identity Outputs
#--------------------------------------------------------------

output "keyvault_identity_principal_ids" {
  description = "Principal IDs des identités Key Vault par environnement (utilisées par les VMs front)"
  value = {
    for env in var.environments : env => azurerm_user_assigned_identity.keyvault[env].principal_id
  }
}

output "keyvault_identity_client_ids" {
  description = "Client IDs des identités Key Vault par environnement (pour IMDS)"
  value = {
    for env in var.environments : env => azurerm_user_assigned_identity.keyvault[env].client_id
  }
}