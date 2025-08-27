```
# Directory Structure:
# .
# ├── main.tf                    (root module)
# ├── variables.tf               (root variables)
# ├── outputs.tf                 (root outputs)
# ├── terraform.tfvars          (variable values)
# └── modules/
#     └── transfer-family/
#         ├── main.tf            (module resources)
#         ├── variables.tf       (module variables)
#         └── outputs.tf         (module outputs)
```
=================================================================
modules/transfer-family/main.tf
=================================================================

Key Features
Module Components:

Transfer Family Server - Configurable with multiple protocols (SFTP, FTP, FTPS)
IAM Role & Policies - For server operations and logging
S3 Bucket - Optional bucket creation with encryption and versioning
CloudWatch Logging - Optional logging configuration
Security Group - For VPC endpoints with configurable access rules
VPC Support - Can deploy as public or VPC endpoint

Variable Passing:

Root to Module: Uses the module block with source path
Flexible Configuration: Supports both public and VPC endpoints
Optional Resources: S3 bucket and logging can be enabled/disabled
Security: Configurable CIDR blocks and protocols

Output Variables:

Server details (ID, ARN, endpoint, host key fingerprint)
S3 bucket information (if created)
IAM role details
Security group ID (for VPC endpoints)
CloudWatch log group name

```
# Data source for getting the current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# IAM role for Transfer Family server
resource "aws_iam_role" "transfer_role" {
  name = "${var.server_name}-transfer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for CloudWatch logging
resource "aws_iam_role_policy" "transfer_logging_policy" {
  count = var.enable_logging ? 1 : 0
  name  = "${var.server_name}-logging-policy"
  role  = aws_iam_role.transfer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/transfer/*"
      }
    ]
  })
}

# CloudWatch Log Group (if logging enabled)
resource "aws_cloudwatch_log_group" "transfer_log_group" {
  count             = var.enable_logging ? 1 : 0
  name              = "/aws/transfer/${var.server_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# S3 bucket for file storage (if create_s3_bucket is true)
resource "aws_s3_bucket" "transfer_bucket" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.server_name}-transfer-bucket-${random_id.bucket_suffix[0].hex}"
  tags   = var.tags
}

resource "random_id" "bucket_suffix" {
  count       = var.create_s3_bucket ? 1 : 0
  byte_length = 4
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "transfer_bucket_versioning" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.transfer_bucket[0].id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "transfer_bucket_encryption" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.transfer_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Security group for Transfer Family server (if using VPC)
resource "aws_security_group" "transfer_sg" {
  count       = var.endpoint_type == "VPC" ? 1 : 0
  name_prefix = "${var.server_name}-transfer-sg"
  description = "Security group for AWS Transfer Family server"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_protocols
    content {
      description = "Allow ${upper(ingress.value)} traffic"
      from_port   = ingress.value == "sftp" ? 22 : (ingress.value == "ftps" ? 21 : 990)
      to_port     = ingress.value == "sftp" ? 22 : (ingress.value == "ftps" ? 21 : 990)
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.server_name}-transfer-sg"
  })
}

# Transfer Family Server
resource "aws_transfer_server" "main" {
  identity_provider_type = var.identity_provider_type
  protocols              = var.allowed_protocols
  endpoint_type          = var.endpoint_type
  domain                 = var.domain

  # VPC endpoint configuration (only if endpoint_type is VPC)
  dynamic "endpoint_details" {
    for_each = var.endpoint_type == "VPC" ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      vpc_id            = var.vpc_id
      security_group_ids = [aws_security_group.transfer_sg[0].id]
      address_allocation_ids = var.address_allocation_ids
    }
  }

  # Logging configuration
  dynamic "workflow_details" {
    for_each = var.enable_logging ? [1] : []
    content {
      on_upload {
        execution_role = aws_iam_role.transfer_role.arn
        workflow_id    = var.workflow_id
      }
    }
  }

  logging_role = var.enable_logging ? aws_iam_role.transfer_role.arn : null

  # Certificate for FTPS
  certificate = var.certificate_arn

  tags = merge(var.tags, {
    Name = var.server_name
  })
}

# =================================================================
# modules/transfer-family/variables.tf
# =================================================================

variable "server_name" {
  description = "Name of the Transfer Family server"
  type        = string
}

variable "identity_provider_type" {
  description = "The mode of authentication enabled for this service"
  type        = string
  default     = "SERVICE_MANAGED"
  validation {
    condition     = contains(["SERVICE_MANAGED", "API_GATEWAY", "AWS_DIRECTORY_SERVICE", "AWS_LAMBDA"], var.identity_provider_type)
    error_message = "Identity provider type must be one of: SERVICE_MANAGED, API_GATEWAY, AWS_DIRECTORY_SERVICE, AWS_LAMBDA."
  }
}

variable "allowed_protocols" {
  description = "List of protocols enabled for the server"
  type        = list(string)
  default     = ["SFTP"]
  validation {
    condition = alltrue([
      for protocol in var.allowed_protocols : contains(["SFTP", "FTP", "FTPS"], protocol)
    ])
    error_message = "Allowed protocols must be one or more of: SFTP, FTP, FTPS."
  }
}

variable "endpoint_type" {
  description = "The type of endpoint that the server will be"
  type        = string
  default     = "PUBLIC"
  validation {
    condition     = contains(["PUBLIC", "VPC", "VPC_ENDPOINT"], var.endpoint_type)
    error_message = "Endpoint type must be one of: PUBLIC, VPC, VPC_ENDPOINT."
  }
}

variable "domain" {
  description = "The domain of the storage system that is used for file transfers"
  type        = string
  default     = "S3"
  validation {
    condition     = contains(["S3", "EFS"], var.domain)
    error_message = "Domain must be either S3 or EFS."
  }
}

variable "vpc_id" {
  description = "VPC ID for VPC endpoint (required if endpoint_type is VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for VPC endpoint (required if endpoint_type is VPC)"
  type        = list(string)
  default     = []
}

variable "address_allocation_ids" {
  description = "List of Elastic IP allocation IDs for VPC endpoint"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ARN of the certificate for FTPS"
  type        = string
  default     = ""
}

variable "enable_logging" {
  description = "Enable CloudWatch logging for the server"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
}

variable "workflow_id" {
  description = "Workflow ID for post-upload processing"
  type        = string
  default     = ""
}

variable "create_s3_bucket" {
  description = "Whether to create an S3 bucket for file storage"
  type        = bool
  default     = true
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket (if create_s3_bucket is true)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}

# =================================================================
# modules/transfer-family/outputs.tf
# =================================================================

output "server_id" {
  description = "ID of the Transfer Family server"
  value       = aws_transfer_server.main.id
}

output "server_arn" {
  description = "ARN of the Transfer Family server"
  value       = aws_transfer_server.main.arn
}

output "server_endpoint" {
  description = "Endpoint of the Transfer Family server"
  value       = aws_transfer_server.main.endpoint
}

output "server_host_key_fingerprint" {
  description = "Host key fingerprint of the server"
  value       = aws_transfer_server.main.host_key_fingerprint
}

output "iam_role_arn" {
  description = "ARN of the IAM role created for the Transfer Family server"
  value       = aws_iam_role.transfer_role.arn
}

output "iam_role_name" {
  description = "Name of the IAM role created for the Transfer Family server"
  value       = aws_iam_role.transfer_role.name
}

output "s3_bucket_id" {
  description = "ID of the S3 bucket (if created)"
  value       = var.create_s3_bucket ? aws_s3_bucket.transfer_bucket[0].id : ""
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket (if created)"
  value       = var.create_s3_bucket ? aws_s3_bucket.transfer_bucket[0].arn : ""
}

output "security_group_id" {
  description = "ID of the security group (if VPC endpoint)"
  value       = var.endpoint_type == "VPC" ? aws_security_group.transfer_sg[0].id : ""
}

output "log_group_name" {
  description = "Name of the CloudWatch log group (if logging enabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.transfer_log_group[0].name : ""
}

# =================================================================
# ROOT MODULE FILES
# =================================================================

# main.tf (root module)
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources for VPC information (if using VPC endpoint)
data "aws_vpc" "main" {
  count = var.use_vpc_endpoint ? 1 : 0
  default = true
}

data "aws_subnets" "main" {
  count = var.use_vpc_endpoint ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main[0].id]
  }
}

module "transfer_family_server" {
  source = "./modules/transfer-family"

  server_name            = var.server_name
  identity_provider_type = var.identity_provider_type
  allowed_protocols      = var.allowed_protocols
  endpoint_type          = var.use_vpc_endpoint ? "VPC" : "PUBLIC"
  domain                 = var.domain

  # VPC configuration (only if using VPC endpoint)
  vpc_id                 = var.use_vpc_endpoint ? data.aws_vpc.main[0].id : ""
  subnet_ids             = var.use_vpc_endpoint ? data.aws_subnets.main[0].ids : []
  allowed_cidr_blocks    = var.allowed_cidr_blocks

  # S3 configuration
  create_s3_bucket     = var.create_s3_bucket
  s3_bucket_name       = var.s3_bucket_name
  enable_s3_versioning = var.enable_s3_versioning

  # Logging configuration
  enable_logging       = var.enable_logging
  log_retention_days   = var.log_retention_days

  # Certificate for FTPS (if using FTPS)
  certificate_arn = var.certificate_arn

  tags = var.tags
}

# =================================================================
# variables.tf (root module)
# =================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "server_name" {
  description = "Name of the Transfer Family server"
  type        = string
}

variable "identity_provider_type" {
  description = "The mode of authentication enabled for this service"
  type        = string
  default     = "SERVICE_MANAGED"
}

variable "allowed_protocols" {
  description = "List of protocols enabled for the server"
  type        = list(string)
  default     = ["SFTP"]
}

variable "use_vpc_endpoint" {
  description = "Whether to use VPC endpoint instead of public endpoint"
  type        = bool
  default     = false
}

variable "domain" {
  description = "The domain of the storage system that is used for file transfers"
  type        = string
  default     = "S3"
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "create_s3_bucket" {
  description = "Whether to create an S3 bucket for file storage"
  type        = bool
  default     = true
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket (if create_s3_bucket is true)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Enable CloudWatch logging for the server"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
}

variable "certificate_arn" {
  description = "ARN of the certificate for FTPS"
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}

# =================================================================
# outputs.tf (root module)
# =================================================================

output "transfer_server_id" {
  description = "ID of the Transfer Family server"
  value       = module.transfer_family_server.server_id
}

output "transfer_server_arn" {
  description = "ARN of the Transfer Family server"
  value       = module.transfer_family_server.server_arn
}

output "transfer_server_endpoint" {
  description = "Endpoint of the Transfer Family server"
  value       = module.transfer_family_server.server_endpoint
}

output "transfer_server_host_key_fingerprint" {
  description = "Host key fingerprint of the server"
  value       = module.transfer_family_server.server_host_key_fingerprint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket created for file storage"
  value       = module.transfer_family_server.s3_bucket_id
}

output "iam_role_arn" {
  description = "ARN of the IAM role for the Transfer Family server"
  value       = module.transfer_family_server.iam_role_arn
}

# =================================================================
# terraform.tfvars (example values)
# =================================================================

aws_region             = "us-east-1"
server_name           = "my-transfer-server"
identity_provider_type = "SERVICE_MANAGED"
allowed_protocols     = ["SFTP"]
use_vpc_endpoint      = false
domain                = "S3"
allowed_cidr_blocks   = ["0.0.0.0/0"]
create_s3_bucket      = true
s3_bucket_name        = ""  # Will auto-generate if empty
enable_s3_versioning  = false
enable_logging        = true
log_retention_days    = 14
certificate_arn       = ""  # Only needed for FTPS

tags = {
  Environment = "dev"
  Project     = "file-transfer"
  Owner       = "devops-team"
}
```
