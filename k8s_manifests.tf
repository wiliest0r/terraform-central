# ==============================================================================
# Kubernetes Provider & Declarative Application Manifests
# ==============================================================================

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = var.enable_gke && length(google_container_cluster.primary) > 0 ? "https://${google_container_cluster.primary[0].endpoint}" : "https://127.0.0.1"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = var.enable_gke && length(google_container_cluster.primary) > 0 ? base64decode(google_container_cluster.primary[0].master_auth[0].cluster_ca_certificate) : ""
}

# Dedicated namespace for Beacon application
resource "kubernetes_namespace_v1" "beacon" {
  count = var.enable_gke ? 1 : 0

  metadata {
    name   = "beacon"
    labels = local.common_labels
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Kubernetes Service Account bound to GCP Runtime SA via Workload Identity
resource "kubernetes_service_account_v1" "beacon" {
  count = var.enable_gke ? 1 : 0

  metadata {
    name      = "beacon-sa"
    namespace = kubernetes_namespace_v1.beacon[0].metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.beacon_runtime.email
    }
    labels = local.common_labels
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Workload Identity binding allowing beacon-sa in K8s to impersonate GCP beacon_runtime SA
resource "google_service_account_iam_member" "runtime_workload_identity" {
  service_account_id = google_service_account.beacon_runtime.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[beacon/beacon-sa]"
}

# Vector Sidecar Configuration Map
resource "kubernetes_config_map_v1" "vector_config" {
  count = var.enable_gke ? 1 : 0

  metadata {
    name      = "vector-config"
    namespace = kubernetes_namespace_v1.beacon[0].metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "vector.toml" = <<-EOT
      data_dir = "/var/lib/vector"

      [sources.beacon_logs]
      type = "file"
      include = ["/var/log/beacon/events.log"]
      read_from = "beginning"

      [sources.vector_metrics]
      type = "internal_metrics"

      [transforms.parse_events]
      type = "remap"
      inputs = ["beacon_logs"]
      source = '''
      parsed, err = parse_json(.message)
      if err != null {
        abort
      }
      . = parsed
      '''

      [sinks.pubsub_events]
      type = "gcp_pubsub"
      inputs = ["parse_events"]
      project = "${var.project_id}"
      topic = "${google_pubsub_topic.beacon_events.name}"
      encoding.codec = "json"

      [sinks.pubsub_events.buffer]
      type = "disk"
      max_size = 536870912
      when_full = "block"

      [sinks.prometheus]
      type = "prometheus_exporter"
      inputs = ["vector_metrics"]
      address = "0.0.0.0:9090"
    EOT
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# RuntimeClass for Spin WebAssembly runtime (matches edge/k3s specification)
resource "kubernetes_runtime_class_v1" "wasm_spin" {
  count = var.enable_gke ? 1 : 0

  metadata {
    name = "wasm-spin"
  }

  handler = "spin"

  depends_on = [google_container_node_pool.primary_nodes]
}

# Declarative Beacon Server Deployment with Vector Ingestion Sidecar
resource "kubernetes_deployment_v1" "beacon_server" {
  count = var.enable_gke ? 1 : 0

  metadata {
    name      = "beacon-server"
    namespace = kubernetes_namespace_v1.beacon[0].metadata[0].name
    labels    = local.common_labels
  }

  spec {
    replicas = 1

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "0"
        max_unavailable = "1"
      }
    }

    selector {
      match_labels = {
        app = "beacon-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "beacon-server"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9090"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.beacon[0].metadata[0].name

        volume {
          name = "beacon-logs"
          empty_dir {}
        }

        volume {
          name = "vector-buffer"
          empty_dir {}
        }

        volume {
          name = "vector-config"
          config_map {
            name = kubernetes_config_map_v1.vector_config[0].metadata[0].name
          }
        }

        container {
          name  = "beacon-server"
          image = var.beacon_image

          port {
            name           = "http"
            container_port = 8080
          }

          env {
            name  = "PORT"
            value = "8080"
          }

          env {
            name  = "ENVIRONMENT"
            value = var.environment
          }

          env {
            name  = "APP_VERSION"
            value = var.app_version
          }

          volume_mount {
            name       = "beacon-logs"
            mount_path = "/var/log/beacon"
          }

          resources {
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }

        container {
          name  = "vector"
          image = "timberio/vector:0.43.0-alpine"

          args = ["--config", "/etc/vector/vector.toml"]

          port {
            name           = "metrics"
            container_port = 9090
          }

          volume_mount {
            name       = "vector-config"
            mount_path = "/etc/vector"
            read_only  = true
          }

          volume_mount {
            name       = "beacon-logs"
            mount_path = "/var/log/beacon"
            read_only  = true
          }

          volume_mount {
            name       = "vector-buffer"
            mount_path = "/var/lib/vector"
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "20m"
              memory = "32Mi"
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec[0].template[0].spec[0].container[0].image
    ]
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# External LoadBalancer Service
resource "kubernetes_service_v1" "beacon_service" {
  count = var.enable_gke ? 1 : 0

  metadata {
    name      = "beacon-service"
    namespace = kubernetes_namespace_v1.beacon[0].metadata[0].name
    labels    = local.common_labels
  }

  spec {
    selector = {
      app = "beacon-server"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [google_container_node_pool.primary_nodes]
}
