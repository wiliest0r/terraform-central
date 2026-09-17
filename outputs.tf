output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP Region"
  value       = var.region
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "cloud_run_service_name" {
  description = "Name of the provisioned Cloud Run service"
  value       = google_cloud_run_v2_service.beacon_server.name
}

output "cloud_run_service_url" {
  description = "Direct HTTPS URI of the Beacon Cloud Run service"
  value       = google_cloud_run_v2_service.beacon_server.uri
}

output "artifact_registry_repository_id" {
  description = "ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.beacon_repo.repository_id
}

output "artifact_registry_repository_url" {
  description = "Full URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.beacon_repo.repository_id}"
}

output "runtime_service_account" {
  description = "Dedicated runtime service account for Cloud Run container"
  value       = google_service_account.beacon_runtime.email
}

output "terraform_service_account" {
  description = "Service account used by HCP Terraform"
  value       = "sa-terraform-executor@${var.project_id}.iam.gserviceaccount.com"
}

output "gha_deployer_service_account" {
  description = "Service account used by GitHub Actions"
  value       = "sa-gha-deployer@${var.project_id}.iam.gserviceaccount.com"
}

output "tfc_workload_identity_provider" {
  description = "Workload Identity Provider for HCP Terraform"
  value       = "projects/847948858817/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
}

output "github_workload_identity_provider" {
  description = "Workload Identity Provider for GitHub Actions"
  value       = "projects/847948858817/locations/global/workloadIdentityPools/tfc-pool/providers/github-provider"
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
