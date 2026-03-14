# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  count      = var.create_vpc ? 1 : 0
  cidr_block = "10.0.0.0/16"

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-vpc" }
}

# ── Subnets ───────────────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = var.create_vpc ? 2 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Batch instances need to reach AWS APIs (S3, ECS, ECR).
  # map_public_ip_on_launch = true is the simplest setup.
  # For production, use private subnets + NAT gateway.
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-subnet-${count.index}" }
}

data "aws_availability_zones" "available" {}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  tags   = { Name = "${var.project_name}-igw" }
}

# ── Route Table ───────────────────────────────────────────────────────────────
resource "aws_route_table" "main" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = { Name = "${var.project_name}-rt" }
}

resource "aws_route_table_association" "private" {
  count          = var.create_vpc ? 2 : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.main[0].id
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "batch" {
  name        = "${var.project_name}-batch-sg"
  description = "Security group for Batch compute environment"
  vpc_id      = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id

  # Allow all outbound — needed for:
  # - Pulling Docker images from DockerHub / ECR
  # - Reaching S3, ECS, Batch AWS APIs
  # - Downloading packages during setup
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "${var.project_name}-batch-sg" }
}
