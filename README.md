# Terraform Central (`terraform-central`)

Infrastructure as Code (IaC) repository managing Google Cloud Platform (GCP) resources for the **PlayTests Beacon** analytics engine via **HCP Terraform (Terraform Cloud)** and **Workload Identity Federation (OIDC)**.

## Architecture

```text
GitHub (wiliest0r/terraform-central)
  │
  ├── Pull Request ──> HCP Terraform Speculative Plan
  └── Merge to main ─> HCP Terraform Apply
                            │ (OIDC / Dynamic Provider Credentials)
                            ▼
               GCP Workload Identity Federation
               (Pool: tfc-pool / Provider: tfc-provider)
                            │ (Impersonate)
                            ▼
          sa-terraform-executor@playtests-beacon.iam.gserviceaccount.com
                            │ (Provisions)
                            ▼
               ├── Google Artifact Registry (beacon-repo)
               └── Cloud Run v2 (beacon-server)
```

## OIDC & Dynamic Provider Credentials Configuration

This infrastructure utilizes secretless authentication. In your HCP Terraform workspace (**`terraform-central`** under the **`PlayTests`** organization), configure the following environment variables:

| Variable Name | Category | Value | Description |
| :--- | :--- | :--- | :--- |
| `TFC_GCP_PROVIDER_AUTH` | Environment | `true` | Enables Dynamic Provider Credentials |
| `TFC_GCP_WORKLOAD_PROVIDER_NAME` | Environment | `projects/847948858817/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider` | Full resource name of the WIF provider |
| `TFC_GCP_SERVICE_ACCOUNT_EMAIL` | Environment | `sa-terraform-executor@playtests-beacon.iam.gserviceaccount.com` | Target GCP Service Account |

## Managed Resources

1. **Artifact Registry Repository (`beacon-repo`)**: Docker & WASM OCI format for storing containerized Spin services and WebAssembly modules.
2. **Cloud Run Service (`beacon-server`)**: Serverless runtime executing the high-performance Rust WASM telemetry ingestion service.
3. **Public Ingress IAM**: `roles/run.invoker` granted to `allUsers` for telemetry ingestion endpoint `/v1/sync` and static tag delivery.
