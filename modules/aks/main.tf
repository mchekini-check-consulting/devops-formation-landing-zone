resource "azurerm_resource_group" "aks" {
  name     = "rg-${var.team_name}-${var.project_name}-aks"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "aks" {
  name                = "vnet-${var.team_name}-${var.project_name}-aks"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  address_space       = [var.aks_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "subnet-aks"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = [var.aks_subnet_cidr]
}
