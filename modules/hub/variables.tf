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

variable "cicd_sp_object_id" {
  description = "Object ID du Service Principal pipeline CI/CD (accès secrets Key Vault)"
  type        = string
}

variable "terraform_runner_object_id" {
  description = "Object ID du compte/SP qui exécute Terraform en local"
  type        = string
}

variable "devops_sp_object_id" {
  description = "Object ID du Service Principal DevOps (accès clés et secrets Key Vault)"
  type        = string
}

