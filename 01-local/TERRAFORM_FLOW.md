# Terraform hands-on: the core command flow

A step-by-step lesson that walks through the core Terraform commands using only the `local` provider, so no cloud account is needed.

## 0. Setup

Create a folder with this `main.tf`:

```hcl
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

resource "local_file" "hello" {
  filename = "${path.module}/out/hello.txt"
  content  = "hello from terraform\n"
}
```

**Teach:** `path.module` is the directory of the module the code is in. In the root module it's the folder you run Terraform from.

## 1. Initialise

```bash
terraform init
ls -a
find .terraform
```

**Observe:**

- `.terraform/providers/...` contains the downloaded provider binary for this OS and architecture.
- `.terraform.lock.hcl` pins the exact provider version and checksums.

**Teach:** `.terraform/` is a disposable cache, so add it to `.gitignore`. The lock file **should** be committed. Run `init` again whenever you add providers or modules or change the backend.

## 2. Tidy and check

```bash
terraform fmt
terraform validate
```

**Teach:** `fmt` formats the code. `validate` checks syntax and references without touching anything real.

## 3. Plan, and save the plan

```bash
terraform plan
terraform plan -out=tfplan
terraform show tfplan
```

**Observe:** the `+` create symbol, and `content_md5`, `content_sha256` and similar attributes shown as `(known after apply)`.

**Teach:**

- **Computed attributes** are values the provider works out itself, not ones you set.
- **Why save a plan:** `apply tfplan` does exactly what was reviewed. If the state changes in the meantime, the saved plan is rejected as stale. This is the basis of the plan → review → apply split in CI/CD.
- Plan files can contain secrets, so don't commit them.

## 4. Apply

```bash
terraform apply tfplan
cat out/hello.txt
ls
```

**Observe:** `out/hello.txt` exists, and `terraform.tfstate` has appeared.

**Teach:** state is Terraform's record of what it manages. Without it, Terraform doesn't know the file exists.

## 5. Inspect state

```bash
terraform state list
terraform state show local_file.hello
terraform show
```

**Teach:** `state list` shows what's been **applied**, not what's in the config. `state show` displays the computed hashes that were "known after apply" earlier.

## 6. Change the config

Edit `content` in `main.tf`, then:

```bash
terraform plan
terraform apply
ls
```

**Observe:**

- The plan shows a replace (`-/+`) or an update.
- `terraform.tfstate.backup` now exists.

**Teach:** before every state write, the local backend copies the previous state to `.backup`. It only keeps one version back. Remote backends use versioning instead.

## 7. Drift

```bash
rm out/hello.txt
terraform state list      # still lists local_file.hello
terraform plan            # "has been deleted" → will be created
terraform apply
```

Optionally, edit `out/hello.txt` by hand and run `plan` again.

**Teach:** Terraform only notices changes when it runs. On each plan it **refreshes** state against reality, then moves reality back to what the config declares.

## 8. Backends (discussion)

**Teach:** a backend is where state is stored. So far that's been the default **local** backend, `terraform.tfstate` on disk. Real teams use remote backends such as S3, Azure Blob, GCS or HCP Terraform to get shared state, locking and encryption.

```hcl
terraform {
  backend "s3" {
    bucket       = "my-tf-state"
    key          = "demo/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}
```

Changing the backend means running `terraform init` again. It offers to migrate the existing state, and `.terraform/terraform.tfstate` then stores a pointer to the backend, not the state itself.

## 9. Import (concept demo)

**Teach:** `import` brings an existing resource into state without changing it. The preferred style is an `import` block (Terraform 1.5+), which shows up in the plan:

```hcl
import {
  to = aws_s3_bucket.logs
  id = "my-existing-logs-bucket"
}
```

```bash
terraform plan -generate-config-out=generated.tf
terraform apply
```

Use it to adopt infrastructure created by hand or to recover from lost state. After importing, keep adjusting the config until `plan` shows no changes. Point out that the ID format, and whether import is supported at all, varies by resource, and the provider docs list both.

## 10. Tear down and start from scratch

```bash
terraform destroy
rm -rf .terraform terraform.tfstate terraform.tfstate.backup tfplan
```

**Key lesson:** **always destroy before deleting state.** Deleting state only makes Terraform forget the resources. With cloud resources, they keep running and keep costing money.

Then rebuild: `terraform init`, `terraform plan`, `terraform apply`.

---

## Cheat sheet

| Command | Purpose |
|---|---|
| `terraform init` | Download providers and modules, configure the backend |
| `terraform fmt` / `validate` | Format the code / check it |
| `terraform plan [-out=tfplan]` | Preview changes, optionally saving the plan |
| `terraform apply [tfplan]` | Make the changes |
| `terraform show [tfplan]` | Read the state or a saved plan |
| `terraform state list` / `state show <addr>` | Inspect managed resources |
| `terraform import` / `import {}` block | Adopt existing resources |
| `terraform destroy` | Remove everything Terraform manages |

## Suggested `.gitignore`

```gitignore
.terraform/
*.tfstate
*.tfstate.*
tfplan
```
