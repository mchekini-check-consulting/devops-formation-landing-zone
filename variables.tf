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
  type = list(string)
  default = ["dev", "qua", "prod"]
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
