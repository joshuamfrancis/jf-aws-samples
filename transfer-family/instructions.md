Below is a Terraform script to set up an AWS Transfer Family SFTP server with Amazon S3 as the storage backend, where each user is restricted to a specific directory within the same S3 bucket. The script includes the necessary IAM roles, policies, S3 bucket, and user configurations. It assumes two users (`user1` and `user2`) with SSH public keys, each restricted to their own directory (e.g., `/my-sftp-bucket/user1` and `/my-sftp-bucket/user2`).

---

### **Terraform Script**

```hcl
# Terraform configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS provider configuration
provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for SFTP storage"
  default     = "my-sftp-bucket"
}

variable "user1_ssh_key" {
  description = "SSH public key for user1"
  type        = string
}

variable "user2_ssh_key" {
  description = "SSH public key for user2"
  type        = string
}

# S3 bucket for SFTP storage
resource "aws_s3_bucket" "sftp_bucket" {
  bucket = var.bucket_name

  tags = {
    Name = "SFTP Bucket"
  }
}

# Block public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "sftp_bucket_block" {
  bucket = aws_s3_bucket.sftp_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for AWS Transfer Family
resource "aws_iam_role" "transfer_role" {
  name = "sftp-transfer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "SFTP Transfer Role"
  }
}

# IAM policy for S3 access with user-specific directory restrictions
resource "aws_iam_policy" "transfer_s3_policy" {
  name        = "sftp-s3-access-policy"
  description = "Policy to allow SFTP users access to their specific S3 directory"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = "${aws_transfer_user.user1.user_name}/*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion",
          "s3:PutObjectAcl"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/${aws_transfer_user.user1.user_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = "${aws_transfer_user.user2.user_name}/*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion",
          "s3:PutObjectAcl"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/${aws_transfer_user.user2.user_name}/*"
      }
    ]
  })
}

# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "transfer_s3_policy_attachment" {
  role       = aws_iam_role.transfer_role.name
  policy_arn = aws_iam_policy.transfer_s3_policy.arn
}

# S3 bucket policy to allow the IAM role access
resource "aws_s3_bucket_policy" "sftp_bucket_policy" {
  bucket = aws_s3_bucket.sftp_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.transfer_role.arn
        }
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      }
    ]
  })
}

# AWS Transfer Family SFTP server
resource "aws_transfer_server" "sftp_server" {
  protocols               = ["SFTP"]
  identity_provider_type = "SERVICE_MANAGED"
  endpoint_type          = "PUBLIC"

  tags = {
    Name = "SFTP Server"
  }
}

# SFTP user1 configuration
resource "aws_transfer_user" "user1" {
  server_id = aws_transfer_server.sftp_server.id
  user_name = "user1"
  role      = aws_iam_role.transfer_role.arn

  home_directory_type = "PATH"
  home_directory      = "/${var.bucket_name}/user1"

  # Restrict user to their home directory
  home_directory_mappings = [
    {
      entry  = "/"
      target = "/${var.bucket_name}/user1"
    }
  ]
}

# SSH public key for user1
resource "aws_transfer_ssh_key" "user1_ssh_key" {
  server_id = aws_transfer_server.sftp_server.id
  user_name = aws_transfer_user.user1.user_name
  body      = var.user1_ssh_key
}

# SFTP user2 configuration
resource "aws_transfer_user" "user2" {
  server_id = aws_transfer_server.sftp_server.id
  user_name = "user2"
  role      = aws_iam_role.transfer_role.arn

  home_directory_type = "PATH"
  home_directory      = "/${var.bucket_name}/user2"

  # Restrict user to their home directory
  home_directory_mappings = [
    {
      entry  = "/"
      target = "/${var.bucket_name}/user2"
    }
  ]
}

# SSH public key for user2
resource "aws_transfer_ssh_key" "user2_ssh_key" {
  server_id = aws_transfer_server.sftp_server.id
  user_name = aws_transfer_user.user2.user_name
  body      = var.user2_ssh_key
}

# Outputs
output "sftp_server_endpoint" {
  description = "Endpoint of the SFTP server"
  value       = aws_transfer_server.sftp_server.endpoint
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.sftp_bucket.bucket
}
```

---

### **Explanation of the Script**

1. **Provider and Variables**:
   - The script uses the AWS provider and defines variables for the region, S3 bucket name, and SSH public keys for `user1` and `user2`.
   - Replace `var.user1_ssh_key` and `var.user2_ssh_key` with actual SSH public keys (e.g., generated using `ssh-keygen`).

2. **S3 Bucket**:
   - Creates an S3 bucket (`my-sftp-bucket`) and blocks public access for security.
   - Applies a bucket policy to allow the IAM role to perform necessary actions.

3. **IAM Role and Policy**:
   - Creates an IAM role (`sftp-transfer-role`) with a trust relationship for `transfer.amazonaws.com`.
   - Attaches a policy that restricts each user to their specific directory (`user1/*` or `user2/*`) using the `${aws_transfer_user.user1.user_name}` variable for dynamic prefixing.
   - The policy allows actions like `ListBucket`, `PutObject`, `GetObject`, etc., scoped to the user’s directory.

4. **SFTP Server**:
   - Creates an SFTP server with a public endpoint and service-managed identity provider.
   - Uses Amazon S3 as the storage backend.

5. **Users**:
   - Configures two users (`user1` and `user2`) with:
     - The IAM role for S3 access.
     - Home directory set to `/my-sftp-bucket/user1` and `/my-sftp-bucket/user2`, respectively.
     - `home_directory_mappings` to enforce chroot-like restrictions (users see their directory as `/`).
   - Adds SSH public keys for authentication.

6. **Outputs**:
   - Provides the SFTP server endpoint and S3 bucket name for reference.

---

### **Prerequisites**
1. **Terraform Installed**: Ensure Terraform is installed (version 1.5+ recommended).
2. **AWS Credentials**: Configure AWS credentials (e.g., via `aws configure` or environment variables).
3. **SSH Public Keys**: Generate SSH key pairs for `user1` and `user2` using:
   ```bash
   ssh-keygen -t rsa -b 4096 -f user1_key
   ssh-keygen -t rsa -b 4096 -f user2_key
   ```
   Copy the contents of `user1_key.pub` and `user2_key.pub` for the `user1_ssh_key` and `user2_ssh_key` variables.

---

### **How to Use**
1. **Save the Script**: Save the script as `main.tf`.
2. **Create a Variables File** (`terraform.tfvars`):
   ```hcl
   region        = "us-east-1"
   bucket_name   = "my-sftp-bucket"
   user1_ssh_key = "ssh-rsa AAAAB3NzaC1yc2E... user1@example.com"
   user2_ssh_key = "ssh-rsa AAAAB3NzaC1yc2E... user2@example.com"
   ```
   Replace the SSH keys with your actual public keys.

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan and Apply**:
   ```bash
   terraform plan
   terraform apply
   ```

5. **Test the SFTP Server**:
   - Use an SFTP client (e.g., FileZilla or `sftp` command):
     ```bash
     sftp user1@<sftp_server_endpoint>
     ```
     Replace `<sftp_server_endpoint>` with the output from `sftp_server_endpoint`.
   - Authenticate using the private key corresponding to the public key.
   - Verify that `user1` lands in `/my-sftp-bucket/user1` and cannot access `/my-sftp-bucket/user2` or the bucket root.

---

### **Notes**
- **Bucket Name**: Ensure the bucket name is globally unique (e.g., append a random suffix like `my-sftp-bucket-1234`).
- **Security**: The script blocks public access to the S3 bucket. Ensure SSH keys are securely managed.
- **Logical Directories**: The script uses `home_directory_mappings` for chroot-like behavior. You can modify this to `home_directory_type = "LOGICAL"` for more complex mappings.
- **Additional Users**: To add more users, replicate the `aws_transfer_user` and `aws_transfer_ssh_key` resources and update the IAM policy with additional statements.
- **Cleanup**: Run `terraform destroy` to remove all resources when no longer needed.

If you need modifications (e.g., VPC endpoint, additional users, or logging to CloudWatch), let me know!