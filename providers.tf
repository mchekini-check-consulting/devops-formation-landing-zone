terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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
}
