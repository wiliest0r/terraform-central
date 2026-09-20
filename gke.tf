# ==============================================================================
# GKE Standard Cluster & Networking (Single-Zone Cost-Optimized for Dev)
# ==============================================================================

# Dedicated VPC for GKE isolation
resource "google_compute_network" "gke_vpc" {
  count                   = var.enable_gke ? 1 : 0
  name                    = "beacon-vpc-${var.environment}"
  auto_create_subnetworks = false
}

# Subnet with secondary ranges for VPC-native Pods & Services
resource "google_compute_subnetwork" "gke_subnet" {
  count                    = var.enable_gke ? 1 : 0
  name                     = "beacon-gke-subnet-${var.environment}"
  ip_cidr_range            = "10.10.0.0/20"
  region                   = var.region
  network                  = google_compute_network.gke_vpc[0].id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

# Least-privilege Service Account for GKE Nodes
resource "google_service_account" "gke_node_sa" {
  count        = var.enable_gke ? 1 : 0
  account_id   = "sa-gke-nodes-${var.environment}"
  display_name = "Beacon GKE Node Service Account (${var.environment})"
  description  = "Dedicated minimal privilege service account for GKE worker nodes"
}

# Minimal IAM roles for GKE nodes
resource "google_project_iam_member" "gke_node_logging" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa[0].email}"
}

resource "google_project_iam_member" "gke_node_metrics" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa[0].email}"
}

resource "google_project_iam_member" "gke_node_monitoring" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_node_sa[0].email}"
}

resource "google_project_iam_member" "gke_node_registry" {
  count   = var.enable_gke ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_node_sa[0].email}"
}

# GKE Standard Cluster (Zonal for 100% Free Tier Management Fee)
resource "google_container_cluster" "primary" {
  count                    = var.enable_gke ? 1 : 0
  name                     = "beacon-gke-${var.environment}"
  location                 = var.gke_zone
  remove_default_node_pool = true
  initial_node_count       = 1
  network                  = google_compute_network.gke_vpc[0].name
  subnetwork               = google_compute_subnetwork.gke_subnet[0].name
  deletion_protection      = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = local.common_labels
}

# Managed Node Pool with configurable compute (Spot for Dev; Reliable On-Demand for Prod)
resource "google_container_node_pool" "primary_nodes" {
  count              = var.enable_gke ? 1 : 0
  name               = "beacon-node-pool-${var.environment}"
  location           = var.gke_zone
  cluster            = google_container_cluster.primary[0].name
  initial_node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.gke_machine_type
    spot            = var.gke_spot_nodes
    disk_type       = "pd-standard"
    disk_size_gb    = 20
    service_account = google_service_account.gke_node_sa[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = local.common_labels
    tags   = ["beacon-gke-node"]
  }
}
