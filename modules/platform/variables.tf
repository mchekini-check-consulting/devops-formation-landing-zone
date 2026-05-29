variable "team_name" {
  description = "Nom de l'equipe"
  type        = string
}

variable "project_name" {
  description = "Nom du projet"
  type        = string
}

variable "location" {
  description = "Region Azure"
  type        = string
  default     = "francecentral"
}

variable "oidc_issuer_url" {
  description = "URL de l'emetteur OIDC du cluster AKS"
  type        = string
}