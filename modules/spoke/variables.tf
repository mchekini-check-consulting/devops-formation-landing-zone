variable "team_name" {
  type = string
}

variable "project_name" {
  type = string
}

variable "location" {
  type = string
}

variable "environments" {
  type = list(string)
  default = ["dev", "qua", "prod"]
}

variable "address_spaces" {
  type = map(string)
}

variable "hub_vnet_id" {
  type = string
}

variable "hub_vnet_name" {
  type = string
}

variable "hub_resource_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
  default = {}
}

variable "key_vault_id" {
  description = "ID du Key Vault contenant la cle publique SSH"
  type        = string
}

variable "ssh_public_key_secret_name" {
  description = "Nom du secret contenant la cle publique SSH"
  type        = string
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