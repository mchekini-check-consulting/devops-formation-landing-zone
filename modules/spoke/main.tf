
locals {
  common_tags = merge(var.tags, {
    Project   = var.project_name
    ManagedBy = "Terraform"
  })

  subnets = {
    for env in var.environments : env => {
      front = cidrsubnet(var.address_spaces[env], 8, 0)
      back = cidrsubnet(var.address_spaces[env], 8, 1)
      data = cidrsubnet(var.address_spaces[env], 8, 2)
    }
  }


}

resource "azurerm_resource_group" "main" {
  for_each = toset(var.environments)

  location = var.location
  name     = "rg-${var.team_name}-${var.project_name}-${each.key}"
  tags = merge(local.common_tags, { Environment = each.key })
}


resource "azurerm_virtual_network" "main" {

  for_each = toset(var.environments)

  location            = var.location
  name                = "vnet-${var.team_name}-${var.project_name}-${each.key}"
  resource_group_name = azurerm_resource_group.main[each.key].name
  address_space = [var.address_spaces[each.key]]

  tags = merge(local.common_tags, { Environment = each.key })
}

resource "azurerm_subnet" "subnet-front" {
  for_each = toset(var.environments)

  name                 = "subnet-front-${each.key}"
  resource_group_name  = azurerm_resource_group.main[each.key].name
  virtual_network_name = azurerm_virtual_network.main[each.key].name
  address_prefixes = [local.subnets[each.key].front]
}


resource "azurerm_subnet" "subnet-back" {
  for_each = toset(var.environments)

  name                 = "subnet-back-${each.key}"
  resource_group_name  = azurerm_resource_group.main[each.key].name
  virtual_network_name = azurerm_virtual_network.main[each.key].name
  address_prefixes = [local.subnets[each.key].back]
}



resource "azurerm_subnet" "subnet-data" {
  for_each = toset(var.environments)

  name                 = "subnet-data-${each.key}"
  resource_group_name  = azurerm_resource_group.main[each.key].name
  virtual_network_name = azurerm_virtual_network.main[each.key].name
  address_prefixes = [local.subnets[each.key].data]
}


# Peering Hub -> Spoke

resource "azurerm_virtual_network_peering" "hub-to-spoke" {

  for_each = toset(var.environments)

  name                      = "peer-hub-to-spoke-${var.project_name}-${each.key}"
  remote_virtual_network_id = azurerm_virtual_network.main[each.key].id
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = var.hub_vnet_name
  allow_virtual_network_access =  true
}


resource "azurerm_virtual_network_peering" "spoke-to-hub" {

  for_each = toset(var.environments)

  name                      = "peer-spoke-to-hub-${var.project_name}-${each.key}"
  remote_virtual_network_id = var.hub_vnet_id
  resource_group_name       = azurerm_resource_group.main[each.key].name
  virtual_network_name      = azurerm_virtual_network.main[each.key].name
  allow_virtual_network_access =  true
}
