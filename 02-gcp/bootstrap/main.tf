terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7"
    }
  }

  # No backend block: this config keeps its state locally.
  # It creates the bucket that every other config stores its state in.
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Run every API call as the Terraform service account instead of as you.
  impersonate_service_account = var.terraform_sa
}

resource "google_storage_bucket" "tfstate" {
  name     = var.state_bucket_name
  location = "EU"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Keep old state versions so a bad apply can be rolled back.
  versioning {
    enabled = true
  }

  # Demo only: lets `terraform destroy` delete the bucket even when it holds state files.
  force_destroy = true
}
