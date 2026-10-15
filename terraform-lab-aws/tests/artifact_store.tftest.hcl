# Offline tests: the AWS provider is mocked, so no credentials are needed and nothing is created

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

run "bucket_is_versioned_encrypted_and_private" {
  command = plan

  assert {
    condition     = aws_s3_bucket.artifacts.bucket == "mlops-lab-artifacts-123456789012"
    error_message = "Bucket name should be <project>-artifacts-<account-id>."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.artifacts.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled so old models can be rolled back."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.artifacts.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Artifacts must be encrypted at rest."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.artifacts.block_public_acls,
      aws_s3_bucket_public_access_block.artifacts.block_public_policy,
      aws_s3_bucket_public_access_block.artifacts.ignore_public_acls,
      aws_s3_bucket_public_access_block.artifacts.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be on."
  }
}

run "lifecycle_ages_out_old_versions" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).noncurrent_version_transition).noncurrent_days == 30
    error_message = "Old versions should move to STANDARD_IA after 30 days."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).noncurrent_version_transition).storage_class == "STANDARD_IA"
    error_message = "Old versions should transition to STANDARD_IA."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).noncurrent_version_expiration).noncurrent_days == 90
    error_message = "Old versions should be deleted after 90 days."
  }
}

run "instance_role_is_read_only" {
  command = plan

  assert {
    condition     = contains(flatten([for s in data.aws_iam_policy_document.artifact_read.statement : s.actions]), "s3:GetObject")
    error_message = "The instance role must be able to read artifacts."
  }

  assert {
    condition = length(setintersection(
      flatten([for s in data.aws_iam_policy_document.artifact_read.statement : s.actions]),
      ["s3:PutObject", "s3:DeleteObject", "s3:*", "*"],
    )) == 0
    error_message = "The instance role must not be able to write or delete artifacts."
  }

  assert {
    condition     = aws_instance.myec2.iam_instance_profile == "mlops-lab-artifact-reader"
    error_message = "The EC2 instance must run as the artifact-reader instance profile."
  }

  assert {
    condition     = aws_instance.myec2.instance_type == "t3.micro"
    error_message = "Use t3.micro to stay on the free tier."
  }
}

run "model_version_flows_into_artifact" {
  command = plan

  variables {
    model_version = "2.0.0"
  }

  assert {
    condition     = jsondecode(aws_s3_object.sample_model.content).model_version == "2.0.0"
    error_message = "The artifact content should carry the requested model version."
  }

  assert {
    condition     = aws_s3_object.sample_model.metadata["model-version"] == "2.0.0"
    error_message = "The artifact metadata should carry the requested model version."
  }
}

run "rejects_ia_transition_under_30_days" {
  command = plan

  variables {
    noncurrent_ia_days = 10
  }

  expect_failures = [var.noncurrent_ia_days]
}
