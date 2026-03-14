terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Change to your region
}

# Variables - customize these for each run
variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
  default     = "seqwell"
}

variable "project_prefix" {
  description = "Project prefix (e.g., 'NEB')"
  type        = string
}

variable "year_month" {
  description = "Year and month (e.g., '202510' for October 2025)"
  type        = string
}

variable "base_path" {
  description = "Base S3 path"
  type        = string
  default     = "data"
}

# Locals
locals {
  user_name      = "${var.project_prefix}_${var.year_month}"
  policy_name    = "${local.user_name}_policy"
  s3_prefix      = "${var.project_prefix}/${var.base_path}/${var.year_month}"
  expiration     = timeadd(timestamp(), "720h") # 30 days
}

# IAM User
resource "aws_iam_user" "user" {
  name = local.user_name
  
  tags = {
    Project     = var.project_prefix
    Period      = var.year_month
    ExpiresOn   = formatdate("YYYY-MM-DD", local.expiration)
    CreatedBy   = "Terraform"
  }
}

# IAM Policy
resource "aws_iam_policy" "s3_access" {
  name        = local.policy_name
  description = "S3 access for ${local.user_name} - Expires ${formatdate("YYYY-MM-DD", local.expiration)}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowListBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowListSpecificPrefix"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = "${local.s3_prefix}*"
          }
        }
      },
      {
        Sid    = "AllowObjectActions"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/${local.s3_prefix}/*"
      }
    ]
  })
}

# Attach policy to user
resource "aws_iam_user_policy_attachment" "attach" {
  user       = aws_iam_user.user.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# Create access key
resource "aws_iam_access_key" "key" {
  user = aws_iam_user.user.name
}

# Outputs
output "username" {
  value = aws_iam_user.user.name
}

output "access_key_id" {
  value = aws_iam_access_key.key.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.key.secret
  sensitive = true
}

output "s3_path" {
  value = "s3://${var.bucket_name}/${local.s3_prefix}/*"
}

output "expires_on" {
  value = formatdate("YYYY-MM-DD", local.expiration)
}

output "credentials" {
  value = <<-EOT
    
    ==========================================
    AWS Credentials Created
    ==========================================
    Username:    ${aws_iam_user.user.name}
    Access Key:  ${aws_iam_access_key.key.id}
    Secret Key:  [Run: terraform output -raw secret_access_key]
    
    S3 Access:   s3://${var.bucket_name}/${local.s3_prefix}/*
    Expires:     ${formatdate("YYYY-MM-DD", local.expiration)}
    ==========================================
    
    Share with user:
      terraform output -raw secret_access_key
    
  EOT
}
