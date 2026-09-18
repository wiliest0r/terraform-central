# ==============================================================================
# Observability, Monitoring & Alerting (Google Cloud Monitoring & Logging)
# ==============================================================================

# 1. Incident Notification Channel (Email)
resource "google_monitoring_notification_channel" "email" {
  display_name = "Beacon Ops Incident Alerts (${var.environment})"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  user_labels = local.common_labels
}

# 2. Log-based Metric: Ingested Events Count
resource "google_logging_metric" "ingested_events" {
  name   = "beacon-ingested-events-${var.environment}"
  filter = "resource.type=\"k8s_container\" AND resource.labels.container_name=\"beacon-server\" AND textPayload:\"\\\"event_id\\\":\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Ingested Telemetry Events (${var.environment})"
  }
}

# 3. Log-based Metric: Quarantined Events Count
resource "google_logging_metric" "quarantined_events" {
  name   = "beacon-quarantined-events-${var.environment}"
  filter = "resource.type=\"k8s_container\" AND resource.labels.container_name=\"beacon-server\" AND textPayload:\"\\\"is_quarantined\\\":true\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Quarantined Telemetry Events (${var.environment})"
  }
}

# 4. Alert Policy: Dead-Letter Queue (DLQ) Backlog Alert
resource "google_monitoring_alert_policy" "dlq_backlog" {
  display_name = "Beacon DLQ Activity Alert (${var.environment})"
  combiner     = "OR"

  conditions {
    display_name = "Unprocessed events routed to DLQ topic"
    condition_threshold {
      filter          = "resource.type = \"pubsub_topic\" AND resource.labels.topic_id = \"${google_pubsub_topic.beacon_events_dlq.name}\" AND metric.type = \"pubsub.googleapis.com/topic/send_message_operation_count\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "Telemetry events failed schema validation or could not be delivered to Lakehouse GCS sink and were routed to DLQ ${google_pubsub_topic.beacon_events_dlq.name}."
    mime_type = "text/markdown"
  }

  user_labels = local.common_labels
}

# 5. Alert Policy: Lakehouse Delivery Lag Alert
resource "google_monitoring_alert_policy" "lakehouse_lag" {
  display_name = "Beacon Lakehouse Delivery Lag Alert (${var.environment})"
  combiner     = "OR"

  conditions {
    display_name = "Oldest unacknowledged message age > 15m"
    condition_threshold {
      filter          = "resource.type = \"pubsub_subscription\" AND resource.labels.subscription_id = \"${google_pubsub_subscription.lakehouse_sink.name}\" AND metric.type = \"pubsub.googleapis.com/subscription/oldest_unacked_message_age\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 900

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "3600s"
  }

  documentation {
    content   = "Subscription ${google_pubsub_subscription.lakehouse_sink.name} has not flushed events to GCS Lakehouse within 15 minutes. Check Pub/Sub service agent IAM and GCS bucket status."
    mime_type = "text/markdown"
  }

  user_labels = local.common_labels
}

# 6. Alert Policy: GKE Pod Restarts Alert
resource "google_monitoring_alert_policy" "pod_restarts" {
  count        = var.enable_gke ? 1 : 0
  display_name = "Beacon Server Container Restart Alert (${var.environment})"
  combiner     = "OR"

  conditions {
    display_name = "Container restart count > 0"
    condition_threshold {
      filter          = "resource.type = \"k8s_container\" AND resource.labels.container_name = \"beacon-server\" AND metric.type = \"kubernetes.io/container/restart_count\""
      duration        = "180s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "Beacon server container in GKE has restarted. Possible OOM killed or WASM runtime crash."
    mime_type = "text/markdown"
  }

  user_labels = local.common_labels
}

# 7. Cloud Monitoring Dashboard
resource "google_monitoring_dashboard" "beacon_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Beacon Telemetry & Lakehouse Dashboard (${var.environment})"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Pub/Sub Message Ingestion Rate"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\" resource.type=\"pubsub_topic\" resource.label.topic_id=\"${google_pubsub_topic.beacon_events.name}\""
                    aggregation = {
                      perSeriesAligner = "ALIGN_RATE"
                      alignmentPeriod  = "60s"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
          }
        },
        {
          title = "Lakehouse Subscription Unacked Messages"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" resource.type=\"pubsub_subscription\" resource.label.subscription_id=\"${google_pubsub_subscription.lakehouse_sink.name}\""
                    aggregation = {
                      perSeriesAligner = "ALIGN_MEAN"
                      alignmentPeriod  = "60s"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
          }
        },
        {
          title = "Oldest Unacknowledged Message Age (Seconds)"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" resource.type=\"pubsub_subscription\" resource.label.subscription_id=\"${google_pubsub_subscription.lakehouse_sink.name}\""
                    aggregation = {
                      perSeriesAligner = "ALIGN_MAX"
                      alignmentPeriod  = "60s"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
          }
        },
        {
          title = "GKE Pod CPU Core Usage"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/container/cpu/core_usage_time\" resource.type=\"k8s_container\" resource.label.container_name=monitoring.regex.full_match(\"beacon-server|vector\")"
                    aggregation = {
                      perSeriesAligner   = "ALIGN_RATE"
                      alignmentPeriod    = "60s"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.container_name"]
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
          }
        },
        {
          title = "GKE Pod Memory Used (Bytes)"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/container/memory/used_bytes\" resource.type=\"k8s_container\" resource.label.container_name=monitoring.regex.full_match(\"beacon-server|vector\")"
                    aggregation = {
                      perSeriesAligner   = "ALIGN_MEAN"
                      alignmentPeriod    = "60s"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.container_name"]
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
          }
        },
        {
          title = "Quarantined vs Ingested Telemetry Events"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.ingested_events.name}\" resource.type=\"k8s_container\""
                    aggregation = {
                      perSeriesAligner = "ALIGN_RATE"
                      alignmentPeriod  = "60s"
                    }
                  }
                }
                plotType = "LINE"
              },
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.quarantined_events.name}\" resource.type=\"k8s_container\""
                    aggregation = {
                      perSeriesAligner = "ALIGN_RATE"
                      alignmentPeriod  = "60s"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
          }
        }
      ]
    }
  })
}
