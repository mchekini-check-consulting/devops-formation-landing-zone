module "hub" {
  source        = "./modules/hub"
  team_name     = var.team_name
  location      = var.location
  address_space = var.hub_address_space

  key_vault_name             = var.key_vault_name
  ssh_public_key_secret_name = var.ssh_public_key_secret_name
  ssh_private_key_secret_name = var.ssh_private_key_secret_name
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
  vm_count          = var.vm_count
  vm_environments   = var.vm_environments
  vm_admin_username = var.vm_admin_username
  
}

