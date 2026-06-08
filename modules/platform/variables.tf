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



variable "velero_storage_account" {
  description = "Nom du Storage Account Azure Blob pour les backups Velero"
  type        = string
}

variable "velero_storage_container" {
  description = "Nom du container Blob pour les backups Velero"
  type        = string
}

variable "velero_resource_group" {
  description = "Resource Group contenant le Storage Account Velero"
  type        = string
}

variable "velero_subscription_id" {
  description = "ID de la subscription Azure (requis par le plugin Velero for Azure)"
  type        = string
}

variable "velero_uami_client_id" {
  description = "Client ID de l'UAMI Velero (annotation Workload Identity sur le ServiceAccount K8s)"
  type        = string
}

variable "key_vault_id" {
  description = "ID du Key Vault hub pour stocker les secrets SonarQube"
  type        = string
}

variable "sonarqube_chart_version" {
  description = "Version du chart Helm SonarQube (SonarSource). Vérifier la dernière version : helm search repo sonarqube/sonarqube"
  type        = string
  default     = "2026.3.1"
}
