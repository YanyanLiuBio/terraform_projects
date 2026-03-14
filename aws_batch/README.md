# AWS Batch + Nextflow Terraform Infrastructure

> Spot Instances · ECS · Docker · AWS CLI · S3 · Nextflow

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [File Structure](#file-structure)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Nextflow Integration](#nextflow-integration)
- [IAM & Security](#iam--security)
- [Troubleshooting](#troubleshooting)
- [Cost Optimization](#cost-optimization)
- [Quick Reference](#quick-reference)

---

## Overview

This Terraform project provisions a fully managed, general-purpose AWS Batch compute infrastructure for running Nextflow bioinformatics pipelines on AWS. It is designed to be **set once and used indefinitely** — the infrastructure makes no assumptions about data location, memory requirements, or pipeline type.

Key design principles:

- **Data is workflow-defined** — input can come from local paths, S3, or any mounted source. Output can go anywhere. All paths are declared in your Nextflow workflow, not in Terraform.
- **Resources are job-defined** — memory and vCPU are declared per-process in `nextflow.config`. The infrastructure supports jobs from **2 GB to 128 GB+** without any changes.
- **Infrastructure is long-lived** — deploy once, run any pipeline. No Terraform changes needed between runs.
- **Any user can run pipelines** — a dedicated service account handles all AWS permissions. The human user's own IAM permissions are irrelevant.
- **No AWS CLI required in containers** — Nextflow uses the CLI on the host EC2 instance via `cliPath`, so any plain Docker image works without modification.

---

## Architecture

```
Nextflow Pipeline (any workflow, any data source)
       │
       ▼
Job Queue: <project_name>-queue
       │
       ├── Priority 1 ──▶ Spot Compute Environment   (SPOT_CAPACITY_OPTIMIZED)
       │                        │
       └── Priority 2 ──▶ On-Demand Compute Environment (fallback)
                                │
                         EC2 Instances (ECS-Optimized AMI)
                           ├── Docker     (pre-installed)
                           ├── AWS CLI    (/usr/bin/aws — used by Nextflow for S3 staging)
                           └── instance_type = "optimal" (AWS picks best fit per job)
```

| Component | Description |
|---|---|
| **Job Queue** | `<project_name>-queue` — Spot CE at priority 1, On-Demand CE at priority 2 |
| **Spot CE** | `SPOT_CAPACITY_OPTIMIZED` — minimizes interruptions for longer jobs |
| **On-Demand CE** | `BEST_FIT_PROGRESSIVE` — fallback when Spot capacity is unavailable |
| **EC2 AMI** | ECS-Optimized Amazon Linux 2 — managed by AWS, always up to date |
| **Instance type** | `optimal` — AWS selects best fit for each job's memory + vCPU request |
| **AWS CLI** | Pre-installed on host at `/usr/bin/aws` — mounted into containers by Nextflow |
| **Storage** | Defined per workflow — local, S3, or any mounted path |
| **Credentials** | `nextflow-runner` service account key in `nextflow.config` |

---

## File Structure

```
terraform_project/
  ├── main.tf               # Provider and Terraform configuration
  ├── batch.tf              # Compute environments, job queue, job definition
  ├── iam.tf                # Roles, policies, and nextflow-runner service account
  ├── networking.tf         # VPC, subnets, security groups
  ├── locals.tf             # Local values (subnet_ids)
  ├── variables.tf          # All input variables with defaults
  ├── outputs.tf            # Output values after apply
  └── terraform.tfvars      # Your environment-specific values
```

> ℹ️ There is no `launch_template.tf` — this stack uses the default ECS-optimized AMI with no custom user_data. This is the simplest and most reliable pattern for Nextflow + AWS Batch.

---

## Prerequisites

### Tools Required

- Terraform >= 1.3
- AWS CLI v2 configured locally (`aws configure`)
- Java 17+ installed locally (required by Nextflow)
- Nextflow installed locally

### AWS Permissions for Terraform

The IAM user or role running `terraform apply` needs:

- `AWSBatchFullAccess`
- `AmazonEC2FullAccess`
- `IAMFullAccess`
- `CloudWatchLogsFullAccess`

> ℹ️ These are only needed by the person running Terraform — not by users running pipelines.

### Existing Resources

| Resource | Notes |
|---|---|
| VPC + Subnets | Or set `create_vpc = true` to have Terraform create them |
| S3 Buckets | Add all bucket ARNs to `s3_arns` in `terraform.tfvars` |
| ECR Repository | Only needed if your workflows use private ECR images |

---

## Configuration

### terraform.tfvars

```hcl
project_name        = "seqwell-batch"
aws_region          = "us-east-1"
create_vpc          = true
max_vcpus           = 256
spot_bid_percentage = 100
instance_types      = ["optimal"]

# Add every S3 bucket your pipelines read from or write to
s3_arns = [
  "arn:aws:s3:::seqwell-dev",
  "arn:aws:s3:::seqwell-dev/*",
  "arn:aws:s3:::seqwell-fastq",
  "arn:aws:s3:::seqwell-fastq/*",
  "arn:aws:s3:::seqwell-analysis",
  "arn:aws:s3:::seqwell-analysis/*",
]
```

### All Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `project_name` | string | `batch-nextflow` | Prefix for all resource names |
| `aws_region` | string | `us-east-1` | AWS region to deploy into |
| `create_vpc` | bool | `true` | Whether to create a new VPC |
| `existing_vpc_id` | string | `""` | Use when `create_vpc = false` |
| `existing_subnet_ids` | list(string) | `[]` | Use when `create_vpc = false` |
| `instance_types` | list(string) | `["optimal"]` | `optimal` lets AWS pick best fit per job |
| `max_vcpus` | number | `256` | Max total vCPUs — acts as a cost cap |
| `spot_bid_percentage` | number | `100` | Max Spot price as % of On-Demand |
| `job_docker_image` | string | `amazonlinux:2` | Fallback image — Nextflow overrides per-process |
| `job_timeout_seconds` | number | `604800` | Max job runtime — 7 days default |
| `s3_arns` | list(string) | `[]` | S3 bucket ARNs for both instance role and job role |

---

## Deployment

### Encrypt Terraform State First

The service account secret key is stored in Terraform state. Add an encrypted S3 backend to `main.tf`:

```hcl
terraform {
  backend "s3" {
    bucket  = "my-terraform-state-bucket"
    key     = "seqwell-batch/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
```

### Apply

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Get Service Account Credentials

After apply, populate `nextflow.config` with the service account credentials:

```bash
terraform output nextflow_runner_access_key_id
terraform output -raw nextflow_runner_secret_access_key
terraform output batch_job_role_arn
```

### Expected Outputs

```
batch_job_role_arn                = "arn:aws:iam::XXXX:role/seqwell-batch-batch-job-role"
job_definition_arn                = "arn:aws:batch:us-east-1:XXXX:job-definition/..."
job_queue_arn                     = "arn:aws:batch:us-east-1:XXXX:job-queue/seqwell-batch-queue"
job_queue_name                    = "seqwell-batch-queue"
nextflow_runner_access_key_id     = "AKIAIOSFODNN7EXAMPLE"
nextflow_runner_secret_access_key = <sensitive>
batch_job_role_arn                = "arn:aws:iam::XXXX:role/seqwell-batch-batch-job-role"
```

### Tear Down

```bash
terraform destroy
```

> ⚠️ This deletes all Batch resources and the service account key. S3 buckets and ECR repositories are not deleted.

---

## Nextflow Integration

### How AWS CLI Staging Works

Nextflow needs AWS CLI to stage files between S3 and the running container. It does **not** need to be installed inside each container image. Instead, set `cliPath` to the path on the **host EC2 instance** — Nextflow mounts it into the container automatically:

```
cliPath = '/usr/bin/aws'    ← path on the EC2 host instance
                               Nextflow mounts this into every container
                               Your container image needs NO AWS CLI
```

| Approach | AWS CLI in every image? | Notes |
|---|---|---|
| `cliPath` = path inside container | Yes — every image needs it | Hard to maintain at scale |
| `cliPath` = path on host instance | No — host CLI is mounted in | **Recommended — use any plain Docker image** |

### nextflow.config

```groovy
aws {
    accessKey = 'REPLACE_WITH_ACCESS_KEY'    // terraform output nextflow_runner_access_key_id
    secretKey = 'REPLACE_WITH_SECRET_KEY'    // terraform output -raw nextflow_runner_secret_access_key
    region    = 'us-east-1'

    batch {
        cliPath = '/usr/bin/aws'             // AWS CLI on the host EC2 instance — no CLI needed in containers
        jobRole = 'REPLACE_WITH_JOB_ROLE'   // terraform output batch_job_role_arn
    }

    client {
        maxConnections     = 20
        uploadStorageClass = 'INTELLIGENT_TIERING'
    }
}

docker {
    enabled = true
}

process {
    // Each process declares its own memory and cpus.
    // Use any plain Docker image — no AWS CLI required inside the container.

    withName: fastqc {
        memory    = '7.GB'
        cpus      = 2
        executor  = 'awsbatch'
        queue     = 'seqwell-batch-queue'
        container = 'biocontainers/fastqc:v0.11.9'    // plain image, no AWS CLI needed
    }
    withName: multiqc {
        memory    = '4.GB'
        cpus      = 2
        executor  = 'awsbatch'
        queue     = 'seqwell-batch-queue'
        container = 'ewels/multiqc:latest'             // plain image, no AWS CLI needed
    }
    withName: get_ATCG_counts {
        memory    = '7.GB'
        cpus      = 2
        executor  = 'awsbatch'
        queue     = 'seqwell-batch-queue'
        container = '512431263418.dkr.ecr.us-east-1.amazonaws.com/python-pandas'
    }
}
```

### How Resource Allocation Works

Terraform job definition has placeholder values (`1 vCPU / 512 MB`) required by the AWS API. Nextflow overrides per-process at runtime. With `instance_types = ["optimal"]`, AWS picks the right instance automatically:

```
Job requests  2G / 1 vCPU  →  AWS picks a small  instance  ( 8 GB /  2 vCPU)
Job requests  7G / 2 vCPU  →  AWS picks a medium instance  (16 GB /  4 vCPU)
Job requests 28G / 4 vCPU  →  AWS picks a large  instance  (32 GB /  8 vCPU)
Job requests 58G / 8 vCPU  →  AWS picks an xlarge instance (64 GB / 16 vCPU)
```

### Data Sources

Input and output paths are fully workflow-defined — no Terraform changes needed:

```groovy
// Local data
params.input  = '/data/fastq/'
params.outdir = '/results/'

// S3 — input and output can be completely different buckets
params.input  = 's3://seqwell-fastq/runs/20250710/'
params.outdir = 's3://seqwell-analysis/results/20250710/'
```

### Example Run Script

```bash
#!/bin/bash
run=20250710_MiSeq-i100
plate=Twist_demuxed_trimmed_FASTQ

nextflow run /software/nextflow-fastqc/fastqc.nf \
  -work-dir s3://seqwell-dev/fastq/work/$run/work/ \
  --run $run \
  --plate $plate \
  -bg -resume
```

---

## IAM & Security

### What iam.tf Creates

| Resource | Type | Description |
|---|---|---|
| `ecs-instance-role` | IAM Role | Allows EC2 instances to join ECS/Batch, pull ECR images, access S3 |
| `batch-service-role` | IAM Role | Used by AWS Batch to manage compute resources |
| `batch-job-role` | IAM Role | Attached to running containers — S3 staging, child job submit, ECR pull, CloudWatch |
| `nextflow-submitter` | IAM Policy | Scoped permissions for the pipeline service account |
| `nextflow-runner` | IAM User + Key | Service account — key goes in `nextflow.config` |

### Why Both Instance Role and Job Role Need S3 Access

Both roles are granted S3 access via the same `s3_arns` variable:

- **`ecs-instance-role`** — used by the EC2 instance itself for S3 staging (downloading `.command.run`, uploading `.command.log`)
- **`batch-job-role`** — used by the container process for reading inputs and writing outputs

If either is missing S3 access, you will see `AccessDenied` errors in CloudWatch logs.

### Security Notes

- **Service account key stored in Terraform state** — use an encrypted S3 backend
- **All S3 access is explicit** — only buckets listed in `s3_arns` are accessible
- **No inbound SSH** — instances are managed via SSM (SSM policy attached to instance role)
- **Spot draining** — graceful job handoff on Spot interruption via instance role

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Job stuck in `RUNNABLE` | Compute environment `INVALID` | Check `aws batch describe-compute-environments` for status reason |
| `INVALID` — Launch Template UserData not MIME | Old launch template still attached | Remove `launch_template` block from `batch.tf`, destroy and recreate CEs |
| `INVALID` — ECS cluster mismatch | `ECS_CLUSTER` set in user_data | Remove `ECS_CLUSTER` line — Batch sets this automatically |
| Instance launches but never registers to ECS | Wrong instance profile | Verify `ecs-instance-role` has `AmazonEC2ContainerServiceforEC2Role` |
| `download failed: s3://... Forbidden (403)` | Instance role missing S3 access | Add bucket to `s3_arns` and run `terraform apply` |
| `upload failed: s3://... AccessDenied` | Instance role missing S3 access | Same fix — add bucket ARN and `/*` to `s3_arns` |
| `s3:ListBucket AccessDenied` on submitter | Bucket not in `s3_arns` | Add bucket to `s3_arns` in `terraform.tfvars` and apply |
| `vCPU is required` on apply | Empty `resourceRequirements` | Set placeholder `1 vCPU / 512 MB` in job definition |
| `Essential container in task exited` | Container crash — check full logs | Run `aws logs get-log-events` on the job's log stream |
| Java version error running Nextflow locally | Wrong Java version | Install Java 17+: `brew install openjdk@17` |

### Useful Debugging Commands

```bash
# Check compute environment status
aws batch describe-compute-environments \
  --compute-environments seqwell-batch-spot-ce \
  --region us-east-1 \
  --query 'computeEnvironments[*].{Status:status,Reason:statusReason}'

# Check ECS cluster registration
aws batch describe-compute-environments \
  --compute-environments seqwell-batch-spot-ce \
  --region us-east-1 \
  --query 'computeEnvironments[*].ecsClusterArn' \
  --output text | xargs -I{} aws ecs list-container-instances --cluster {} --region us-east-1

# Get full job error
aws batch describe-jobs \
  --jobs <job-id> \
  --region us-east-1 \
  --query 'jobs[0].{Status:status,Reason:statusReason,Container:container.reason}'

# View CloudWatch logs
aws logs tail /aws/batch/seqwell-batch --follow --region us-east-1

# Check S3 permissions on instance role
aws iam get-role-policy \
  --role-name seqwell-batch-ecs-instance-role \
  --policy-name seqwell-batch-ecs-instance-s3 \
  --query 'PolicyDocument.Statement[*].Resource'

# Check which identity is being used
aws sts get-caller-identity
```

---

## Cost Optimization

| Bid % | Savings vs On-Demand | Trade-off |
|---|---|---|
| 60% | ~40% | Balanced — good for most bioinformatics jobs |
| **100% (default)** | **~10-70%** | **Pays current Spot price — most capacity available** |

- `instance_types = ["optimal"]` — AWS bin-packs jobs across instance families for best cost efficiency
- `min_vcpus = 0` — scales to zero when no jobs are running, no idle cost
- CloudWatch logs retained **30 days** — adjust `retention_in_days` in `batch.tf`
- Set `max_vcpus` to cap spend if a pipeline submits unexpectedly large job counts
- Use AWS Cost Explorer with tag `Project = seqwell-batch` to track spending

---

## Quick Reference

```bash
# Deploy
terraform init && terraform apply -var-file=terraform.tfvars

# Get credentials for nextflow.config (run once after apply)
terraform output nextflow_runner_access_key_id
terraform output -raw nextflow_runner_secret_access_key
terraform output batch_job_role_arn

# Run a pipeline
run=20250710_MiSeq-i100
plate=Twist_demuxed_trimmed_FASTQ
nextflow run /software/nextflow-fastqc/fastqc.nf \
  -work-dir s3://seqwell-dev/fastq/work/$run/work/ \
  --run $run --plate $plate -bg -resume

# Watch logs
aws logs tail /aws/batch/seqwell-batch --follow --region us-east-1

# Add a new S3 bucket (no destroy needed)
# 1. Add ARNs to s3_arns in terraform.tfvars
# 2. terraform apply --auto-approve

# Destroy
terraform destroy -var-file=terraform.tfvars
```
