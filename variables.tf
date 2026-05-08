variable "team_name" {
  description = "Nom de l'équipe"
  type        = string
}

variable "location" {
  description = "Région Azure"
  type        = string
  default     = "francecentral"
}

variable "environments" {
  description = "Liste des environnements"
  type = list(string)
  default = ["dev", "qua", "prod"]
}

variable "hub_address_space" {
  type    = string
  default = "10.0.0.0/16"
}

variable "spoke_address_spaces" {
  type = map(string)
  default = {
    dev  = "10.1.0.0/16"
    qua  = "10.2.0.0/16"
    prod = "10.3.0.0/16"
  }
}

variable "key_vault_name" {
  description = "Nom du Key Vault"
  type        = string
}

variable "ssh_public_key_secret_name" {
  description = "Nom du secret contenant la cle publique SSH"
  type        = string
  default     = "vm-admin-ssh-public-key"
}

variable "ssh_private_key_secret_name" {
  description = "Nom du secret contenant la cle privee SSH"
  type        = string
  default     = "vm-admin-ssh-private-key"
}