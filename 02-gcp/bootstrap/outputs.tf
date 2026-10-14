output "state_bucket" {
  description = "Use this as `bucket` in the gcs backend of other configs"
  value       = google_storage_bucket.tfstate.name
}
