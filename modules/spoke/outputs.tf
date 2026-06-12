#--------------------------------------------------------------
# Fraud-check outputs
#--------------------------------------------------------------

output "fraud_check_function_app_ids" {
  description = "IDs des Function Apps fraud-check par environnement"
  value = {
    for env in var.environments :
    env => azurerm_linux_function_app.fraud_check[env].id
  }
}

output "fraud_check_function_app_names" {
  description = "Noms des Function Apps fraud-check par environnement"
  value = {
    for env in var.environments :
    env => azurerm_linux_function_app.fraud_check[env].name
  }
}

output "fraud_check_function_urls" {
  description = "URLs des endpoints fraud-check par environnement"
  value = {
    for env in var.environments :
    env => "https://${azurerm_linux_function_app.fraud_check[env].default_hostname}/api/fraud-check"
  }
  sensitive = false
}

output "fraud_check_identity_principal_ids" {
  description = "Principal IDs des Managed Identities fraud-check par environnement"
  value = {
    for env in var.environments :
    env => azurerm_user_assigned_identity.fraud_check[env].principal_id
  }
}
