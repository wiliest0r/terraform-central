variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "playtests-beacon-dev"
}

variable "region" {
  description = "GCP Region for cloud resources"
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Target deployment environment (dev, stage, prod)"
  type        = string
}

variable "app_version" {
  description = "Application semver release"
  type        = string
  default     = "0.1.0"
}

variable "git_sha" {
  description = "Git commit hash"
  type        = string
  default     = "initial"
}

variable "beacon_image" {
  description = "Container image for Beacon server"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "enable_gke" {
  description = "Whether to provision GKE cluster and deploy Kubernetes manifests"
  type        = bool
  default     = true
}

variable "gke_zone" {
  description = "Zonal location for single-zone GKE cluster (Free Tier eligible)"
  type        = string
  default     = "europe-west1-b"
}

variable "gke_machine_type" {
  description = "Compute Engine machine type for GKE node pool (cost-optimized minimal compute)"
  type        = string
  default     = "e2-small"
}
