# Lets the EC2 instance read model artifacts without any access keys on the machine

# Trust policy: only the EC2 service can assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
    statement {
        actions = ["sts:AssumeRole"]
        principals {
            type        = "Service"
            identifiers = ["ec2.amazonaws.com"]
        }
    }
}

# Least privilege: list the bucket and read objects, nothing else
data "aws_iam_policy_document" "artifact_read" {
    statement {
        sid       = "ListArtifactBucket"
        actions   = ["s3:ListBucket"]
        resources = [aws_s3_bucket.artifacts.arn]
    }

    statement {
        sid       = "ReadArtifacts"
        actions   = ["s3:GetObject", "s3:GetObjectVersion"]
        resources = ["${aws_s3_bucket.artifacts.arn}/*"]
    }
}

resource "aws_iam_role" "artifact_reader" {
    name               = "${var.project_name}-artifact-reader"
    assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy" "artifact_read" {
    name   = "artifact-read"
    role   = aws_iam_role.artifact_reader.id
    policy = data.aws_iam_policy_document.artifact_read.json
}

# EC2 attaches roles through an instance profile
resource "aws_iam_instance_profile" "artifact_reader" {
    name = "${var.project_name}-artifact-reader"
    role = aws_iam_role.artifact_reader.name
}
