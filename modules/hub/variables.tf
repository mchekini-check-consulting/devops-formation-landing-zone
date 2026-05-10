variable "team_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  type = string
  default = "10.0.0.0/16"
}

variable "tags" {
  type = map(string)
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

variable "github_pat" {
  description = "GitHub Personal Access Token pour le repo start-up-scritps"
  type        = string
  sensitive   = true
}