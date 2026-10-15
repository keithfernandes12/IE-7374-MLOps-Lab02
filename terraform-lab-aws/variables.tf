variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used in resource names and tags"
  type        = string
  default     = "mlops-lab"
}

variable "environment" {
  description = "Deployment environment tag"
  type        = string
  default     = "dev"
}

variable "model_name" {
  description = "Name of the model whose artifact is stored in the bucket"
  type        = string
  default     = "iris-classifier"
}

variable "model_version" {
  description = "Version written into the sample model artifact; change it to create a new S3 object version"
  type        = string
  default     = "1.0.0"
}

variable "noncurrent_ia_days" {
  description = "Days before an old artifact version moves to STANDARD_IA (minimum 30)"
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_ia_days >= 30
    error_message = "S3 requires objects to be at least 30 days old before moving to STANDARD_IA."
  }
}

variable "noncurrent_expire_days" {
  description = "Days before an old artifact version is deleted"
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the bucket even if it holds artifact versions"
  type        = bool
  default     = true
}
