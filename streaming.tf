# ==============================================================================
# Event Streaming & Lakehouse Pipeline (Pub/Sub & GCS Parquet Lakehouse)
# ==============================================================================

data "google_project" "current" {
  project_id = var.project_id
}

# 1. Cloud Storage Lakehouse Bucket for Parquet/Avro Databricks & Spark ingestion
resource "google_storage_bucket" "lakehouse" {
  name                        = "playtests-beacon-lakehouse-${var.environment}"
  location                    = var.region
  force_destroy               = var.environment == "dev" ? true : false
  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = var.environment == "dev" ? 7 : 90
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels
}

# Grant GCP Pub/Sub Service Agent permission to write files to Lakehouse bucket
resource "google_storage_bucket_iam_member" "pubsub_gcs_admin" {
  bucket = google_storage_bucket.lakehouse.name
  role   = "roles/storage.admin"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# 2. Dead Letter Queue Pub/Sub Topic for unprocessable events
resource "google_pubsub_topic" "beacon_events_dlq" {
  name   = "beacon-events-dlq-${var.environment}"
  labels = local.common_labels
}

# 3. Primary Message Streaming Bus Pub/Sub Topic
resource "google_pubsub_topic" "beacon_events" {
  name   = "beacon-events-${var.environment}"
  labels = local.common_labels
}

# Grant publisher & viewer role to Beacon Runtime Service Account (used by Vector sidecar)
resource "google_pubsub_topic_iam_member" "runtime_publisher" {
  topic  = google_pubsub_topic.beacon_events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.beacon_runtime.email}"
}

resource "google_pubsub_topic_iam_member" "runtime_viewer" {
  topic  = google_pubsub_topic.beacon_events.name
  role   = "roles/pubsub.viewer"
  member = "serviceAccount:${google_service_account.beacon_runtime.email}"
}

# 4. Native Pub/Sub to Cloud Storage Subscription (Lakehouse Sink)
resource "google_pubsub_subscription" "lakehouse_sink" {
  name  = "beacon-events-lakehouse-${var.environment}"
  topic = google_pubsub_topic.beacon_events.id

  cloud_storage_config {
    bucket          = google_storage_bucket.lakehouse.name
    filename_prefix = "events/year=%Y/month=%m/day=%d/hour=%H/"
    filename_suffix = ".json"
    max_duration    = "300s"
    max_bytes       = 10485760 # 10MB micro-batches
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.beacon_events_dlq.id
    max_delivery_attempts = 5
  }

  labels = local.common_labels

  depends_on = [
    google_storage_bucket_iam_member.pubsub_gcs_admin
  ]
}
