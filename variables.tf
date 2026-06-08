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


variable "fraud_amount_limit" {
  description = "Montant maximum autorisé par paiement (en euros). Tout montant supérieur est bloqué."
  type        = number
  default     = 5000

  validation {
    condition     = var.fraud_amount_limit > 0
    error_message = "fraud_amount_limit doit être strictement positif."
  }
}

variable "fraud_velocity_max_calls" {
  description = "Nombre maximum de paiements autorisés par utilisateur sur la fenêtre de temps."
  type        = number
  default     = 5

  validation {
    condition     = var.fraud_velocity_max_calls >= 1
    error_message = "fraud_velocity_max_calls doit être >= 1."
  }
}

variable "fraud_velocity_window_seconds" {
  description = "Fenêtre de temps (en secondes) pour la règle de vélocité. Défaut : 600 s (10 min)."
  type        = number
  default     = 600

  validation {
    condition     = var.fraud_velocity_window_seconds > 0
    error_message = "fraud_velocity_window_seconds doit être strictement positif."
  }
}

variable "fraud_blacklisted_ips" {
  description = "Liste des IPs blacklistées. Transmise à la Function App via app_settings."
  type        = list(string)
  default     = []
}

variable "apim_allowed_origins" {
  description = "Liste des origines CORS autorisées sur la Function App (typiquement l'URL de l'APIM)."
  type        = list(string)
  default     = ["*"]
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
