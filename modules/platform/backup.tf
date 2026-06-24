resource "azurerm_resource_group" "backup" {
  name     = "rg-${var.team_name}-${var.project_name}-backup"
  location = var.location
}

resource "azurerm_storage_account" "backup" {
  name                     = "st${var.team_name}${var.project_name}backup"
  resource_group_name      = azurerm_resource_group.backup.name
  location                 = azurerm_resource_group.backup.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Cool"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "backups" {
  name               = "postgres-backups"
  storage_account_id = azurerm_storage_account.backup.id
}

resource "azurerm_storage_management_policy" "retention" {
  storage_account_id = azurerm_storage_account.backup.id

  rule {
    name    = "delete-old-backups"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = 7
      }
    }
  }
}

resource "azurerm_user_assigned_identity" "backup" {
  name                = "id-${var.team_name}-${var.project_name}-pg-backup"
  resource_group_name = azurerm_resource_group.backup.name
  location            = azurerm_resource_group.backup.location
}

resource "azurerm_federated_identity_credential" "backup" {
  name                      = "fed-${var.team_name}-${var.project_name}-pg-backup"
  user_assigned_identity_id = azurerm_user_assigned_identity.backup.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:postgres-backup:sa-pg-backup"
}

resource "azurerm_role_assignment" "backup_blob" {
  principal_id         = azurerm_user_assigned_identity.backup.principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.backup.id
}
