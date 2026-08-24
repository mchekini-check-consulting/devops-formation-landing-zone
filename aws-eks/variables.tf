variable "team_name" {
  description = "Nom de l'equipe"
  type        = string
  default     = "formation"
}

variable "project_name" {
  description = "Nom du projet"
  type        = string
  default     = "ecom"
}

variable "region" {
  description = "Region AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR du VPC dedie au futur cluster EKS"
  type        = string
  default     = "10.4.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR des subnets publics, un par AZ"
  type        = list(string)
  default     = ["10.4.0.0/20", "10.4.16.0/20", "10.4.32.0/20"]
}

variable "availability_zones" {
  description = "AZ utilisees pour les subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# t3.medium = 2 vCPU / 4 Gio, utilise pour les 3 node groups
variable "system_instance_type" {
  description = "Type d'instance du node group system"
  type        = string
  default     = "t3.medium"
}

variable "apps_instance_type" {
  description = "Type d'instance du node group apps"
  type        = string
  default     = "t3.medium"
}

variable "db_instance_type" {
  description = "Type d'instance du node group db"
  type        = string
  default     = "t3.medium"
}

variable "apps_min_count" {
  description = "Nombre de noeuds du node group apps (fixe pour l'instant, pas d'autoscaling)"
  type        = number
  default     = 3
}

variable "apps_max_count" {
  description = "Reserve pour l'autoscaling (Karpenter) -- pas utilise tant que apps est fixe"
  type        = number
  default     = 6
}

variable "db_node_count" {
  description = "Nombre de noeuds fixes du node group db"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags a appliquer aux ressources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Team      = "formation"
  }
}
