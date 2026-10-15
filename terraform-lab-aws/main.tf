terraform {
  # 1.7+ is needed for mock providers in the offline tests
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Applied to every resource that supports tags
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Look up the latest Ubuntu 24.04 AMI instead of hardcoding an ID that can be retired
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Part 1-3: EC2 instance with a Name tag
# Extension: runs as the artifact-reader role and tests reading the model at boot
resource "aws_instance" "myec2" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3.micro" # free-tier eligible on both legacy and new AWS free plans
  iam_instance_profile = aws_iam_instance_profile.artifact_reader.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    bucket    = aws_s3_bucket.artifacts.id
    model_key = local.model_key
    region    = var.region
  })
  # Re-create the instance when the boot script changes so it runs again
  user_data_replace_on_change = true

  tags = {
    Name = "MyEC2Instance"
  }

  # The artifact must exist before the instance tries to download it
  depends_on = [aws_s3_object.sample_model]
}

# Part 4: VPC and a subnet inside it
resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "myvpc"
  }
}

resource "aws_subnet" "mysubnet1" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "mysubnet1"
  }
}
