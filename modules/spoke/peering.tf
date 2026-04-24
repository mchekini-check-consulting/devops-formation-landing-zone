#--------------------------------------------------------------
# VNet Peering - Hub <-> Spoke
#--------------------------------------------------------------

# Peering Hub -> Spoke
resource "azurerm_virtual_network_peering" "hub-to-spoke" {
  for_each = toset(var.environments)

  name                         = "peer-hub-to-spoke-${var.project_name}-${each.key}"
  remote_virtual_network_id    = azurerm_virtual_network.main[each.key].id
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  allow_virtual_network_access = true
}

# Peering Spoke -> Hub
resource "azurerm_virtual_network_peering" "spoke-to-hub" {
  for_each = toset(var.environments)

  name                         = "peer-spoke-to-hub-${var.project_name}-${each.key}"
  remote_virtual_network_id    = var.hub_vnet_id
  resource_group_name          = azurerm_resource_group.main[each.key].name
  virtual_network_name         = azurerm_virtual_network.main[each.key].name
  allow_virtual_network_access = true
}
