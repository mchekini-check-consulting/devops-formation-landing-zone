module "hub" {
  source        = "./modules/hub"
  team_name     = var.team_name
  location      = var.location
  address_space = var.hub_address_space

  key_vault_name             = var.key_vault_name
  ssh_public_key_secret_name = var.ssh_public_key_secret_name
  ssh_private_key_secret_name = var.ssh_private_key_secret_name
  readers_group_object_id = var.readers_group_object_id
  apim_publisher_email = var.apim_publisher_email
  keycloak_vm_admin_username = var.keycloak_vm_admin_username
  keycloak_vm_size = var.keycloak_vm_size

  frontend_public_ip = "20.43.59.226"
  backend_vm_ip      = "10.1.1.4"
  payment_lb_ip      = "10.1.1.10"

  fraud_check_function_urls = module.spoke.fraud_check_function_urls

  catalog_rate_limit = var.catalog_rate_limit
  order_rate_limit   = var.order_rate_limit
  payment_rate_limit = var.payment_rate_limit

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
    managed_by  = "terraform"
    team        = var.team_name
    component   = "backup"
  }
}

module "platform" {
  source       = "./modules/platform"
  team_name    = var.team_name
  project_name    = "ecom"
  location        = var.location
  oidc_issuer_url = module.aks.oidc_issuer_url

  velero_storage_account   = module.velero.storage_account_name
  velero_storage_container = module.velero.storage_container_name
  velero_resource_group    = module.velero.resource_group_name
  velero_subscription_id   = module.velero.subscription_id
  velero_uami_client_id    = module.velero.uami_client_id
}

module "spoke" {

  source = "./modules/spoke"
  team_name = var.team_name
  project_name = "ecom"
  address_spaces = var.spoke_address_spaces
  hub_vnet_id = module.hub.vnet_hub_id
  hub_vnet_name = module.hub.vnet_hub_name
  hub_resource_group_name = module.hub.resource_group_name
  location = var.location
  environments = var.environments

  apim_subnet_id  = module.hub.apim_subnet_id
  apim_public_ip  = module.hub.apim_public_ip
}

