provider "google" {
  project = var.project_id
  region  = var.region
}

# Artifact Registry Repository for Docker & WASM OCI images
resource "google_artifact_registry_repository" "beacon_repo" {
  location      = var.region
  repository_id = var.artifact_repo_name
  description   = "Docker and WASM OCI repository for Beacon server and analytics assets"
  format        = "DOCKER"

  labels = {
    environment = var.environment
    managed_by  = "terraform"
    repository  = "terraform-central"
  }
}

# Cloud Run Service for Beacon Telemetry Server
resource "google_cloud_run_v2_service" "beacon_server" {
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = var.beacon_image

      ports {
        container_port = 80
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
    repository  = "terraform-central"
  }
}

# Public access policy for Beacon telemetry ingestion endpoint
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = google_cloud_run_v2_service.beacon_server.project
  location = google_cloud_run_v2_service.beacon_server.location
  name     = google_cloud_run_v2_service.beacon_server.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
