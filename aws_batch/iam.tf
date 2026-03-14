# ── ECS Instance Role ────────────────────────────────────────────────────────
# Attached to every EC2 instance that joins the Batch compute environment.
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.project_name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecr" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.project_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# ── Batch Service Role ────────────────────────────────────────────────────────
# Used by the AWS Batch service itself to manage compute resources.
resource "aws_iam_role" "batch_service_role" {
  name = "${var.project_name}-batch-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "batch.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "batch_service_role" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# ── Batch Job Role ────────────────────────────────────────────────────────────
# Attached to every running container (ECS task) submitted by Batch.
# Covers both the Nextflow head job and all child process jobs.
resource "aws_iam_role" "batch_job_role" {
  name = "${var.project_name}-batch-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "batch_job_ecr" {
  role       = aws_iam_role.batch_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy" "batch_job_nextflow" {
  name = "${var.project_name}-nextflow-job-policy"
  role = aws_iam_role.batch_job_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BatchChildJobs"
        Effect = "Allow"
        Action = [
          "batch:SubmitJob",
          "batch:DescribeJobs",
          "batch:DescribeJobQueues",
          "batch:DescribeJobDefinitions",
          "batch:ListJobs",
          "batch:TerminateJob",
          "batch:CancelJob",
          "batch:RegisterJobDefinition"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Staging"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = length(var.s3_arns) > 0 ? var.s3_arns : ["arn:aws:s3:::placeholder-never-used"]
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Nextflow Submitter Policy ─────────────────────────────────────────────────
# Defines exactly what the Nextflow pipeline is allowed to do.
# Attached to the nextflow-runner service account below.
resource "aws_iam_policy" "nextflow_submitter" {
  name        = "${var.project_name}-nextflow-submitter"
  description = "Scoped permissions for the Nextflow pipeline service account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BatchAccess"
        Effect = "Allow"
        Action = [
          "batch:SubmitJob",
          "batch:DescribeJobs",
          "batch:DescribeJobQueues",
          "batch:DescribeJobDefinitions",
          "batch:ListJobs",
          "batch:TerminateJob",
          "batch:CancelJob",
          "batch:RegisterJobDefinition",
          "batch:DeregisterJobDefinition"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3WorkDir"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = length(var.s3_arns) > 0 ? var.s3_arns : ["arn:aws:s3:::placeholder-never-used"]
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Nextflow Runner Service Account ──────────────────────────────────────────
# A dedicated IAM user that exists solely to run Nextflow pipelines.
# NOT a human user — a service account.
# Its access key goes in nextflow.config so any human user (even one
# with very limited IAM permissions) can run pipelines.
resource "aws_iam_user" "nextflow_runner" {
  name = "${var.project_name}-nextflow-runner"
  tags = {
    Purpose = "Nextflow pipeline execution service account - not a human user"
    Project = var.project_name
  }
}

resource "aws_iam_user_policy_attachment" "nextflow_runner" {
  user       = aws_iam_user.nextflow_runner.name
  policy_arn = aws_iam_policy.nextflow_submitter.arn
}

resource "aws_iam_access_key" "nextflow_runner" {
  user = aws_iam_user.nextflow_runner.name
}


resource "aws_iam_role_policy" "ecs_instance_s3" {
  name = "${var.project_name}-ecs-instance-s3"
  role = aws_iam_role.ecs_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "S3BatchAccess"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = length(var.s3_arns) > 0 ? var.s3_arns : ["arn:aws:s3:::placeholder-never-used"]
    }]
  })
}
