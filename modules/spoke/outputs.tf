#--------------------------------------------------------------
# PostgreSQL Outputs
#--------------------------------------------------------------

output "postgres_fqdns" {
  description = "FQDNs des serveurs PostgreSQL par environnement"
  value = {
    for env in var.environments : env => azurerm_postgresql_flexible_server.postgres[env].fqdn
  }
}

output "postgres_server_ids" {
  description = "IDs des serveurs PostgreSQL par environnement"
  value = {
    for env in var.environments : env => azurerm_postgresql_flexible_server.postgres[env].id
  }
}

output "postgres_server_names" {
  description = "Noms des serveurs PostgreSQL par environnement"
  value = {
    for env in var.environments : env => azurerm_postgresql_flexible_server.postgres[env].name
  }
}

#--------------------------------------------------------------
# VM Identity Outputs
#--------------------------------------------------------------

output "keyvault_identity_principal_ids" {
  description = "Principal IDs des identités Key Vault par environnement (utilisées par les VMs front)"
  value = {
    for env in var.environments : env => azurerm_user_assigned_identity.keyvault[env].principal_id
  }
}

output "keyvault_identity_client_ids" {
  description = "Client IDs des identités Key Vault par environnement (pour IMDS)"
  value = {
    for env in var.environments : env => azurerm_user_assigned_identity.keyvault[env].client_id
  }
}

#--------------------------------------------------------------
# Load Balancer Outputs
#--------------------------------------------------------------

output "backend_vm_ip" {
  description = "IP privée de la première VM back par environnement"
  value = {
    for key, vm in local.vm_instances : vm.env => azurerm_network_interface.vm[key].private_ip_address
    if vm.service == "back" && vm.index == 1
  }
}

output "frontend_public_ip" {
  description = "IP publique de la VM front par environnement"
  value = {
    for key, vm in local.front_vm_instances : vm.env => azurerm_public_ip.front[key].ip_address
  }
}

output "payment_lb_ip" {
  description = "IP privée du Load Balancer payment par environnement"
  value = {
    for env, lb in azurerm_lb.payment : env => lb.frontend_ip_configuration[0].private_ip_address
  }
}

#--------------------------------------------------------------
# Fraud-check outputs (single Function App created only for "dev")
#--------------------------------------------------------------

output "fraud_check_function_app_ids" {
  description = "IDs des Function Apps fraud-check par environnement (valeur pour dev, null sinon)"
  value = {
    for env in var.environments :
    env => env == "dev" ? azurerm_linux_function_app.fraud_check.id : null
  }
}

output "fraud_check_function_app_names" {
  description = "Noms des Function Apps fraud-check par environnement (valeur pour dev, null sinon)"
  value = {
    for env in var.environments :
    env => env == "dev" ? azurerm_linux_function_app.fraud_check.name : null
  }
}

output "fraud_check_function_urls" {
  description = "URLs des endpoints fraud-check par environnement (valeur pour dev, null sinon)"
  value = {
    for env in var.environments :
    env => env == "dev" ? "https://${azurerm_linux_function_app.fraud_check.default_hostname}/api/fraud-check" : null
  }
  sensitive = false
}

output "fraud_check_identity_principal_ids" {
  description = "Principal IDs des Managed Identities fraud-check par environnement (valeur pour dev, null sinon)"
  value = {
    for env in var.environments :
    env => env == "dev" ? azurerm_user_assigned_identity.fraud_check.principal_id : null
  }
}
