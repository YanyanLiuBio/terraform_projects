#!/bin/bash
# create_credentials.sh
# Quick wrapper for creating S3 temporary credentials

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<EOF
Usage: ./create_credentials.sh PROJECT YYYYMM [BUCKET] [BASE_PATH]

Examples:
  ./create_credentials.sh NEB 202510
  ./create_credentials.sh NEB 202511
  ./create_credentials.sh ACME 202512 my-bucket results

Arguments:
  PROJECT    - Project prefix (e.g., NEB, ACME)
  YYYYMM     - Year and month (e.g., 202510 for October 2025)
  BUCKET     - (optional) S3 bucket name, defaults to 'seqwell'
  BASE_PATH  - (optional) Base path, defaults to 'data'

Creates:
  - IAM user: {PROJECT}_{YYYYMM}
  - S3 access: s3://{BUCKET}/{PROJECT}/{BASE_PATH}/{YYYYMM}/*
  - Expires: 30 days from creation
EOF
    exit 0
fi

# Check arguments
if [[ -z "$1" || -z "$2" ]]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo "Usage: ./create_credentials.sh PROJECT YYYYMM [BUCKET] [BASE_PATH]"
    echo "Run with --help for more information"
    exit 1
fi

PROJECT="$1"
YEAR_MONTH="$2"
BUCKET="${3:-seqwell}"
BASE_PATH="${4:-data}"

echo -e "${YELLOW}Creating credentials...${NC}"
echo "Project:    $PROJECT"
echo "Period:     $YEAR_MONTH"
echo "Bucket:     $BUCKET"
echo "Base Path:  $BASE_PATH"
echo ""

# Check if Terraform is initialized
if [[ ! -d ".terraform" ]]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
fi

# Apply
terraform apply \
    -var="project_prefix=$PROJECT" \
    -var="year_month=$YEAR_MONTH" \
    -var="bucket_name=$BUCKET" \
    -var="base_path=$BASE_PATH"

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Credentials created successfully!${NC}"
    echo ""
    echo "To view credentials:"
    echo "  terraform output credentials"
    echo ""
    echo "To get secret key:"
    echo "  terraform output -raw secret_access_key"
    echo ""
    echo -e "${YELLOW}⚠️  Remember to destroy after 30 days:${NC}"
    echo "  terraform destroy \\"
    echo "    -var=\"project_prefix=$PROJECT\" \\"
    echo "    -var=\"year_month=$YEAR_MONTH\" \\"
    echo "    -var=\"bucket_name=$BUCKET\" \\"
    echo "    -var=\"base_path=$BASE_PATH\""
fi
