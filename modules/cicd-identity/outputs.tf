output "client_id" {
  description = "Client ID du Service Principal CI/CD (AZURE_CLIENT_ID dans GitHub Secrets)"
  value       = azuread_application.cicd.client_id
}

output "tenant_id" {
  description = "Tenant ID Azure AD (AZURE_TENANT_ID dans GitHub Secrets)"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Subscription ID Azure (AZURE_SUBSCRIPTION_ID dans GitHub Secrets)"
  value       = data.azurerm_client_config.current.subscription_id
}
