resource "azurerm_container_registry" "main" {
  name                          = "cr${var.team_name}"
  resource_group_name           = azurerm_resource_group.devops.name
  location                      = var.location
  sku                           = "Standard"
  anonymous_pull_enabled        = false
  public_network_access_enabled = true

  tags = merge(local.common_tags, { Function = "acr" })
}
