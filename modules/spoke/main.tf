#--------------------------------------------------------------
# SPOKE - Ressources par projet et environnement
#--------------------------------------------------------------

locals {
  common_tags = merge(var.tags, {
    Project   = var.project_name
    ManagedBy = "Terraform"
  })

  # Calcul des subnets pour chaque environnement
  subnets = {
    for env in var.environments : env => {
      front = cidrsubnet(var.address_spaces[env], 8, 0)  # x.x.0.0/24
      back  = cidrsubnet(var.address_spaces[env], 8, 1)  # x.x.1.0/24
      data  = cidrsubnet(var.address_spaces[env], 8, 2)  # x.x.2.0/24
    }
  }
}

#--------------------------------------------------------------
# Resource Groups (un par environnement)
#--------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  for_each = toset(var.environments)

  name     = "rg-${var.team_name}-${var.project_name}-${each.key}"
  location = var.location

  tags = merge(local.common_tags, {
    Environment = each.key
  })
}

#--------------------------------------------------------------
# VNets (un par environnement)
#--------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  for_each = toset(var.environments)

  name                = "vnet-${var.team_name}-${var.project_name}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main[each.key].name
  address_space       = [var.address_spaces[each.key]]

  tags = merge(local.common_tags, {
    Environment = each.key
  })
}

#--------------------------------------------------------------
# Subnets
#--------------------------------------------------------------
resource "azurerm_subnet" "subnet-front" {
  for_each = toset(var.environments)

  name                 = "subnet-front-${each.key}"
  resource_group_name  = azurerm_resource_group.main[each.key].name
  virtual_network_name = azurerm_virtual_network.main[each.key].name
  address_prefixes     = [local.subnets[each.key].front]
}

resource "azurerm_subnet" "subnet-back" {
  for_each = toset(var.environments)

  name                 = "subnet-back-${each.key}"
  resource_group_name  = azurerm_resource_group.main[each.key].name
  virtual_network_name = azurerm_virtual_network.main[each.key].name
  address_prefixes     = [local.subnets[each.key].back]
}

resource "azurerm_subnet" "subnet-data" {
  for_each = toset(var.environments)

  name                 = "subnet-data-${each.key}"
  resource_group_name  = azurerm_resource_group.main[each.key].name
  virtual_network_name = azurerm_virtual_network.main[each.key].name
  address_prefixes     = [local.subnets[each.key].data]
}
