
# # Variables for AWS Transfer Family SFTP server configuration

# variable "aws_region" {
#   description = "AWS region for deployment"
#   type        = string
#   default     = "us-east-1"
# }

# variable "domain_name" {
#   description = "Custom domain for SFTP server (e.g., sftp.example.com)"
#   type        = string
#   default     = "sftp.example.com"
# }

# variable "bucket_name" {
#   description = "Name of the S3 bucket"
#   type        = string
#   default     = "partner-sftp-bucket"
# }

# variable "partners" {
#   description = "Map of partner usernames and their SSH public keys"
#   type = map(object({
#     ssh_public_key = string
#   }))
#   default = {
#     "partner1" = { ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E..." } # Replace with actual SSH key
#     "partner2" = { ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E..." } # Replace with actual SSH key
#   }
# }

# variable "vpc_cidr" {
#   description = "CIDR block for the VPC"
#   type        = string
#   default     = "10.0.0.0/16"
# }

# variable "subnet_1_cidr" {
#   description = "CIDR block for the first public subnet"
#   type        = string
#   default     = "10.0.1.0/24"
# }

# variable "subnet_2_cidr" {
#   description = "CIDR block for the second public subnet"
#   type        = string
#   default     = "10.0.2.0/24"
# }

# variable "allowed_ssh_cidr" {
#   description = "CIDR blocks allowed to access SFTP port 22"
#   type        = list(string)
#   default     = ["0.0.0.0/0"] # Restrict to partner IPs in production
# }
