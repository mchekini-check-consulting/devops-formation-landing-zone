output "key_vault_id" {
  value = module.hub.key_vault_id
}

output "key_vault_name" {
  value = module.hub.key_vault_name
}


output "acr_login_server" {
  description = "URL du registre ACR pour pull les images (docker pull <url>/<image>:<tag>)"
  value       = module.hub.acr_login_server
}

output "acr_id" {
  description = "ID de l'ACR pour les role assignments"
  value       = module.hub.acr_id
}


#--------------------------------------------------------------
# AKS Outputs
#--------------------------------------------------------------

output "aks_kubeconfig" {
  description = "Kubeconfig du cluster AKS"
  value       = module.aks.kubeconfig
  sensitive   = true
}

#--------------------------------------------------------------
# Backup Outputs
#--------------------------------------------------------------

output "backup_identity_client_id" {
  description = "Client ID de la Managed Identity backup — à mettre dans k8s/postgres-backup/serviceaccount.yaml"
  value       = module.platform.backup_identity_client_id
}

output "sonarqube_namespace" {
  description = "Namespace K8s SonarQube — kubectl get svc -n <namespace> sonarqube-sonarqube pour récupérer l'IP du LoadBalancer"
  value       = module.platform.sonarqube_namespace
}

output "sonarqube_admin_secret_name" {
  description = "Nom du secret Key Vault contenant le mot de passe admin SonarQube"
  value       = module.platform.sonarqube_admin_secret_name
}

