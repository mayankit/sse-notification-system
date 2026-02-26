#######################################################################
# Terraform Provider Requirements
# Multi-cloud provider configuration for monitoring module
#######################################################################

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    # AWS Provider (optional - enabled via aws_enabled variable)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws]
    }

    # GCP Provider (optional - enabled via gcp_enabled variable)
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
      configuration_aliases = [google]
    }

    # Azure Provider (optional - enabled via azure_enabled variable)
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
      configuration_aliases = [azurerm]
    }
  }
}
