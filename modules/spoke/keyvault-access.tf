resource "azurerm_user_assigned_identity" "keyvault" {
  for_each            = toset(var.environments)
  name                = "id-${var.team_name}-${var.project_name}-kv-${each.key}"
  resource_group_name = azurerm_resource_group.main[each.key].name
  location            = var.location

  tags = merge(local.common_tags, {
    Environment = each.key
    Function    = "keyvault-access"
  })
}
