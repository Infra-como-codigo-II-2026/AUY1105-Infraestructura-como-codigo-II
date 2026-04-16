terraform {
  required_version = ">= 1.0.0" # Esto acepta cualquier versión mayor o igual a la 1.0.0

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Es recomendable también fijar la versión del proveedor
    }
  }
}

provider "aws" {
  region = "us-east-1"
}