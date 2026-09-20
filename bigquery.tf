# ==============================================================================
# BigQuery Multi-Tenant Analytics Engine & SQL Ingestion Layer
# ==============================================================================

# 1. Analytical BigQuery Dataset
resource "google_bigquery_dataset" "beacon_analytics" {
  dataset_id                  = "beacon_analytics_${var.environment}"
  friendly_name               = "Beacon Telemetry Analytics (${var.environment})"
  description                 = "Multi-tenant event analytics and AdTech/CRM attribution dataset"
  location                    = var.region
  default_table_expiration_ms = var.environment == "dev" ? 1209600000 : null # 14 days in dev (FinOps)

  labels = local.common_labels
}

# 2. Ingested Events BigQuery Table (Day Partitioned & Multi-Tenant Clustered)
resource "google_bigquery_table" "events_raw" {
  dataset_id          = google_bigquery_dataset.beacon_analytics.dataset_id
  table_id            = "events_raw"
  deletion_protection = var.environment == "prod" ? true : false

  time_partitioning {
    type  = "DAY"
    field = "server_timestamp"
  }

  clustering = ["account_id", "event_name", "session_id"]

  schema = file("${path.module}/schemas/events_schema.json")
  labels = local.common_labels
}

# 3. Grant Pub/Sub Service Agent BigQuery dataEditor & viewer permissions
resource "google_project_iam_member" "pubsub_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "pubsub_bigquery_viewer" {
  project = var.project_id
  role    = "roles/bigquery.metadataViewer"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# 4. Native Pub/Sub to BigQuery Subscription (Real-time Streaming Ingestion)
resource "google_pubsub_subscription" "bigquery_sink" {
  name  = "beacon-events-bigquery-${var.environment}"
  topic = google_pubsub_topic.beacon_events.id

  enable_message_ordering = true

  bigquery_config {
    table               = "${var.project_id}:${google_bigquery_dataset.beacon_analytics.dataset_id}.${google_bigquery_table.events_raw.table_id}"
    use_table_schema    = true
    use_topic_schema    = false
    drop_unknown_fields = true
    write_metadata      = true
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.beacon_events_dlq.id
    max_delivery_attempts = 5
  }

  labels = local.common_labels

  depends_on = [
    google_project_iam_member.pubsub_bigquery_editor,
    google_project_iam_member.pubsub_bigquery_viewer,
    google_bigquery_table.events_raw
  ]
}

# 5. BigLake / External Table over GCS Lakehouse Parquet/JSON
resource "google_bigquery_table" "events_lakehouse" {
  dataset_id          = google_bigquery_dataset.beacon_analytics.dataset_id
  table_id            = "events_lakehouse"
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "NEWLINE_DELIMITED_JSON"
    source_uris = [
      "gs://${google_storage_bucket.lakehouse.name}/events/*"
    ]
  }

  labels = local.common_labels
}

# 6. Analytical SQL Views
resource "google_bigquery_table" "view_daily_active_users" {
  dataset_id          = google_bigquery_dataset.beacon_analytics.dataset_id
  table_id            = "v_daily_active_users"
  deletion_protection = false

  view {
    query          = <<-SQL
      SELECT
        DATE(server_timestamp) AS event_date,
        account_id,
        COALESCE(tenant_id, account_id) AS tenant_id,
        COUNT(DISTINCT visitor_id) AS unique_visitors,
        COUNT(DISTINCT session_id) AS unique_sessions,
        COUNT(1) AS total_events,
        COUNTIF(is_conversion = true) AS total_conversions,
        COUNTIF(has_ad_attribution = true) AS attributed_events
      FROM `${var.project_id}.${google_bigquery_dataset.beacon_analytics.dataset_id}.events_raw`
      GROUP BY 1, 2, 3
    SQL
    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.events_raw]
}

resource "google_bigquery_table" "view_adtech_performance" {
  dataset_id          = google_bigquery_dataset.beacon_analytics.dataset_id
  table_id            = "v_adtech_performance"
  deletion_protection = false

  view {
    query          = <<-SQL
      SELECT
        DATE(server_timestamp) AS event_date,
        account_id,
        COALESCE(tenant_id, account_id) AS tenant_id,
        COALESCE(utm_source, 'direct') AS utm_source,
        COALESCE(utm_campaign, 'none') AS utm_campaign,
        COUNT(1) AS total_events,
        COUNTIF(gclid IS NOT NULL) AS gclid_events,
        COUNTIF(fbclid IS NOT NULL) AS fbclid_events,
        COUNTIF(is_conversion = true) AS conversions
      FROM `${var.project_id}.${google_bigquery_dataset.beacon_analytics.dataset_id}.events_raw`
      GROUP BY 1, 2, 3, 4, 5
    SQL
    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.events_raw]
}
