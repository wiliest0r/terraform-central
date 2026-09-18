variable "project_id" {
  description = "Target GCP Project ID (injected from workspace variable)"
  type        = string
}

variable "region" {
  description = "Target GCP Region for cloud resources"
  type        = string
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
  description = "Zonal location for GKE cluster"
  type        = string
}

variable "gke_machine_type" {
  description = "Compute Engine machine type for GKE node pool"
  type        = string
  default     = "e2-medium"
}

variable "gke_spot_nodes" {
  description = "Enable Spot VMs for GKE worker nodes (cost optimization for dev/test; false for production high availability)"
  type        = bool
  default     = false
}
