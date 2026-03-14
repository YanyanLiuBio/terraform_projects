output "job_queue_arn" {
  description = "ARN of the Batch job queue"
  value       = aws_batch_job_queue.main.arn
}

output "job_queue_name" {
  description = "Name of the Batch job queue — use this in nextflow.config as the queue value"
  value       = aws_batch_job_queue.main.name
}

output "spot_compute_env_arn" {
  description = "ARN of the Spot compute environment"
  value       = aws_batch_compute_environment.spot.arn
}

output "job_definition_arn" {
  description = "ARN of the Batch job definition"
  value       = aws_batch_job_definition.main.arn
}

output "batch_job_role_arn" {
  description = "ARN of the job role — use this in nextflow.config as aws.batch.jobRole"
  value       = aws_iam_role.batch_job_role.arn
}

output "nextflow_submitter_policy_arn" {
  description = "ARN of the Nextflow submitter policy"
  value       = aws_iam_policy.nextflow_submitter.arn
}

output "nextflow_runner_access_key_id" {
  description = "Access key ID for nextflow.config aws.accessKey"
  value       = aws_iam_access_key.nextflow_runner.id
}

output "nextflow_runner_secret_access_key" {
  description = "Secret access key for nextflow.config aws.secretKey — retrieve with: terraform output -raw nextflow_runner_secret_access_key"
  value       = aws_iam_access_key.nextflow_runner.secret
  sensitive   = true
}
