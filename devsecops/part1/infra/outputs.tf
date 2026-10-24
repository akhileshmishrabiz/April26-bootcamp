output "bucket_name" {
  description = "S3 bucket used by the sample application"
  value       = aws_s3_bucket.uploads.id
}

output "queue_url" {
  description = "SQS queue used by the sample application"
  value       = aws_sqs_queue.jobs.url
}

output "kms_key_arn" {
  description = "KMS key created for the security exercise"
  value       = aws_kms_key.lab.arn
}
