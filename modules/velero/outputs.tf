output "storage_account_name" {
  description = "Nom du Storage Account Velero (à passer au module platform)"
  value       = azurerm_storage_account.velero.name
}

output "storage_container_name" {
  description = "Nom du container Blob Velero"
  value       = azurerm_storage_container.velero.name
}

output "resource_group_name" {
  description = "Resource Group contenant les ressources Velero Azure"
  value       = var.resource_group_name
}

output "uami_client_id" {
  description = "Client ID de l'UAMI Velero (annotation Workload Identity sur le ServiceAccount K8s)"
  value       = azurerm_user_assigned_identity.velero.client_id
}

output "subscription_id" {
  description = "Subscription ID Azure courante (requis par le plugin Velero for Azure)"
  value       = data.azurerm_client_config.current.subscription_id
}
