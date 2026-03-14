locals {
  subnet_ids = var.create_vpc ? aws_subnet.private[*].id : var.existing_subnet_ids
}
