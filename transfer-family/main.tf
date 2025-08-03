
# Main Terraform configuration for AWS Transfer Family SFTP server

terraform {
  required_version = "~> 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.5.0"
    }
  }
  backend "s3" {
    bucket         = "jmf-dev-us-east-01-tfstate"
    key            = "dev/sftp-server/terraform.tfstate"
    encrypt        = true
    dynamodb_table = "jmf-dev-us-east-01-tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region
}


# 1. S3 Bucket for Storage
resource "aws_s3_bucket" "sftp_bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "sftp_bucket_block" {
  bucket = aws_s3_bucket.sftp_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create partner-specific folders
resource "aws_s3_object" "partner_folders" {
  for_each = var.partners
  bucket   = aws_s3_bucket.sftp_bucket.id
  key      = "${each.key}/"
  content  = ""
}

# 2. VPC Setup
resource "aws_vpc" "sftp_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "sftp-vpc"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.sftp_vpc.id
  cidr_block        = var.subnet_1_cidr
  availability_zone = "${var.aws_region}a"
  tags = {
    Name = "sftp-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.sftp_vpc.id
  cidr_block        = var.subnet_2_cidr
  availability_zone = "${var.aws_region}b"
  tags = {
    Name = "sftp-public-subnet-2"
  }
}

resource "aws_internet_gateway" "sftp_igw" {
  vpc_id = aws_vpc.sftp_vpc.id
  tags = {
    Name = "sftp-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.sftp_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sftp_igw.id
  }
  tags = {
    Name = "sftp-public-route-table"
  }
}

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# 3. Security Group for SFTP
resource "aws_security_group" "sftp_sg" {
  vpc_id = aws_vpc.sftp_vpc.id
  name   = "sftp-security-group"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sftp-security-group"
  }
}

# 4. Network Load Balancer (NLB) with Elastic IP
resource "aws_eip" "sftp_eip" {
  domain = "vpc"
  tags = {
    Name = "sftp-eip"
  }
}

resource "aws_lb" "sftp_nlb" {
  name               = "sftp-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  tags = {
    Name = "sftp-nlb"
  }
}

resource "aws_lb_target_group" "sftp_target_group" {
  name        = "sftp-target-group"
  port        = 22
  protocol    = "TCP"
  vpc_id      = aws_vpc.sftp_vpc.id
  target_type = "ip"
  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "sftp_listener" {
  load_balancer_arn = aws_lb.sftp_nlb.arn
  port              = 22
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sftp_target_group.arn
  }
}

# 5. AWS Transfer Family SFTP Server
resource "aws_transfer_server" "sftp_server" {
  identity_provider_type = "SERVICE_MANAGED"
  endpoint_type          = "VPC"
  endpoint_details {
    vpc_id             = aws_vpc.sftp_vpc.id
    subnet_ids         = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
    security_group_ids = [aws_security_group.sftp_sg.id]
  }
  protocols = ["SFTP"]
  logging_role = aws_iam_role.transfer_logging_role.arn
  tags = {
    Name = "sftp-server"
  }
}

# # 6. Route 53 Configuration
# resource "aws_route53_zone" "sftp_zone" {
#   name = var.domain_name
# }

# resource "aws_route53_record" "sftp_alias" {
#   zone_id = aws_route53_zone.sftp_zone.zone_id
#   name    = var.domain_name
#   type    = "A"
#   alias {
#     name                   = aws_lb.sftp_nlb.dns_name
#     zone_id                = aws_lb.sftp_nlb.zone_id
#     evaluate_target_health = true
#   }
# }

# 7. IAM Roles and Policies
resource "aws_iam_role" "transfer_logging_role" {
  name = "TransferLoggingRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "transfer_logging_policy" {
  name = "TransferLoggingPolicy"
  role = aws_iam_role.transfer_logging_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "transfer_s3_role" {
  name = "TransferS3Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "transfer_s3_policy" {
  name = "TransferS3AccessPolicy"
  role = aws_iam_role.transfer_s3_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sftp_bucket.arn,
          "${aws_s3_bucket.sftp_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "partner_policies" {
  for_each = var.partners
  name     = "${each.key}S3Policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.sftp_bucket.arn}/${each.key}/*"
        Condition = {
          StringLike = {
            "s3:prefix" = "${each.key}/*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.sftp_bucket.arn
        Condition = {
          StringLike = {
            "s3:prefix" = "${each.key}/"
          }
        }
      }
    ]
  })
}

# 8. AWS Transfer Family Users
resource "aws_transfer_user" "sftp_users" {
  for_each       = var.partners
  server_id      = aws_transfer_server.sftp_server.id
  user_name      = each.key
  role           = aws_iam_role.transfer_s3_role.arn
  policy         = aws_iam_policy.partner_policies[each.key].policy
  home_directory_type = "LOGICAL"
  home_directory_mappings {
    entry  = "/"
    target = "/${aws_s3_bucket.sftp_bucket.id}/${each.key}"
  }
}

resource "aws_transfer_ssh_key" "sftp_user_ssh_key" {
  for_each       = var.partners
  server_id      = aws_transfer_server.sftp_server.id
  user_name = each.key
  body      = each.value.ssh_public_key
}
