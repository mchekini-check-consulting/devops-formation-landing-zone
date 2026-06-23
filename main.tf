module "hub" {
  source        = "./modules/hub"
  team_name     = var.team_name
  location      = var.location
  address_space = var.hub_address_space

  key_vault_name              = var.key_vault_name
  ssh_public_key_secret_name  = var.ssh_public_key_secret_name
  ssh_private_key_secret_name = var.ssh_private_key_secret_name
  readers_group_object_id     = var.readers_group_object_id
}


module "aks" {
  source       = "./modules/aks"
  team_name    = var.team_name
  project_name = "ecom"
  location     = var.location
  acr_id       = module.hub.acr_id
}

module "velero" {
  source              = "./modules/velero"
  team_name           = var.team_name
  location            = var.location
  resource_group_name = module.aks.resource_group_name
  aks_oidc_issuer_url = module.aks.oidc_issuer_url

  tags = {
    managed_by = "terraform"
    team       = var.team_name
    component  = "backup"
  }
}

module "platform" {
  source          = "./modules/platform"
  team_name       = var.team_name
  project_name    = "ecom"
  location        = var.location
  oidc_issuer_url = module.aks.oidc_issuer_url

  velero_storage_account   = module.velero.storage_account_name
  velero_storage_container = module.velero.storage_container_name
  velero_resource_group    = module.velero.resource_group_name
  velero_subscription_id   = module.velero.subscription_id
  velero_uami_client_id    = module.velero.uami_client_id

  key_vault_id = module.hub.key_vault_id
}

module "cicd_identity" {
  source = "./modules/cicd-identity"

  team_name  = var.team_name
  github_org = "mchekini-check-consulting"
  github_repositories = [
    "devops-formation-catalog",
    "devops-formation-order",
    "devops-formation-payment",
    "devops-formation-landing-zone",
    "devops-formation-utils",
  ]

  acr_id            = module.hub.acr_id
  aks_id            = module.aks.aks_id
  resource_group_id = module.hub.devops_resource_group_id
}

module "spoke" {
  source                  = "./modules/spoke"
  team_name               = var.team_name
  project_name            = "ecom"
  address_spaces          = var.spoke_address_spaces
  hub_vnet_id             = module.hub.vnet_hub_id
  hub_vnet_name           = module.hub.vnet_hub_name
  hub_resource_group_name = module.hub.resource_group_name
  location                = var.location
  environments            = var.environments
}
