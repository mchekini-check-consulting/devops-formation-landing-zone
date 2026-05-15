variable "team_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  type = string
  default = "10.0.0.0/16"
}

variable "tags" {
  type = map(string)
  default = {}
}

variable "key_vault_name" {
  type = string
}

variable "ssh_public_key_secret_name" {
  type = string
}

variable "ssh_private_key_secret_name" {
  type = string
}

variable "readers_group_object_id" {
  type = string
}

variable "keycloak_vm_size" {
  description = "Gabarit de la VM keycloak"
  type        = string
}

variable "keycloak_vm_admin_username" {
  description = "Utilisateur administrateur des VMs linux"
  type        = string
}

variable "apim_publisher_email" {
  description = "Email du publisher pour Azure API Management"
  type        = string
}
