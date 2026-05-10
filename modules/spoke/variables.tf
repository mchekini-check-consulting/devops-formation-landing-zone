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

variable "acr_id" {
  description = "ID de l'ACR du hub pour les role assignments"
  type        = string
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

variable "github_pat" {
  description = "GitHub Personal Access Token pour le repo start-up-scritps"
  type        = string
  sensitive   = true
}

variable "postgres_admin_login" {
  type        = string
  description = "Admin username for PostgreSQL"
  sensitive   = true
  default     = "formation"
}

variable "postgres_admin_password" {
  type        = string
  description = "Admin password for PostgreSQL"
  sensitive   = true
  default     = "test"
}

variable "postgres_server_name" {
  type        = string
  description = "PostgreSQL flexible server name prefix"
  default     = "data-pgsql"
}

variable "postgres_sku_name" {
  type        = string
  description = "SKU for PostgreSQL flexible server"
  default     = "B_Standard_B1ms"

  validation {
    condition     = can(regex("^(B|GP|MO)_", var.postgres_sku_name))
    error_message = "postgres_sku_name must start with B_, GP_, or MO_ for Flexible Server."
  }
}

variable "postgres_version" {
  type        = string
  description = "PostgreSQL version"
  default     = "15"
}

variable "postgres_storage_mb" {
  type        = number
  description = "Storage size in MB for PostgreSQL"
  default     = 32768
}

variable "postgres_backup_retention_days" {
  type        = number
  description = "Backup retention in days"
  default     = 7
}

variable "postgres_databases" {
  type = map(object({
    charset   = string
    collation = string
  }))
  description = "Map of databases to create"
  default = {
    "order" = {
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
    "payment" = {
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
    "catalogue" = {
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  }
}