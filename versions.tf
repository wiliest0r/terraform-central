terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "PlayTests"

    workspaces {
      tags = ["beacon-analytics"]
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
