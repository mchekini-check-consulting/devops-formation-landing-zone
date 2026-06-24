output "kubeconfig" {
  description = "Kubeconfig du cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "URL de l'émetteur OIDC du cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "cluster_name" {
  description = "Nom du cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "resource_group_name" {
  description = "Nom du resource group AKS"
  value       = azurerm_resource_group.aks.name
}

output "aks_id" {
  description = "ID du cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.id
}
