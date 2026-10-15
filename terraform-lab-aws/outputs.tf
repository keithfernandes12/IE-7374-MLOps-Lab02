output "instance_id" {
    value = aws_instance.myec2.id
}

output "ami_id" {
    value = data.aws_ami.ubuntu.id
}

output "artifact_bucket" {
    value = aws_s3_bucket.artifacts.id
}

output "model_artifact_uri" {
    value = "s3://${aws_s3_bucket.artifacts.id}/${aws_s3_object.sample_model.key}"
}

output "model_artifact_version_id" {
    description = "S3 version ID of the current model artifact"
    value       = aws_s3_object.sample_model.version_id
}

output "artifact_reader_role_arn" {
    value = aws_iam_role.artifact_reader.arn
}
