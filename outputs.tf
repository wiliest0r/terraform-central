output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

output "artifact_registry_repository" {
  description = "GAR repository ID for Beacon container images"
  value       = google_artifact_registry_repository.beacon_repo.id
}

output "artifact_registry_url" {
  description = "GAR repository URL prefix"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.beacon_repo.repository_id}"
}

output "beacon_runtime_service_account" {
  description = "Runtime Service Account email for Beacon workloads"
  value       = google_service_account.beacon_runtime.email
}

output "github_actions_workload_identity_provider" {
  description = "Workload Identity Provider for GitHub Actions"
  value       = "projects/${var.project_id}/locations/global/workloadIdentityPools/tfc-pool/providers/github-provider"
}

output "tfc_workload_identity_provider" {
  description = "Workload Identity Provider for HCP Terraform"
  value       = "projects/${var.project_id}/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
}

# GKE Cluster outputs (present when enable_gke is true)
output "gke_cluster_name" {
  description = "Name of the GKE cluster"
  value       = var.enable_gke && length(google_container_cluster.primary) > 0 ? google_container_cluster.primary[0].name : null
}

output "gke_cluster_endpoint" {
  description = "Master endpoint of the GKE cluster"
  value       = var.enable_gke && length(google_container_cluster.primary) > 0 ? google_container_cluster.primary[0].endpoint : null
}

output "gke_service_load_balancer_ip" {
  description = "Public Load Balancer IP of the Beacon Kubernetes service"
  value       = var.enable_gke && length(kubernetes_service_v1.beacon_service) > 0 ? (length(kubernetes_service_v1.beacon_service[0].status[0].load_balancer[0].ingress) > 0 ? kubernetes_service_v1.beacon_service[0].status[0].load_balancer[0].ingress[0].ip : "pending") : null
}

# Streaming & Lakehouse outputs (Stage 3)
output "pubsub_topic_beacon_events" {
  description = "Pub/Sub Primary Topic for Beacon Telemetry Events"
  value       = google_pubsub_topic.beacon_events.id
}

output "pubsub_topic_beacon_events_dlq" {
  description = "Pub/Sub Dead Letter Topic for Beacon Telemetry Events"
  value       = google_pubsub_topic.beacon_events_dlq.id
}

output "gcs_lakehouse_bucket" {
  description = "GCS Lakehouse Bucket for Parquet/Avro Databricks & Spark ingestion"
  value       = google_storage_bucket.lakehouse.url
}

# BigQuery Analytics outputs (Stage 5)
output "bigquery_dataset_id" {
  description = "BigQuery Dataset ID for Beacon Analytics"
  value       = google_bigquery_dataset.beacon_analytics.dataset_id
}

output "bigquery_table_events_raw" {
  description = "BigQuery Ingestion Table ID for raw events"
  value       = google_bigquery_table.events_raw.table_id
}

output "bigquery_table_events_lakehouse" {
  description = "BigQuery External BigLake Table ID over GCS"
  value       = google_bigquery_table.events_lakehouse.table_id
}
