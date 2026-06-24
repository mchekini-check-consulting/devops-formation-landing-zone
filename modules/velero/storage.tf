resource "azurerm_storage_account" "velero" {
  name                     = "stvelero${var.team_name}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Cool"
  min_tls_version          = "TLS1_2"

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "velero" {
  name                  = "velero-backups"
  storage_account_id    = azurerm_storage_account.velero.id
  container_access_type = "private"
}

# Filet de sécurité : supprime tout blob > 45j si le garbage collector Velero échoue
resource "azurerm_storage_management_policy" "velero" {
  storage_account_id = azurerm_storage_account.velero.id

  rule {
    name    = "velero-expire"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["velero-backups/"]
    }

    actions {
      base_blob {
        tier_to_archive_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than          = 45
      }
    }
  }
}
