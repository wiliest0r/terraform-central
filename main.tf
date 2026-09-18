provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  repo_name  = "beacon-repo-${var.environment}"
  runtime_sa = "sa-beacon-runtime-${var.environment}"

  common_labels = {
    organization = "playtests"
    project      = "beacon-analytics"
    managed_by   = "terraform"
    repository   = "terraform-central"
    environment  = var.environment
    component    = "beacon-server"
    app_version  = replace(var.app_version, ".", "-")
    git_sha      = var.git_sha
  }
}

# Isolated Runtime Service Account for GKE Pod Workload Identity
resource "google_service_account" "beacon_runtime" {
  account_id   = local.runtime_sa
  display_name = "Beacon Runtime Service Account (${var.environment})"
  description  = "Dedicated minimal privilege service account for Beacon container workloads"
}

# Grant logging writer to runtime service account
resource "google_project_iam_member" "runtime_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.beacon_runtime.email}"
}

# Allow GHA Deployer SA to act as the runtime SA when deploying revisions
resource "google_service_account_iam_member" "gha_impersonate_runtime" {
  service_account_id = google_service_account.beacon_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:sa-gha-deployer@${var.project_id}.iam.gserviceaccount.com"
}

# Artifact Registry Repository for Docker & WASM OCI images
resource "google_artifact_registry_repository" "beacon_repo" {
  location      = var.region
  repository_id = local.repo_name
  description   = "Docker and WASM OCI repository for Beacon server (${var.environment})"
  format        = "DOCKER"

  docker_config {
    immutable_tags = var.environment == "dev" ? false : true
  }

  labels = local.common_labels
}
