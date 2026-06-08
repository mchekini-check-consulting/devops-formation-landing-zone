variable "team_name" {
  description = "Nom de l'équipe — utilisé dans le nommage des ressources"
  type        = string
}

variable "location" {
  description = "Région Azure"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group dans lequel créer les ressources Velero"
  type        = string
}

variable "aks_oidc_issuer_url" {
  description = "URL de l'OIDC Issuer du cluster AKS (requis pour le Federated Identity Credential)"
  type        = string
}

variable "tags" {
  description = "Tags à appliquer à toutes les ressources"
  type        = map(string)
  default     = {}
}