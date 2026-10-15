# Lab 02 – Terraform: MLOps Artifact Store on AWS

[![Terraform CI](https://github.com/keithfernandes12/IE-7374-MLOps-Lab02/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/keithfernandes12/IE-7374-MLOps-Lab02/actions/workflows/terraform-ci.yml)

Based on the course [Terraform Beginner Lab (AWS)](https://github.com/raminmohammadi/MLOps/tree/main/Labs/Terraform_Labs/AWS/Lab1_Beginner).
I completed Parts 1–6 of the original lab, then extended it into a small **MLOps model artifact store**: a versioned, encrypted, private S3 bucket that an EC2 instance can read through an IAM role, with no access keys on the machine.

## What I changed from the original lab

| Area | Original lab | This version |
|---|---|---|
| AMI | Hardcoded `ami-0e2c8caa4b6378d8c` | `data "aws_ami"` looks up the latest Ubuntu 24.04 image, so the ID never goes stale |
| Instance type | `t2.micro` | `t3.micro`, eligible on both the legacy and the new AWS free plan |
| Configuration | Hardcoded values in one file | Input variables, outputs and provider `default_tags`, split across files |
| Storage | None | S3 artifact bucket with versioning, encryption, public access block and lifecycle rules |
| Access | None | IAM role + instance profile with least-privilege read access |
| Verification | Check the console | Boot script on the instance proves it can read the model and cannot overwrite it |
| CI | None | GitHub Actions runs `fmt`, `validate` and offline `terraform test` on every push and PR |

## Files

```
.github/workflows/
└── terraform-ci.yml      CI: fmt check, init, validate, test

terraform-lab-aws/
├── main.tf               provider, default tags, AMI lookup, EC2 instance, VPC + subnet (Parts 1–4)
├── variables.tf          region, naming, model version, lifecycle settings
├── s3.tf                 artifact bucket + versioning, encryption, public access block, lifecycle, sample model
├── iam.tf                EC2 trust policy, read-only bucket policy, instance profile
├── outputs.tf            bucket name, model URI and version ID, instance ID, role ARN
├── user_data.sh.tftpl    first-boot script that tests read (allowed) and write (denied)
└── tests/
    └── artifact_store.tftest.hcl   offline tests with a mocked AWS provider
```

## Design choices

- **Versioning** keeps every version of `model.json`, so a bad model can be rolled back by version ID.
- **Lifecycle rule**: old (noncurrent) versions move to `STANDARD_IA` after 30 days and are deleted after 90. Incomplete multipart uploads are cleaned up after 7 days. Both day counts are variables, and a `validation` block enforces S3's 30-day minimum for `STANDARD_IA`.
- **Encryption** uses SSE-S3 (`AES256`), which is free and needs no KMS key.
- **Public access block** turns on all four settings, so artifacts can never be made public by accident.
- **Unique bucket name** comes from the AWS account ID (`mlops-lab-artifacts-<account-id>`) instead of a random suffix, so it's stable across re-creates.
- **Least privilege**: the instance role can only `ListBucket`, `GetObject` and `GetObjectVersion` on this one bucket.
- **`depends_on`** makes sure versioning is on before lifecycle rules and objects are created, and that the model exists before the instance boots and tries to download it.

## How to run

From `terraform-lab-aws/` (credentials come from `aws configure`):

```powershell
terraform init
terraform plan
terraform apply
```

From an empty state, the plan should show **12 to add**: the EC2 instance, VPC, subnet, 6 S3 resources (bucket, versioning, encryption, public access block, lifecycle, sample model) and 3 IAM resources (role, policy, instance profile).

## Verifying it works

**1. The instance can read the model but not write to the bucket.** Wait about 3–5 minutes after apply for the boot script to finish, then:

```powershell
aws ec2 get-console-output --instance-id (terraform output -raw instance_id) --latest --output text | Select-String "ARTIFACT_PULL|WRITE_"
```

Expected:

```
ARTIFACT_PULL_OK: {"framework":"scikit-learn","metrics":{"accuracy":0.96},"model_name":"iris-classifier","model_version":"1.0.0"}
WRITE_DENIED: expected, the instance role is read-only
```

**2. Versioning keeps old models.** Publish a new model version, then list the versions:

```powershell
terraform apply -var="model_version=1.1.0"
aws s3api list-object-versions --bucket (terraform output -raw artifact_bucket) --prefix models/ --query "Versions[].[VersionId,IsLatest,LastModified]" --output table
```

There should be two versions, with only the newest marked `IsLatest = True`. To roll back, download the older one by its version ID:

```powershell
aws s3api get-object --bucket (terraform output -raw artifact_bucket) --key models/iris-classifier/model.json --version-id <old-version-id> previous_model.json
```

**3. The bucket is private and encrypted.**

```powershell
aws s3api get-public-access-block --bucket (terraform output -raw artifact_bucket)
aws s3api get-bucket-encryption --bucket (terraform output -raw artifact_bucket)
aws s3api get-bucket-lifecycle-configuration --bucket (terraform output -raw artifact_bucket)
```

## Continuous integration

[`.github/workflows/terraform-ci.yml`](.github/workflows/terraform-ci.yml) runs on every push to `main` and every pull request that touches `terraform-lab-aws/`:

1. **`terraform fmt -check`** fails if any file isn't in canonical Terraform style.
2. **`terraform init`** downloads the AWS provider, cached between runs using the lock file hash.
3. **`terraform validate`** catches syntax errors, bad references and wrong argument types.
4. **`terraform test`** runs [`tests/artifact_store.tftest.hcl`](terraform-lab-aws/tests/artifact_store.tftest.hcl).

The tests use `mock_provider "aws"`, so they need **no AWS credentials, create nothing and cost nothing**. Terraform plans the config against a fake AWS and checks:

| Test | What it checks |
|---|---|
| `bucket_is_versioned_encrypted_and_private` | Bucket name format, versioning on, AES256 encryption, all 4 public access settings on |
| `lifecycle_ages_out_old_versions` | Old versions go to `STANDARD_IA` at 30 days and are deleted at 90 |
| `instance_role_is_read_only` | Role can `GetObject` but has no `PutObject`, `DeleteObject` or wildcard actions; EC2 uses the role and `t3.micro` |
| `model_version_flows_into_artifact` | Setting `model_version` updates both the artifact content and its metadata |
| `rejects_ia_transition_under_30_days` | The variable validation blocks a transition S3 would reject |

Run the same checks locally from `terraform-lab-aws/`:

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
```

## Cleanup

```powershell
terraform destroy
```

`force_destroy = true` lets Terraform delete the bucket even though it still holds old model versions.

## Takeaways

- Terraform builds a dependency graph from resource references (`aws_s3_bucket.artifacts.arn`) and from explicit `depends_on`, then creates resources in the right order.
- Data sources (`aws_ami`, `aws_caller_identity`, `aws_iam_policy_document`) read information instead of creating anything, which keeps the config portable across accounts.
- IAM roles let workloads use AWS without any stored keys. That's the same pattern a training or serving job would use to pull model artifacts in production.
