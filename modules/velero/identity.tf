data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "velero" {
  name                = "uami-velero-${var.team_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Scope sur le Storage Account (pas le container) pour que Velero puisse lister les containers
resource "azurerm_role_assignment" "velero_blob" {
  scope                = azurerm_storage_account.velero.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

# Lien entre le ServiceAccount K8s "velero" (namespace velero) et l'UAMI Azure
resource "azurerm_federated_identity_credential" "velero" {
  name                      = "fedcred-velero-${var.team_name}"
  user_assigned_identity_id = azurerm_user_assigned_identity.velero.id

  issuer   = var.aks_oidc_issuer_url
  subject  = "system:serviceaccount:velero:velero-server"
  audience = ["api://AzureADTokenExchange"]
}
