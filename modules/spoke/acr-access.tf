resource "azurerm_user_assigned_identity" "acr" {
  for_each            = toset(var.environments)
  name                = "id-${var.team_name}-${var.project_name}-acr-${each.key}"
  resource_group_name = azurerm_resource_group.main[each.key].name
  location            = var.location

  tags = merge(local.common_tags, {
    Environment = each.key
    Function    = "acr-access"
  })
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each             = toset(var.environments)
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.acr[each.key].principal_id
}
