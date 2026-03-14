# ── Spot Compute Environment ──────────────────────────────────────────────────
# Uses "optimal" instance type — AWS selects the best fit for each job's
# memory and vCPU request. No launch template, no custom AMI.
# This matches the pattern used by proven working Nextflow + Batch setups.
resource "aws_batch_compute_environment" "spot" {
  compute_environment_name = "${var.project_name}-spot-ce"
  type                     = "MANAGED"
  service_role             = aws_iam_role.batch_service_role.arn
  state                    = "ENABLED"

  compute_resources {
    type                = "SPOT"
    allocation_strategy = "SPOT_CAPACITY_OPTIMIZED"
    bid_percentage      = var.spot_bid_percentage

    min_vcpus     = 0
    max_vcpus     = var.max_vcpus
    desired_vcpus = 0

    instance_role = aws_iam_instance_profile.ecs_instance_profile.arn
    instance_type = var.instance_types

    subnets            = local.subnet_ids
    security_group_ids = [aws_security_group.batch.id]
  }

  depends_on = [aws_iam_role_policy_attachment.batch_service_role]
}

# ── On-Demand Fallback Compute Environment ────────────────────────────────────
resource "aws_batch_compute_environment" "ondemand" {
  compute_environment_name = "${var.project_name}-ondemand-ce"
  type                     = "MANAGED"
  service_role             = aws_iam_role.batch_service_role.arn
  state                    = "ENABLED"

  compute_resources {
    type                = "EC2"
    allocation_strategy = "BEST_FIT_PROGRESSIVE"

    min_vcpus     = 0
    max_vcpus     = var.max_vcpus
    desired_vcpus = 0

    instance_role = aws_iam_instance_profile.ecs_instance_profile.arn
    instance_type = var.instance_types

    subnets            = local.subnet_ids
    security_group_ids = [aws_security_group.batch.id]
  }

  depends_on = [aws_iam_role_policy_attachment.batch_service_role]
}

# ── Job Queue ─────────────────────────────────────────────────────────────────
# Spot CE at priority 1 — On-Demand CE as fallback at priority 2.
# Name must match the queue value in nextflow.config.
resource "aws_batch_job_queue" "main" {
  name     = "${var.project_name}-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.spot.arn
  }

  compute_environment_order {
    order               = 2
    compute_environment = aws_batch_compute_environment.ondemand.arn
  }
}

# ── Job Definition ────────────────────────────────────────────────────────────
# Placeholder only — Nextflow overrides image, memory, and vCPU
# per-process at submission time via nextflow.config directives.
# The jobRole here ensures every container gets the right IAM permissions.
resource "aws_batch_job_definition" "main" {
  name = "${var.project_name}-job"
  type = "container"

  platform_capabilities = ["EC2"]

  container_properties = jsonencode({
    image      = var.job_docker_image
    jobRoleArn = aws_iam_role.batch_job_role.arn

    # Minimum placeholder values required by the AWS API.
    # Nextflow replaces these with per-process memory/cpus at runtime.
    resourceRequirements = [
      { type = "VCPU", value = "1" },
      { type = "MEMORY", value = "512" }
    ]

    environment = [
      { name = "AWS_DEFAULT_REGION", value = var.aws_region }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/aws/batch/${var.project_name}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "job"
      }
    }
  })

  retry_strategy {
    attempts = 2
    evaluate_on_exit {
      on_status_reason = "Host EC2 terminated"
      action           = "RETRY"
    }
    evaluate_on_exit {
      on_exit_code = "0"
      action       = "EXIT"
    }
  }

  timeout {
    attempt_duration_seconds = var.job_timeout_seconds
  }
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "batch" {
  name              = "/aws/batch/${var.project_name}"
  retention_in_days = 30
}
