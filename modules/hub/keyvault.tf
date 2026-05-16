locals {
  terraform_secret_permissions      = ["Get", "Set", "List", "Delete", "Recover", "Purge"]
  terraform_certificate_permissions = ["Get", "List", "Create", "Delete", "Import", "Update", "Recover", "Purge"]
}

data "azurerm_client_config" "current" {}

resource "null_resource" "generate_ssh_key_in_vault" {
  depends_on = [azurerm_key_vault.main]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail

      VAULT_NAME="${azurerm_key_vault.main.name}"
      PUBLIC_SECRET_NAME="${var.ssh_public_key_secret_name}"
      PRIVATE_SECRET_NAME="${var.ssh_private_key_secret_name}"

      if az keyvault secret show --vault-name "$VAULT_NAME" --name "$PUBLIC_SECRET_NAME" >/dev/null 2>&1; then
        echo "SSH key already exists in Key Vault, skipping generation."
        exit 0
      fi

      TMP_DIR="$(mktemp -d)"
      KEY_PATH="$TMP_DIR/vm_admin_key"

      ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -q

      az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name "$PRIVATE_SECRET_NAME" \
        --file "$KEY_PATH" \
        >/dev/null

      az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name "$PUBLIC_SECRET_NAME" \
        --file "$KEY_PATH.pub" \
        >/dev/null

      rm -f "$KEY_PATH" "$KEY_PATH.pub"
      rmdir "$TMP_DIR"

      echo "SSH key pair generated and stored in Key Vault."
    EOT
  }

  triggers = {
    key_vault_name      = azurerm_key_vault.main.name
    public_secret_name  = var.ssh_public_key_secret_name
    private_secret_name = var.ssh_private_key_secret_name
  }
}


resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.security.location
  resource_group_name = azurerm_resource_group.security.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  soft_delete_retention_days = 7
  purge_protection_enabled   = false


  access_policy {
    tenant_id               = data.azurerm_client_config.current.tenant_id
    object_id               = var.readers_group_object_id
    secret_permissions      = local.terraform_secret_permissions
    certificate_permissions = local.terraform_certificate_permissions
  }

  # Access policy pour les identités des VMs front (lecture certificats)
  dynamic "access_policy" {
    for_each = var.front_vm_identity_principal_ids
    content {
      tenant_id               = data.azurerm_client_config.current.tenant_id
      object_id               = access_policy.value
      secret_permissions      = ["Get", "List"]
      certificate_permissions = ["Get", "List"]
    }
  }

  tags = merge(local.common_tags, {
    Function = "security"
  })
}

#--------------------------------------------------------------
# Certificat auto-signé pour HTTPS sur la VM front
#--------------------------------------------------------------
resource "azurerm_key_vault_certificate" "front_tls" {
  name         = "front-tls"
  key_vault_id = azurerm_key_vault.main.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }

    x509_certificate_properties {
      subject            = "CN=ecom-front"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = ["ecom-front"]
      }

      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }
  }

  tags = merge(local.common_tags, {
    Function = "tls"
  })
}
