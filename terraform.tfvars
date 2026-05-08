team_name = "formation"
location  = "francecentral"

key_vault_name              = "kv-formation-security"
ssh_public_key_secret_name  = "vm-admin-ssh-public-key"
ssh_private_key_secret_name = "vm-admin-ssh-private-key"

vm_size = "Standard_B2ts_v2"

vm_count = {
  front = 1
  back  = 1
}

vm_environments = ["dev"]