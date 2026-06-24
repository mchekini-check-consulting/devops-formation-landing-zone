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


output "devops_resource_group_name" {
  description = "Nom du resource group hub devops (ACR, Managed Identities DevOps)"
  value       = azurerm_resource_group.devops.name
}

output "devops_resource_group_id" {
  description = "ID du resource group hub devops"
  value       = azurerm_resource_group.devops.id
}