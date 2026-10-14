variable "project_id" {
  description = "GCP project to create resources in"
  type        = string
  default     = "conversionista-se"
}

variable "region" {
  description = "Default region for regional resources"
  type        = string
  default     = "europe-north1"
}

variable "terraform_sa" {
  description = "Service account Terraform impersonates"
  type        = string
  default     = "c-terraform-general@conversionista-se.iam.gserviceaccount.com"
}

variable "state_bucket_name" {
  description = "Globally unique name of the GCS bucket that holds Terraform state"
  type        = string
  default     = "conversionista-se-tfstate-training"
}
