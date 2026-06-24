resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.team_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.monitoring.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(local.common_tags, {
    Function = "monitoring"
  })
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${var.team_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.monitoring.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  daily_data_cap_in_gb                  = 1
  daily_data_cap_notifications_disabled = false
  sampling_percentage                   = 50

  tags = merge(local.common_tags, {
    Function = "monitoring"
  })
}
