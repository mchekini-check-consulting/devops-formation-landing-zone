terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }


  backend "azurerm" {
    resource_group_name = "rg-tfstate"
    storage_account_name = "sanformationecom"
    container_name = "ecom-formation-tfstate"
    key = "terraform.tfstate"
  }

}

provider "azurerm" {
  features {}

}