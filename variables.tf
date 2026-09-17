variable "project_id" {
  description = "Google Cloud Platform Project ID"
  type        = string
  default     = "playtests-beacon"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Deployment environment (production, staging, development)"
  type        = string
  default     = "production"
}

variable "artifact_repo_name" {
  description = "Artifact Registry repository ID for container and WASM OCI images"
  type        = string
  default     = "beacon-repo"
}

variable "service_name" {
  description = "Cloud Run service name for Beacon server"
  type        = string
  default     = "beacon-server"
}

variable "beacon_image" {
  description = "Container image for Cloud Run service"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}
