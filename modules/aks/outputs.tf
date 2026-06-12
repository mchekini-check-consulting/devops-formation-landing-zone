output "kubeconfig" {
  description = "Kubeconfig du cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}
