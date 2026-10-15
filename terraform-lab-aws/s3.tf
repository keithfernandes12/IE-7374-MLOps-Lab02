# MLOps artifact store: a versioned, encrypted, private S3 bucket for model files

data "aws_caller_identity" "current" {}

locals {
  # Account ID makes the name globally unique without a random suffix
  bucket_name = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"
  model_key   = "models/${var.model_name}/model.json"
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
}

# Keep every version of every artifact so a bad model can be rolled back
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt artifacts at rest with S3-managed keys (free, no KMS charges)
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Model files should never be publicly readable
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old model versions move to cheaper storage, then get deleted
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "age-out-old-model-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_transition {
      noncurrent_days = var.noncurrent_ia_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_expire_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Lifecycle rules on noncurrent versions need versioning turned on first
  depends_on = [aws_s3_bucket_versioning.artifacts]
}

# Sample model artifact; changing var.model_version uploads a new object version
resource "aws_s3_object" "sample_model" {
  bucket       = aws_s3_bucket.artifacts.id
  key          = local.model_key
  content_type = "application/json"
  content = jsonencode({
    model_name    = var.model_name
    model_version = var.model_version
    framework     = "scikit-learn"
    metrics       = { accuracy = 0.96 }
  })

  metadata = {
    model-version = var.model_version
  }

  depends_on = [aws_s3_bucket_versioning.artifacts]
}
