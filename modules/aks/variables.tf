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

variable "aks_address_space" {
  description = "Address space du VNet AKS"
  type        = string
  default     = "10.4.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR du subnet AKS"
  type        = string
  default     = "10.4.0.0/22"
}

variable "system_vm_size" {
  description = "Taille des VMs du node pool system"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "apps_vm_size" {
  description = "Taille des VMs du node pool apps"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "db_vm_size" {
  description = "Taille des VMs du node pool db"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "apps_min_count" {
  description = "Nombre minimum de noeuds pour le node pool apps"
  type        = number
  default     = 3
}

variable "apps_max_count" {
  description = "Nombre maximum de noeuds pour le node pool apps"
  type        = number
  default     = 6
}

variable "db_node_count" {
  description = "Nombre de noeuds pour le node pool db"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags a appliquer aux ressources"
  type        = map(string)
  default     = {}
}
