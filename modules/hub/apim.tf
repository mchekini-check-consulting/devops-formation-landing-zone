resource "azurerm_api_management" "main" {
  name                = "apim-${var.team_name}"
  resource_group_name = azurerm_resource_group.devops.name
  location            = var.location
  publisher_name      = "apim-${var.team_name}"
  publisher_email     = var.apim_publisher_email
  sku_name            = "Developer_1"

  virtual_network_type = "External"

  virtual_network_configuration {
    subnet_id = azurerm_subnet.subnet-apim.id
  }

  tags = merge(local.common_tags, { Function = "apim" })
}
