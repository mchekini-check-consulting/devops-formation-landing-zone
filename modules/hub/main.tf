locals {
  keycloak_subnet_prefix = cidrsubnet(var.address_space, 8, 10)

  common_tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })
}


resource "azurerm_resource_group" "monitoring" {
  location = var.location
  name     = "rg-${var.team_name}-monitoring"
  tags = merge(local.common_tags, { Function = "monitoring" })
}

resource "azurerm_resource_group" "network" {
  location = var.location
  name     = "rg-${var.team_name}-network"
  tags = merge(local.common_tags, { Function = "network" })
}

resource "azurerm_resource_group" "security" {
  location = var.location
  name     = "rg-${var.team_name}-security"
  tags = merge(local.common_tags, { Function = "security" })
}

resource "azurerm_resource_group" "devops" {
  location = var.location
  name     = "rg-${var.team_name}-devops"
  tags = merge(local.common_tags, { Function = "devops" })
}


# VNet Hub

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.team_name}-hub"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  address_space = [var.address_space]
  tags                = local.common_tags
}

resource "azurerm_subnet" "keycloak" {
  name                 = "subnet-keycloak-hub"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.keycloak_subnet_prefix]
}