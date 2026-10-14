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

variable "source_dataset" {
  description = "Dataset holding the theLook tables to read from"
  type        = string
  default     = "thelook_raw"
}

variable "dataset_id" {
  description = "Dataset the scheduled query writes into"
  type        = string
  default     = "tf_training_thelook"
}
