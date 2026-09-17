output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID"
  value       = google_artifact_registry_repository.beacon_repo.repository_id
}

output "artifact_registry_repository_url" {
  description = "Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.beacon_repo.repository_id}"
}

output "cloud_run_service_url" {
  description = "Public URL of the Beacon Cloud Run service"
  value       = google_cloud_run_v2_service.beacon_server.uri
}

output "tfc_workload_identity_provider" {
  description = "WIF Provider resource name for HCP Terraform"
  value       = "projects/847948858817/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
}

output "github_workload_identity_provider" {
  description = "WIF Provider resource name for GitHub Actions"
  value       = "projects/847948858817/locations/global/workloadIdentityPools/tfc-pool/providers/github-provider"
}

output "terraform_service_account" {
  description = "Service account used by HCP Terraform"
  value       = "sa-terraform-executor@playtests-beacon.iam.gserviceaccount.com"
}

output "gha_deployer_service_account" {
  description = "Service account used by GitHub Actions"
  value       = "sa-gha-deployer@playtests-beacon.iam.gserviceaccount.com"
}
