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

# RuntimeClass for Spin WebAssembly runtime (matches edge/k3s specification)
resource "kubernetes_runtime_class_v1" "wasm_spin" {
  count = var.enable_gke ? 1 : 0

  metadata {
    name = "wasm-spin"
  }

  handler = "spin"

  depends_on = [google_container_node_pool.primary_nodes]
}

# Declarative Beacon Server Deployment
resource "kubernetes_deployment_v1" "beacon_server" {
  count = var.enable_gke ? 1 : 0

  metadata {
    name      = "beacon-server"
    namespace = kubernetes_namespace_v1.beacon[0].metadata[0].name
    labels    = local.common_labels
  }

  spec {
    replicas = 1

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
      }

      spec {
        container {
          name  = "beacon-server"
          image = var.beacon_image

          port {
            name           = "http"
            container_port = 80
          }

          env {
            name  = "ENVIRONMENT"
            value = var.environment
          }

          env {
            name  = "APP_VERSION"
            value = var.app_version
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
      }
    }
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Expose Beacon Server via Google Cloud Network Load Balancer (Public IPv4)
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
      target_port = 80
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment_v1.beacon_server]
}
