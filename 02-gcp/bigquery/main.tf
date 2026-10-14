terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7"
    }
  }

  # State lives in the bucket created by ../bootstrap.
  # Backend blocks can't use variables, so the values are written out here.
  backend "gcs" {
    bucket                      = "conversionista-se-tfstate-training"
    prefix                      = "02-gcp/bigquery"
    impersonate_service_account = "c-terraform-general@conversionista-se.iam.gserviceaccount.com"
  }
}

provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.terraform_sa
}

# Target dataset. It must be in the same location as the source (thelook_raw is in US).
resource "google_bigquery_dataset" "demo" {
  dataset_id  = var.dataset_id
  location    = "US"
  description = "Terraform training demo: output of the scheduled query"

  # Demo only: lets `terraform destroy` remove the dataset even after the query has written tables.
  delete_contents_on_destroy = true

  labels = {
    managed_by = "terraform"
    purpose    = "training"
  }
}

# Scheduled query (a BigQuery Data Transfer config with data source "scheduled_query").
resource "google_bigquery_data_transfer_config" "daily_order_summary" {
  display_name           = "tf-demo-daily-order-summary"
  location               = google_bigquery_dataset.demo.location
  data_source_id         = "scheduled_query"
  schedule               = "every day 06:00"
  destination_dataset_id = google_bigquery_dataset.demo.dataset_id

  params = {
    destination_table_name_template = "daily_order_summary"
    write_disposition               = "WRITE_TRUNCATE"
    query = templatefile("${path.module}/sql/daily_order_summary.sql", {
      source = "${var.project_id}.${var.source_dataset}"
    })
  }
}
