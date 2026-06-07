output "backup_identity_client_id" {
  description = "Client ID de la Managed Identity pour le backup PostgreSQL"
  value       = azurerm_user_assigned_identity.backup.client_id
}

output "sonarqube_namespace" {
  description = "Namespace Kubernetes de SonarQube"
  value       = helm_release.sonarqube.namespace
}

output "sonarqube_admin_secret_name" {
  description = "Nom du secret Key Vault contenant le mot de passe admin SonarQube"
  value       = azurerm_key_vault_secret.sonarqube_admin_password.name
}
