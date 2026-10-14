# Part 02: Terraform on GCP

Part 01 covered the core Terraform workflow using local files. Part 02 applies the same workflow to real Google Cloud resources: a remote state bucket, a BigQuery dataset, and a scheduled query that summarises theLook orders into that dataset.

It shows how to:

1. Configure the Google provider for an existing project
2. Run Terraform as a service account via impersonation
3. Bootstrap a GCS bucket for remote state and point a backend at it
4. Create a BigQuery scheduled query that extracts data from theLook
5. Create the target dataset the scheduled query writes into
6. Destroy everything again

For diagrams of how these pieces fit together, see [TERRAFORM_FLOW.md](TERRAFORM_FLOW.md).

## Layout

```
02-gcp/
├── bootstrap/            # creates the state bucket (state kept locally)
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── bigquery/             # dataset + scheduled query (state kept in the bucket)
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── sql/daily_order_summary.sql
```

| | |
|---|---|
| Project | `conversionista-se` |
| Terraform service account | `c-terraform-general@conversionista-se.iam.gserviceaccount.com` |
| Source data | `conversionista-se.thelook_raw` (US) |
| State bucket | `gs://conversionista-se-tfstate-training` (EU) |
| Target dataset | `conversionista-se.tf_training_thelook` (US) |

## Prerequisites

- Terraform and the `gcloud` CLI installed
- `roles/iam.serviceAccountTokenCreator` on the Terraform service account
- Application Default Credentials:

  ```bash
  gcloud auth application-default login
  ```

## 1. The Google provider

The provider is documented at [registry.terraform.io/providers/hashicorp/google](https://registry.terraform.io/providers/hashicorp/google/latest/docs). Each resource page has *Example Usage*, *Argument Reference*, *Attributes Reference* and *Import* sections. The resources used here are `google_storage_bucket`, `google_bigquery_dataset` and `google_bigquery_data_transfer_config`.

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7"
    }
  }
}

provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.terraform_sa
}
```

- `required_providers` and `terraform init` work the same way as with the `local` provider in Part 01.
- The `provider` block sets defaults such as project and region. A resource can override them with its own arguments.
- These configs use an existing project. Terraform can also create projects (`google_project`), but that needs organisation and billing permissions.

## 2. Service account impersonation

You authenticate as yourself, but Terraform makes every API call as `c-terraform-general`. That gives everyone the same permissions without personal admin rights, and the audit logs show what Terraform did. CI pipelines work the same way, with Workload Identity Federation instead of a personal login.

It relies on two permissions:

| Permission | Granted to | On |
|---|---|---|
| `roles/iam.serviceAccountTokenCreator` | You | The service account |
| `roles/storage.admin`, `roles/bigquery.admin` | The service account | The project |

Impersonation is configured with `impersonate_service_account` in the provider block (and separately in the backend block). Alternatively, set it with an environment variable instead of in code:

```bash
export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=c-terraform-general@conversionista-se.iam.gserviceaccount.com
```

To check that impersonation works:

```bash
gcloud auth print-access-token \
  --impersonate-service-account=c-terraform-general@conversionista-se.iam.gserviceaccount.com >/dev/null && echo "impersonation OK"
```

## 3. Bootstrapping remote state

Remote state needs a bucket, but the bucket should be managed by Terraform too. The `bootstrap/` config solves this chicken-and-egg problem: it has no backend block, so it keeps its own state locally, and it creates the bucket.

```bash
cd 02-gcp/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

The bucket has versioning (to keep a history of state), uniform bucket-level access, and enforced public access prevention (because state can contain secrets). `force_destroy` is enabled so the demo can be torn down even when the bucket holds state files.

The `bigquery/` config then stores its state in that bucket:

```hcl
backend "gcs" {
  bucket                      = "conversionista-se-tfstate-training"
  prefix                      = "02-gcp/bigquery"
  impersonate_service_account = "c-terraform-general@conversionista-se.iam.gserviceaccount.com"
}
```

- Backend blocks can't use variables, so the values are written out.
- The backend has its own `impersonate_service_account`, separate from the provider block.
- `prefix` is a folder in the bucket, so several configs can share one bucket.
- The GCS backend locks the state during each run.

### Where does the bootstrap state live?

On your laptop, in `bootstrap/terraform.tfstate`. That's fine here. In real projects:

- **Migrate it into the bucket it created** (`backend "gcs"` with `prefix = "bootstrap"`, then `terraform init -migrate-state`). The catch is that to destroy the bucket you first have to migrate the state back to local.
- **Or keep it local** and rely on `import` to recover if the file is lost. `google_storage_bucket` supports import.
- **Never commit state as a general practice.** State stores every attribute in plain text, so it's the main way secrets leak into git. It also has no locking, goes stale when someone forgets to commit, and doesn't merge.

## 4–5. Target dataset and scheduled query

`bigquery/main.tf` defines two resources:

- **`google_bigquery_dataset.demo`**: the target dataset. It's in the **US** to match `thelook_raw`, because a scheduled query can't read from one location and write to another. `delete_contents_on_destroy` lets Terraform delete it after the query has written tables.
- **`google_bigquery_data_transfer_config.daily_order_summary`**: the scheduled query (`data_source_id = "scheduled_query"`). It runs every day at 06:00 and overwrites `daily_order_summary` (`WRITE_TRUNCATE`) with orders, items and revenue per day and status.

The scheduled query references the dataset (`destination_dataset_id = google_bigquery_dataset.demo.dataset_id`), so Terraform creates the dataset first without needing `depends_on`. The SQL lives in `sql/daily_order_summary.sql` and is loaded with `templatefile("${path.module}/sql/...", { source = ... })`.

```bash
cd 02-gcp/bigquery
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform state list
gcloud storage ls -r gs://conversionista-se-tfstate-training   # the state file is in the bucket
```

To see the result without waiting for the schedule, open BigQuery → *Scheduled queries* → `tf-demo-daily-order-summary` → **Run transfer now**, then look at `tf_training_thelook.daily_order_summary`. The query runs as `c-terraform-general`, because that's the identity that created it.

Terraform only manages the scheduled query's *definition*. The runs and the data they write aren't part of Terraform state.

## 6. Destroy

Destroy in reverse order. The bucket holds the state for `bigquery/`, so it goes last:

```bash
cd 02-gcp/bigquery
terraform destroy          # scheduled query + dataset

cd ../bootstrap
terraform destroy          # state bucket
```

`delete_contents_on_destroy` and `force_destroy` are deliberately enabled for this demo. Both default to `false`, because in real projects you want Terraform to refuse to delete data.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Permission 'iam.serviceAccounts.getAccessToken' denied` | Your user lacks Token Creator on the service account, or you haven't run `gcloud auth application-default login` |
| `Error 409: bucket ... already exists` | Bucket names are global. Change `state_bucket_name` **and** the `bucket` in the backend block. |
| `Already Exists: Dataset ...` | `tf_training_thelook` already exists. Pick another `dataset_id`. |
| Scheduled query fails on creation with a service-agent/token error | Grant `service-<project-number>@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com` `roles/iam.serviceAccountTokenCreator` on `c-terraform-general` |
| Scheduled query run fails with a location error | Source and target datasets must be in the same location (US) |
| `Error acquiring the state lock` | A previous run crashed. Run `terraform force-unlock <LOCK_ID>`, but only when you're sure nobody else is running Terraform. |
