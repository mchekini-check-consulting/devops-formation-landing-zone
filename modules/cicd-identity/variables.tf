variable "team_name" {
  description = "Nom de l'equipe"
  type        = string
}

variable "github_org" {
  description = "Organisation GitHub"
  type        = string
}

variable "github_repositories" {
  description = "Liste des repos GitHub pour lesquels creer des federated credentials"
  type        = list(string)
}

variable "acr_id" {
  description = "ID de l'Azure Container Registry"
  type        = string
}

variable "aks_id" {
  description = "ID du cluster AKS"
  type        = string
}

variable "resource_group_id" {
  description = "ID du resource group devops"
  type        = string
}
