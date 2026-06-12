terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
}


  backend "azurerm" {
    resource_group_name = "rg-tfstate"
    storage_account_name = "sanecomformation"
    container_name = "ecom-formation-tfstate"
    key = "terraform.tfstate"
  }

}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}

provider "azuread" {}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}


