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