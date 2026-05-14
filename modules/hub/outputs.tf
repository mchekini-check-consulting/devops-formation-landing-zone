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

output "keycloak_private_ip" {
  description = "Private IP address of the Keycloak VM"
  value       = azurerm_network_interface.keycloak.ip_configuration[0].private_ip_address
}

output "keycloak_subnet_id" {
  description = "Subnet ID where Keycloak is deployed"
  value       = azurerm_subnet.keycloak.id
}

output "keycloak_internal_url" {
  description = "Internal URL to access Keycloak from VNet"
  value       = "https://${azurerm_network_interface.keycloak.ip_configuration[0].private_ip_address}:8443"
}

output "keycloak_vm_name" {
  description = "Name of the Keycloak VM"
  value       = azurerm_linux_virtual_machine.keycloak.name
}