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

  front_vm_identity_principal_ids = values(module.spoke.keyvault_identity_principal_ids)

  frontend_public_ip = module.spoke.frontend_public_ip["dev"]
  backend_vm_ip      = module.spoke.backend_vm_ip["dev"]
  payment_lb_ip = module.spoke.payment_lb_ip["dev"]
  fraud_check_function_urls = module.spoke.fraud_check_function_urls

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

  key_vault_id               = module.hub.key_vault_id
  ssh_public_key_secret_name = var.ssh_public_key_secret_name

  vm_size           = var.vm_size
  vm_size_back_01   = var.vm_size_back_01
  vm_count          = var.vm_count
  vm_environments   = var.vm_environments
  vm_admin_username = var.vm_admin_username

  acr_id = module.hub.acr_id

  apim_subnet_id  = module.hub.apim_subnet_id
  apim_public_ip  = module.hub.apim_public_ip
}

