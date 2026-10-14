# Part 02: Terraform on GCP (1-hour demo)

Instructor-led demo. It creates a GCS state bucket, a BigQuery dataset and a scheduled query that summarises theLook orders, then tears everything down.

```
02-gcp/
├── bootstrap/            # creates the state bucket (local state)
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── bigquery/             # dataset + scheduled query (state in the bucket)
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── sql/daily_order_summary.sql
```

| | |
|---|---|
| Project | `conversionista-se` |
| Terraform SA | `c-terraform-general@conversionista-se.iam.gserviceaccount.com` |
| Source data | `conversionista-se.thelook_raw` (US) |
| State bucket | `gs://conversionista-se-tfstate-training` (EU) |
| Target dataset | `conversionista-se.tf_training_thelook` (US) |

## Timing

| Step | Minutes |
|---|---|
| 1. Google provider and project | 10 |
| 2. Impersonating the service account | 10 |
| 3. Bootstrap the state bucket and link the backend | 12 |
| 4–5. Target dataset and scheduled query | 18 |
| 6. Destroy | 5 |
| Buffer / questions | 5 |

## Before the session

```bash
gcloud auth application-default login     # your own user credentials (ADC)
terraform -version
```

Do a full dry run once beforehand: the first `init` downloads the Google provider (~100 MB).

---

## 1. Google provider and project (10 min)

**Show:** the provider docs at registry.terraform.io/providers/hashicorp/google/latest/docs.

- The **Documentation** tab: resources (create things) vs data sources (read things).
- Search for `google_storage_bucket`, `google_bigquery_dataset` and `google_bigquery_data_transfer_config`. Point out the *Example Usage*, *Argument Reference*, *Attributes Reference* and *Import* sections.
- *Guides → Provider Configuration Reference*: `project`, `region`, `impersonate_service_account`.

**Open `bootstrap/main.tf`:**

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
  project = var.project_id      # every resource defaults to this project
  region  = var.region
  impersonate_service_account = var.terraform_sa
}
```

**Teach:**

- `required_providers` + `init` is the same as with `local` in Part 01.
- The `provider` block sets defaults (project, region). A resource can override them with its own `project` argument.
- We're *using* an existing project. Terraform can also create projects (`google_project`), but that needs org and billing permissions.

## 2. Impersonating the service account (10 min)

**Explain the idea:** you log in as yourself, but Terraform calls GCP as `c-terraform-general`.

- Everyone runs with the **same permissions**, so nobody needs personal admin rights.
- The audit logs show what Terraform did.
- CI works the same way, swapping your login for Workload Identity Federation.

**What makes it work (show in the Console under IAM → Service accounts → c-terraform-general → Permissions):**

1. You have `roles/iam.serviceAccountTokenCreator` **on the SA**, so you can mint tokens for it.
2. The SA has the project roles it needs (`roles/storage.admin`, `roles/bigquery.admin`, …).
3. `impersonate_service_account` in the provider block. Alternatively, set an env var instead of putting it in code:
   ```bash
   export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=c-terraform-general@conversionista-se.iam.gserviceaccount.com
   ```

**Prove it:**

```bash
gcloud auth print-access-token \
  --impersonate-service-account=c-terraform-general@conversionista-se.iam.gserviceaccount.com >/dev/null && echo "impersonation OK"
```

## 3. Bootstrap the state bucket and link the backend (12 min)

**The chicken-and-egg problem:** remote state needs a bucket, and we want the bucket in Terraform too. The solution is a small `bootstrap` config that keeps its *own* state locally and creates the bucket.

```bash
cd 02-gcp/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output state_bucket
```

**Point out in `bootstrap/main.tf`:** versioning (state history), `uniform_bucket_level_access`, `public_access_prevention` (state can contain secrets), and `force_destroy` (demo only).

**Talking point: where does the bootstrap state live?** On your laptop, in `bootstrap/terraform.tfstate`. That's fine for the demo. In real life:

- **Migrate it into the bucket it created** (`backend "gcs"` with `prefix = "bootstrap"`, then `terraform init -migrate-state`). The catch is that to destroy the bucket you first have to migrate the state back to local.
- **Or keep it local** and rely on `import` to recover if the file is lost. `google_storage_bucket` supports import.
- **Never commit state as a general practice.** State stores every attribute in plain text, so it's the main way secrets leak into git. It also has no locking, goes stale when someone forgets to commit, and doesn't merge.

**Link the backend: open `bigquery/main.tf`:**

```hcl
backend "gcs" {
  bucket                      = "conversionista-se-tfstate-training"
  prefix                      = "02-gcp/bigquery"
  impersonate_service_account = "c-terraform-general@conversionista-se.iam.gserviceaccount.com"
}
```

**Teach:**

- Backend blocks **can't use variables**, so the values are literal.
- The backend needs its own `impersonate_service_account`. It's separate from the provider block.
- `prefix` = folder in the bucket, so many configs can share one bucket.
- The GCS backend has built-in **locking**.

```bash
cd ../bigquery
terraform init
gcloud storage ls -r gs://conversionista-se-tfstate-training   # empty until the first apply
```

## 4–5. Target dataset and scheduled query (18 min)

**Walk through `bigquery/main.tf`:**

- `google_bigquery_dataset.demo` is the target. Its location must be **US** to match `thelook_raw`, because a scheduled query can't read from one location and write to another.
- `google_bigquery_data_transfer_config.daily_order_summary` is the scheduled query: `data_source_id = "scheduled_query"`, plus `schedule`, the destination table template and `write_disposition`.
- **Implicit dependency:** `destination_dataset_id = google_bigquery_dataset.demo.dataset_id` makes Terraform create the dataset first.
- **SQL in its own file** via `templatefile("${path.module}/sql/...", { source = ... })`, which reuses `path.module` from Part 01.

```bash
terraform plan -out=tfplan
terraform apply tfplan
terraform state list
gcloud storage ls -r gs://conversionista-se-tfstate-training   # state is now in the bucket
```

**Show the result in the Console:**

1. BigQuery → *Scheduled queries* → `tf-demo-daily-order-summary` → **Run transfer now**. The query runs as `c-terraform-general`, because that's who created it.
2. Open `tf_training_thelook.daily_order_summary` once the run finishes (~30 s).

**Optional, if time allows: an in-place update.** Change `schedule` to `"every day 07:00"` and run `terraform plan`. You'll see `~ update in-place`, not a replacement.

## 6. Destroy (5 min)

**Order matters:** destroy what uses the bucket first, then the bucket.

```bash
cd 02-gcp/bigquery
terraform destroy          # scheduled query + dataset (delete_contents_on_destroy removes the table)

cd ../bootstrap
terraform destroy          # state bucket (force_destroy removes the leftover state objects)
```

**Teach:** `delete_contents_on_destroy` and `force_destroy` are deliberate safety switches. They default to `false` because in real life you *want* Terraform to refuse to delete data.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Permission 'iam.serviceAccounts.getAccessToken' denied` | Your user lacks Token Creator on the SA, or you haven't run `gcloud auth application-default login` |
| `Error 409: bucket ... already exists` | Bucket names are global. Change `state_bucket_name` **and** the `bucket` in the backend block. |
| `Already Exists: Dataset ...` | Someone created `tf_training_thelook` by hand. Pick another `dataset_id`. |
| Scheduled query fails on creation with a service-agent/token error | The BigQuery Data Transfer service agent needs to be able to act as the SA. Grant `service-<project-number>@gcp-sa-bigquerydatatransfer.iam.gserviceaccount.com` `roles/iam.serviceAccountTokenCreator` on `c-terraform-general`. |
| Scheduled query run fails with a location error | Source and target datasets must be in the same location (US) |
| `Error acquiring the state lock` | A previous run crashed. `terraform force-unlock <LOCK_ID>`, only when you're sure nobody else is running. |
