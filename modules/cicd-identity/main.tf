data "azurerm_client_config" "current" {}

resource "azuread_application" "cicd" {
  display_name = "sp-${var.team_name}-cicd"

  lifecycle {
    ignore_changes = all
  }
}

resource "azuread_service_principal" "cicd" {
  client_id = azuread_application.cicd.client_id

  lifecycle {
    ignore_changes = all
  }
}

resource "azuread_application_federated_identity_credential" "github_main" {
  for_each = toset(var.github_repositories)

  application_id = azuread_application.cicd.id
  display_name   = "${replace(each.value, "/[^a-zA-Z0-9-]/", "-")}-main"
  description    = "GitHub Actions OIDC for ${each.value} (main)"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_org}/${each.value}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "github_pr" {
  for_each = toset(var.github_repositories)

  application_id = azuread_application.cicd.id
  display_name   = "${replace(each.value, "/[^a-zA-Z0-9-]/", "-")}-pr"
  description    = "GitHub Actions OIDC for ${each.value} (pull_request)"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_org}/${each.value}:pull_request"
}

resource "azurerm_role_assignment" "acr_push" {
  scope                = var.acr_id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.cicd.object_id
}

resource "azurerm_role_assignment" "aks_user" {
  scope                = var.aks_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.cicd.object_id
}

resource "azurerm_role_assignment" "rg_contributor" {
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.cicd.object_id
}
