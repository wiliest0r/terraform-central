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
        COUNT(DISTINCT COALESCE(device_id, visitor_id)) AS active_devices,
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

# 7. Multi-Touch Attribution & Campaign Performance Marts
resource "google_bigquery_table" "view_attribution_first_last_touch" {
  dataset_id          = google_bigquery_dataset.beacon_analytics.dataset_id
  table_id            = "v_attribution_first_last_touch"
  deletion_protection = false

  view {
    query          = <<-SQL
      WITH ordered_sessions AS (
        SELECT
          account_id,
          COALESCE(device_id, visitor_id) AS device_id,
          session_id,
          server_timestamp,
          is_conversion,
          COALESCE(utm_source, 'direct') AS utm_source,
          COALESCE(utm_medium, 'none') AS utm_medium,
          COALESCE(utm_campaign, 'none') AS utm_campaign,
          COALESCE(
            SAFE_CAST(JSON_EXTRACT_SCALAR(custom_properties_json, '$.value') AS FLOAT64),
            0.0
          ) AS conversion_value,
          ROW_NUMBER() OVER (PARTITION BY account_id, COALESCE(device_id, visitor_id) ORDER BY server_timestamp ASC) AS touch_asc,
          ROW_NUMBER() OVER (PARTITION BY account_id, COALESCE(device_id, visitor_id) ORDER BY server_timestamp DESC) AS touch_desc
        FROM `${var.project_id}.${google_bigquery_dataset.beacon_analytics.dataset_id}.events_raw`
      ),
      first_touches AS (
        SELECT
          account_id,
          COALESCE(device_id, visitor_id) AS device_id,
          utm_source AS first_touch_source,
          utm_medium AS first_touch_medium,
          utm_campaign AS first_touch_campaign
        FROM ordered_sessions
        WHERE touch_asc = 1
      ),
      conversions AS (
        SELECT
          account_id,
          COALESCE(device_id, visitor_id) AS device_id,
          session_id,
          server_timestamp AS conversion_time,
          utm_source AS last_touch_source,
          utm_medium AS last_touch_medium,
          utm_campaign AS last_touch_campaign,
          conversion_value
        FROM ordered_sessions
        WHERE is_conversion = true
      )
      SELECT
        c.account_id,
        DATE(c.conversion_time) AS conversion_date,
        f.first_touch_source,
        f.first_touch_campaign,
        c.last_touch_source,
        c.last_touch_campaign,
        COUNT(1) AS total_conversions,
        SUM(c.conversion_value) AS total_revenue
      FROM conversions c
      LEFT JOIN first_touches f
        ON c.account_id = f.account_id AND c.device_id = f.device_id
      GROUP BY 1, 2, 3, 4, 5, 6
    SQL
    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.events_raw]
}

resource "google_bigquery_table" "view_campaign_unit_economics" {
  dataset_id          = google_bigquery_dataset.beacon_analytics.dataset_id
  table_id            = "v_campaign_unit_economics"
  deletion_protection = false

  view {
    query          = <<-SQL
      SELECT
        DATE(server_timestamp) AS report_date,
        account_id,
        COALESCE(utm_source, 'direct') AS channel_source,
        COALESCE(utm_campaign, 'none') AS campaign_name,
        COUNT(DISTINCT session_id) AS total_visits,
        COUNT(DISTINCT COALESCE(device_id, visitor_id)) AS unique_devices,
        COUNTIF(is_conversion = true) AS conversions,
        ROUND(
          SAFE_DIVIDE(COUNTIF(is_conversion = true) * 100.0, COUNT(DISTINCT session_id)),
          2
        ) AS conversion_rate_percent,
        ROUND(
          SUM(COALESCE(SAFE_CAST(JSON_EXTRACT_SCALAR(custom_properties_json, '$.value') AS FLOAT64), 0.0)),
          2
        ) AS gross_revenue,
        ROUND(
          SAFE_DIVIDE(
            SUM(COALESCE(SAFE_CAST(JSON_EXTRACT_SCALAR(custom_properties_json, '$.value') AS FLOAT64), 0.0)),
            NULLIF(COUNTIF(is_conversion = true), 0)
          ),
          2
        ) AS average_order_value
      FROM `${var.project_id}.${google_bigquery_dataset.beacon_analytics.dataset_id}.events_raw`
      GROUP BY 1, 2, 3, 4
    SQL
    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.events_raw]
}
