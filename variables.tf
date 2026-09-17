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
  description = "Deployment environment (dev, stage, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "The environment must be one of: dev, stage, prod."
  }
}

variable "app_version" {
  description = "Application version string"
  type        = string
  default     = "0.1.0"
}

variable "git_sha" {
  description = "Git commit SHA"
  type        = string
  default     = "initial"
}

variable "beacon_image" {
  description = "Container image for Cloud Run service"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}
