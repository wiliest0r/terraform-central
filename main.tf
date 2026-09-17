provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  service_name = "beacon-server-${var.environment}"
  repo_name    = "beacon-repo-${var.environment}"
  runtime_sa   = "sa-beacon-runtime-${var.environment}"

  scaling_config = {
    dev = {
      cpu           = "1"
      memory        = "512Mi"
      min_instances = 0
      max_instances = 2
    }
    stage = {
      cpu           = "1"
      memory        = "512Mi"
      min_instances = 0
      max_instances = 5
    }
    prod = {
      cpu           = "1"
      memory        = "1Gi"
      min_instances = 1
      max_instances = 20
    }
  }

  current_scaling = local.scaling_config[var.environment]

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

# Isolated Runtime Service Account (Zero Trust Principle)
resource "google_service_account" "beacon_runtime" {
  account_id   = local.runtime_sa
  display_name = "Beacon Runtime Service Account (${var.environment})"
  description  = "Dedicated minimal privilege service account executing Beacon Cloud Run container"
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

# Cloud Run Service for Beacon Telemetry Server
resource "google_cloud_run_v2_service" "beacon_server" {
  name                = local.service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = var.environment == "dev" ? false : true

  template {
    service_account = google_service_account.beacon_runtime.email

    containers {
      image = var.beacon_image

      ports {
        container_port = 80
      }

      resources {
        limits = {
          cpu    = local.current_scaling.cpu
          memory = local.current_scaling.memory
        }
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "APP_VERSION"
        value = var.app_version
      }
    }

    scaling {
      min_instance_count = local.current_scaling.min_instances
      max_instance_count = local.current_scaling.max_instances
    }
  }

  labels = local.common_labels
}

# Public access policy for Beacon telemetry ingestion endpoint
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = google_cloud_run_v2_service.beacon_server.project
  location = google_cloud_run_v2_service.beacon_server.location
  name     = google_cloud_run_v2_service.beacon_server.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
