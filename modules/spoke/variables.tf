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

variable "apim_subnet_id" {
  description = "ID du subnet APIM du Hub."
  type        = string
}

variable "apim_public_ip" {
  description = "IP publique de l'APIM (pour les restrictions d'accès Function App)."
  type        = string
}
