output "backup_identity_client_id" {
  description = "Client ID de la Managed Identity pour le backup PostgreSQL"
  value       = azurerm_user_assigned_identity.backup.client_id
}
