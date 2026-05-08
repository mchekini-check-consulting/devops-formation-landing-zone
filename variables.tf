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

variable "vm_size" {
  description = "Gabarit des VMs front et back"
  type        = string
  default     = "Standard_B2ts_v2"
}

variable "vm_count" {
  description = "Nombre de VMs par service"
  type = object({
    front = number
    back  = number
  })
  default = {
    front = 1
    back  = 1
  }

  validation {
    condition     = var.vm_count.front >= 0 && var.vm_count.back >= 0
    error_message = "vm_count.front et vm_count.back doivent etre superieurs ou egaux a 0."
  }
}

variable "vm_environments" {
  description = "Environnements cible pour le provisionning des VMs"
  type        = list(string)
  default     = ["dev"]
}

variable "vm_admin_username" {
  description = "Utilisateur administrateur des VMs linux"
  type        = string
  default     = "azureuser"
}