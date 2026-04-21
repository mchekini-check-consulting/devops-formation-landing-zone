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