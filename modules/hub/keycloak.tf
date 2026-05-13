locals {
  keycloak_cloud_init = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    echo "=== Cloud-Init: Bootstrapping Keycloak VM ==="

    # Update system packages
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release openssl jq

    # Download and execute setup script from GitHub
    echo "Downloading setup script from GitHub..."
    curl -fsSL https://raw.githubusercontent.com/juba-touam/start-up-scritps/main/setup-keycloak.sh | bash

    echo "=== Cloud-Init: Bootstrap Complete ==="
    EOF
  )
}

# ============================================================================
# NETWORK SECURITY GROUP
# ============================================================================
# NSG : autorise SEULEMENT le port 8443 depuis le VNet
resource "azurerm_network_security_group" "keycloak" {
  name                = "nsg-${var.team_name}-keycloak-hub"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name

  security_rule {
    name                       = "Allow-Internal-HTTPS-8443"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  tags = merge(local.common_tags, { Function = "keycloak" })
}

resource "azurerm_subnet_network_security_group_association" "keycloak" {
  subnet_id                 = azurerm_subnet.keycloak.id
  network_security_group_id = azurerm_network_security_group.keycloak.id
}

# ============================================================================
# NETWORK INTERFACE (NO PUBLIC IP)
# ============================================================================
# Récupérer la clé SSH publique depuis Key Vault
data "azurerm_key_vault_secret" "admin_ssh_public_key" {
  name         = var.ssh_public_key_secret_name
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_network_interface" "keycloak" {
  name                = "nic-${var.team_name}-keycloak-hub"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.keycloak.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = merge(local.common_tags, { Function = "keycloak" })
}

# ============================================================================
# LINUX VM
# ============================================================================
resource "azurerm_linux_virtual_machine" "keycloak" {
  name                = "vm-${var.team_name}-keycloak-hub"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  size                = var.vm_size
  admin_username      = var.vm_admin_username

  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.keycloak.id]
  custom_data = local.keycloak_cloud_init

  # Clé SSH
  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = data.azurerm_key_vault_secret.admin_ssh_public_key.value
  }

  # Disque OS
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Image Ubuntu 22.04 LTS
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = merge(local.common_tags, { Function = "keycloak" })
}

#--------------------------------------------------------------
# Extension AAD SSH Login
#--------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "aad_ssh_login" {
  name                 = "AADSSHLoginForLinux"
  virtual_machine_id   = azurerm_linux_virtual_machine.keycloak.id
  publisher            = "Microsoft.Azure.ActiveDirectory"
  type                 = "AADSSHLoginForLinux"
  type_handler_version = "1.0"

  tags = merge(local.common_tags, {
    Function = "keycloak"
  })
}
