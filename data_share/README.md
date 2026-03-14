# S3 Temporal Access - One-Time Credentials

Quick Terraform setup for creating temporary S3 access credentials on-demand.

## Usage

### Create credentials for NEB project, October 2025:

```bash
terraform init

terraform apply \
  -var="project_prefix=NEB" \
  -var="year_month=202510"
```

### Get the secret key:

```bash
terraform output -raw secret_access_key
```

### Full credentials display:

```bash
terraform output credentials
```

## Examples

### NEB project, November 2025:
```bash
terraform apply \
  -var="project_prefix=NEB" \
  -var="year_month=202511"
```

### Different project, December 2025:
```bash
terraform apply \
  -var="project_prefix=ACME" \
  -var="year_month=202512"
```

### Custom bucket and path:
```bash
terraform apply \
  -var="project_prefix=NEB" \
  -var="year_month=202510" \
  -var="bucket_name=my-bucket" \
  -var="base_path=results"
```
This creates: `s3://my-bucket/NEB/results/202510/*`

## What Gets Created

- **IAM User**: `{project}_{year_month}` (e.g., `NEB_202510`)
- **IAM Policy**: Grants access to `s3://bucket/{project}/data/{year_month}/*`
- **Access Keys**: AWS credentials for the user
- **Tags**: Expiration date (30 days from creation)

## After 30 Days - Cleanup

```bash
# Delete the user and policy
terraform destroy \
  -var="project_prefix=NEB" \
  -var="year_month=202510"
```

Or manually:
```bash
# Delete access key
aws iam delete-access-key --user-name NEB_202510 --access-key-id AKIA...

# Detach policy
aws iam detach-user-policy --user-name NEB_202510 --policy-arn arn:aws:iam::...:policy/NEB_202510_policy

# Delete policy
aws iam delete-policy --policy-arn arn:aws:iam::...:policy/NEB_202510_policy

# Delete user
aws iam delete-user --user-name NEB_202510
```

## Sharing Credentials

**Option 1: Copy/paste (less secure)**
```bash
echo "Username: $(terraform output -raw username)"
echo "Access Key: $(terraform output -raw access_key_id)"
echo "Secret Key: $(terraform output -raw secret_access_key)"
```

**Option 2: AWS Secrets Manager (more secure)**
```bash
aws secretsmanager create-secret \
  --name "NEB_202510_credentials" \
  --secret-string "{
    \"username\": \"$(terraform output -raw username)\",
    \"access_key\": \"$(terraform output -raw access_key_id)\",
    \"secret_key\": \"$(terraform output -raw secret_access_key)\"
  }"
```

**Option 3: Save to encrypted file**
```bash
cat > creds.txt <<EOF
AWS_ACCESS_KEY_ID=$(terraform output -raw access_key_id)
AWS_SECRET_ACCESS_KEY=$(terraform output -raw secret_access_key)
EOF

# Encrypt
gpg -c creds.txt
rm creds.txt

# Share creds.txt.gpg via email/Slack
# Share password separately
```

## Variables Reference

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `project_prefix` | Project name | *required* | `NEB` |
| `year_month` | YYYYMM format | *required* | `202510` |
| `bucket_name` | S3 bucket | `seqwell` | `my-bucket` |
| `base_path` | Path segment | `data` | `results` |

## Resulting S3 Path Pattern

Default: `s3://seqwell/NEB/data/202510/*`

Pattern: `s3://{bucket_name}/{project_prefix}/{base_path}/{year_month}/*`
