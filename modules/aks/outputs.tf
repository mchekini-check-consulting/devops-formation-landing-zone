output "kubeconfig" {
  description = "Kubeconfig du cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "URL de l'OIDC Issuer AKS (requis pour les Federated Identity Credentials)"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "resource_group_name" {
  description = "Resource Group du cluster AKS"
  value       = azurerm_resource_group.aks.name
}
