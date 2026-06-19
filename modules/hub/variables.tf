variable "team_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  type    = string
  default = "10.0.0.0/16"
}

variable "tags" {
  type    = map(string)
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

variable "apim_publisher_email" {
  description = "Email du publisher pour Azure API Management"
  type        = string
}

variable "frontend_public_ip" {
  description = "IP publique du frontend (pour CORS APIM) - sera remplacee par l'IP AKS"
  type        = string
  default     = ""
}

variable "backend_vm_ip" {
  description = "IP du backend (pour routage APIM) - sera remplacee par l'IP AKS"
  type        = string
  default     = ""
}

variable "payment_lb_ip" {
  description = "IP du service payment (pour routage APIM) - sera remplacee par l'IP AKS"
  type        = string
  default     = ""
}

variable "fraud_check_function_urls" {
  description = "value"
  type        = map(string)
  default     = {}
}

variable "catalog_rate_limit" {
  description = "Nombre maximum de requêtes par minute par utilisateur sur le microservice catalog."
  type        = number
  default     = 300
}

variable "order_rate_limit" {
  description = "Nombre maximum de requêtes par minute par utilisateur sur le microservice order."
  type        = number
  default     = 60
}

variable "payment_rate_limit" {
  description = "Nombre maximum de requêtes par minute par utilisateur sur le microservice payment."
  type        = number
  default     = 20
}