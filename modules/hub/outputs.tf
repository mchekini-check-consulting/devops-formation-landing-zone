output "vnet_hub_id" {
  value = azurerm_virtual_network.main.id
}


output "vnet_hub_name" {
  value = azurerm_virtual_network.main.name
}

output "resource_group_name" {
  value = azurerm_resource_group.network.name
}

output "acr_login_server" {
  description = "URL du registre ACR pour pull les images (docker pull <url>/<image>:<tag>)"
  value       = azurerm_container_registry.main.login_server
}

output "acr_id" {
  description = "ID de l'ACR pour les role assignments"
  value       = azurerm_container_registry.main.id
}

output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "apim_public_ip" {
  description = "IP publique de l'APIM pour les tests depuis le navigateur"
  value       = azurerm_api_management.main.public_ip_addresses[0]
}

output "log_analytics_workspace_id" {
  description = "ID du Log Analytics Workspace centralisé pour tous les environnements"
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_instrumentation_key" {
  description = "Clé d'instrumentation Application Insights pour l'envoi de télémétrie"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string Application Insights (méthode recommandée pour les SDK récents)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "apim_subnet_id" {
  description = "L'id du subnet APIM"
  value = azurerm_subnet.subnet-apim.id
}

output "devops_resource_group_name" {
  description = "Nom du resource group hub devops (ACR, Managed Identities DevOps)"
  value       = azurerm_resource_group.devops.name
}