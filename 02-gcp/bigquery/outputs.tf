output "dataset" {
  value = "${google_bigquery_dataset.demo.project}.${google_bigquery_dataset.demo.dataset_id}"
}

output "scheduled_query_name" {
  description = "Full resource name of the transfer config"
  value       = google_bigquery_data_transfer_config.daily_order_summary.name
}
