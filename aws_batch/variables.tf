variable "aws_region" {
  description = "AWS region to deploy all resources into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "seqwell-batch"
}

variable "create_vpc" {
  description = "Set to true to create a new VPC. Set to false to use an existing VPC."
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID of an existing VPC. Only used when create_vpc = false."
  type        = string
  default     = ""
}

variable "existing_subnet_ids" {
  description = "List of existing subnet IDs. Only used when create_vpc = false."
  type        = list(string)
  default     = []
}

variable "instance_types" {
  description = <<-EOT
    EC2 instance types available to the compute environment.
    Use ["optimal"] to let AWS pick the best fit for each job's
    memory and vCPU request — this is the recommended setting and
    matches the pattern used by working Nextflow + Batch setups.
    You can also specify explicit types to control costs.
  EOT
  type        = list(string)
  default     = ["optimal"]
}

variable "max_vcpus" {
  description = "Maximum total vCPUs across the compute environment. Acts as a cost cap."
  type        = number
  default     = 256
}

variable "spot_bid_percentage" {
  description = "Maximum Spot price as a percentage of the On-Demand price (1-100)."
  type        = number
  default     = 100
}

variable "job_docker_image" {
  description = "Fallback Docker image for the base job definition. Nextflow always overrides this per-process."
  type        = string
  default     = "amazonlinux:2"
}

variable "job_timeout_seconds" {
  description = <<-EOT
    Maximum job runtime in seconds before Batch forcefully terminates it.
    Default is 7 days — intentionally high so long-running workflows
    are never killed by the infrastructure.
  EOT
  type        = number
  default     = 604800
}

variable "s3_arns" {
  description = <<-EOT
    Optional list of S3 bucket ARNs to grant job containers read/write access.
    Input and output buckets can be different — add both.
    Leave empty [] if your jobs do not use S3.

    Example:
      s3_arns = [
        "arn:aws:s3:::seqwell-dev",
        "arn:aws:s3:::seqwell-dev/*",
        "arn:aws:s3:::seqwell-fastq",
        "arn:aws:s3:::seqwell-fastq/*",
        "arn:aws:s3:::seqwell-analysis",
        "arn:aws:s3:::seqwell-analysis/*",
      ]
  EOT
  type        = list(string)
  default     = []
}
