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
  type        = list(string)
  default     = ["dev"]
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


variable "readers_group_object_id" {
  description = "Object ID du groupe Azure AD qui doit accéder aux secrets"
  type        = string
}

variable "apim_publisher_email" {
  description = "Email du publisher pour Azure API Management"
  type        = string
  default     = "devops@formation.com"
}


variable "catalog_rate_limit" {
  description = "Nombre maximum de requêtes par minute par utilisateur sur le microservice catalog."
  type        = number
  default     = 300

  validation {
    condition     = var.catalog_rate_limit >= 1
    error_message = "catalog_rate_limit doit être >= 1."
  }
}

variable "order_rate_limit" {
  description = "Nombre maximum de requêtes par minute par utilisateur sur le microservice order."
  type        = number
  default     = 60

  validation {
    condition     = var.order_rate_limit >= 1
    error_message = "order_rate_limit doit être >= 1."
  }
}

variable "payment_rate_limit" {
  description = "Nombre maximum de requêtes par minute par utilisateur sur le microservice payment."
  type        = number
  default     = 20

  validation {
    condition     = var.payment_rate_limit >= 1
    error_message = "payment_rate_limit doit être >= 1."
  }
}
