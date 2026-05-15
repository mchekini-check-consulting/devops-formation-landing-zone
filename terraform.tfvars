team_name = "formation"
location  = "francecentral"

key_vault_name              = "kv-formation-security"
ssh_public_key_secret_name  = "vm-admin-ssh-public-key"
ssh_private_key_secret_name = "vm-admin-ssh-private-key"
readers_group_object_id   = "c8af8cea-7b6a-4ca4-b8a2-2443f9ed6365"

vm_size = "Standard_B2ts_v2"

vm_count = {
  front = 1
  back  = 1
}

vm_environments = ["dev"]

keycloak_vm_admin_username = "azureuser"
keycloak_vm_size = "Standard_B2s"