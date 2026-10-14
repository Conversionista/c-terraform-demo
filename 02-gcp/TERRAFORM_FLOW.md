# Part 02: how the Terraform flow works on GCP

## The big picture

Two Terraform configurations, one service account, one project.

```mermaid
flowchart LR
    you["You<br/>(gcloud ADC login)"]
    sa["c-terraform-general<br/>service account"]

    subgraph local["Your laptop"]
        boot["bootstrap/<br/>local state"]
        bq["bigquery/<br/>remote state"]
    end

    subgraph gcp["GCP project: conversionista-se"]
        bucket[("GCS bucket<br/>conversionista-se-tfstate-training")]
        src[("thelook_raw<br/>(US)")]
        ds[("tf_training_thelook<br/>(US)")]
        sq["Scheduled query<br/>tf-demo-daily-order-summary"]
    end

    you -- runs terraform --> boot
    you -- runs terraform --> bq
    boot -. impersonates .-> sa
    bq -. impersonates .-> sa
    sa -- creates --> bucket
    sa -- creates --> ds
    sa -- creates --> sq
    bq -- stores state in --> bucket
    sq -- reads --> src
    sq -- writes daily_order_summary --> ds
```

## Step 1–2: authentication and impersonation

You log in as yourself, but every API call is made as the service account.

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant TF as Terraform<br/>(google provider)
    participant IAM as IAM Credentials API
    participant API as GCP APIs<br/>(Storage, BigQuery)

    You->>TF: terraform plan / apply
    TF->>TF: Read your ADC credentials<br/>(gcloud auth application-default login)
    TF->>IAM: generateAccessToken for c-terraform-general<br/>(allowed: you have Token Creator on the SA)
    IAM-->>TF: Short-lived SA access token
    TF->>API: API calls with the SA token
    API->>API: Check the SA's project roles<br/>(storage.admin, bigquery.admin)
    API-->>TF: Result
```

Two things have to be true:

| Permission | Granted to | On |
|---|---|---|
| `roles/iam.serviceAccountTokenCreator` | You | The service account |
| `roles/storage.admin`, `roles/bigquery.admin` | The service account | The project |

## Step 3: bootstrapping remote state

The chicken-and-egg problem: remote state needs a bucket, and the bucket is created by Terraform.

```mermaid
flowchart TD
    A["bootstrap/<br/>no backend block"] -->|terraform init + apply| B[("GCS state bucket")]
    A -->|its own state| C["bootstrap/terraform.tfstate<br/>(on your laptop)"]

    D["bigquery/<br/>backend &quot;gcs&quot; block"] -->|terraform init| E{"Bucket<br/>exists?"}
    E -->|no| F["init fails:<br/>run bootstrap first"]
    E -->|yes| G["Backend configured<br/>.terraform/terraform.tfstate points to the bucket"]
    G -->|terraform apply| H["gs://.../02-gcp/bigquery/default.tfstate"]
    B -.-> H
```

How the GCS backend handles each run:

```mermaid
sequenceDiagram
    autonumber
    participant TF as terraform apply
    participant GCS as State bucket
    participant GCP as BigQuery

    TF->>GCS: Create lock file (default.tflock)
    alt Lock already held
        GCS-->>TF: Error acquiring the state lock
    else Lock acquired
        TF->>GCS: Read default.tfstate
        TF->>GCP: Refresh: read real resources
        TF->>TF: Diff config vs state, build plan
        TF->>GCP: Create / update / delete resources
        TF->>GCS: Write new default.tfstate<br/>(bucket versioning keeps the old one)
        TF->>GCS: Delete lock file
    end
```

## Step 4–5: dependency graph

Terraform works out the order from references. Nothing needs `depends_on`.

```mermaid
flowchart LR
    sql["sql/daily_order_summary.sql"] -->|templatefile| sq
    vars["var.project_id<br/>var.source_dataset"] -->|"source = project.dataset"| sq
    ds["google_bigquery_dataset.demo"] -->|"dataset_id, location"| sq["google_bigquery_data_transfer_config<br/>.daily_order_summary"]
    sq --> out1["output.scheduled_query_name"]
    ds --> out2["output.dataset"]
```

So `apply` creates the **dataset first**, then the scheduled query. `destroy` runs in reverse.

You can generate this graph yourself:

```bash
terraform graph | dot -Tsvg > graph.svg    # needs graphviz
```

## What the scheduled query does once created

Terraform only creates the *definition*. BigQuery runs it on the schedule.

```mermaid
sequenceDiagram
    autonumber
    participant Sched as BigQuery Data Transfer<br/>(every day 06:00 or "Run now")
    participant SA as c-terraform-general
    participant Src as thelook_raw.orders<br/>thelook_raw.order_items
    participant Dst as tf_training_thelook<br/>.daily_order_summary

    Sched->>SA: Run as the identity that created the config
    SA->>Src: SELECT ... GROUP BY order_date, status
    Src-->>SA: Rows
    SA->>Dst: WRITE_TRUNCATE (replace table contents)
```

Terraform isn't involved in the runs. Data written by the query isn't in Terraform state.

## The command lifecycle

The same loop as Part 01, now against real cloud resources.

```mermaid
stateDiagram-v2
    [*] --> Init: terraform init
    Init --> Plan: terraform plan -out=tfplan
    Plan --> Review: read the + / ~ / -/+ / - symbols
    Review --> Plan: change the code
    Review --> Apply: terraform apply tfplan
    Apply --> Plan: next change
    Apply --> Destroy: terraform destroy
    Destroy --> [*]

    note right of Init
        Downloads the google provider,
        configures the GCS backend
    end note
    note right of Apply
        State is written to the bucket,
        not to your laptop
    end note
```

## Step 6: teardown order

Destroy in the **reverse** order of creation. The bucket holds the state for `bigquery/`, so it goes last.

```mermaid
flowchart TD
    A["cd bigquery/<br/>terraform destroy"] --> B["Scheduled query deleted"]
    B --> C["Dataset deleted<br/>(delete_contents_on_destroy removes the table)"]
    C --> D["cd bootstrap/<br/>terraform destroy"]
    D --> E["State bucket deleted<br/>(force_destroy removes the leftover state objects)"]
    E --> F(["Project back to where it started"])

    X["Destroy bootstrap first?"] -.->|bad idea| Y["bigquery/ state is gone,<br/>dataset + query are orphaned"]
```

## Cheat sheet

| Command | Run in | What it does here |
|---|---|---|
| `gcloud auth application-default login` | anywhere | Your credentials, used to impersonate the SA |
| `terraform init` | `bootstrap/`, `bigquery/` | Download the provider; in `bigquery/`, connect to the GCS backend |
| `terraform plan -out=tfplan` | both | Preview, impersonating the SA |
| `terraform apply tfplan` | both | Create the bucket / dataset + scheduled query |
| `terraform state list` | `bigquery/` | Reads state **from the bucket** |
| `gcloud storage ls -r gs://conversionista-se-tfstate-training` | anywhere | See the state file and lock |
| `terraform destroy` | `bigquery/` then `bootstrap/` | Tear down in reverse order |
