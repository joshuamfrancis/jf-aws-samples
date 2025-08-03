
# Variables for AWS Transfer Family SFTP server configuration

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# variable "domain_name" {
#   description = "Custom domain for SFTP server (e.g., sftp.example.com)"
#   type        = string
#   default     = "sftp.example.com"
# }

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
  default     = "tst-jf-partner-sftp-bucket"
}

variable "partners" {
  description = "Map of partner usernames and their SSH public keys"
  type = map(object({
    ssh_public_key = string
  }))
  default = {
    "partner1" = { ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC06ZbTE7y1jRTGO/rcT69J6iomjq9MRk6CWubHjuJYLBo8lvtPbGS8myD5xSrJ5X3qHxJl2T02AxciOvRYecFvPZTH+mGtRjxWwlgpfiLW1eUTAA7jPwupGuWOYqIZHnv/+I2Vb+PvnlkbXbpDRWPOkmnIvAVOUhcOhjMo9pNv/ggKpyDHlnnQJeB0zNj7Mz04o1Gi4b9RHLkjz7psBy48Re/SOBtUkyVGwFR69lPoeMaMsJYibKXZq2VJqw26vyF5A1zCh/NdKD91b4phGZb7UTzh59V5ecbL0fPZcobPMh54Kv01pVvwYBoPuJREtx6WZt+7ec6EKV4Wn1XTTI17o1LuvFYuo2TAvBfR3ZL4PV5GoHIjdmmJBu84AP8OjVmo81AcWLQxzc2u4eLKAClQzmB5zgKGqGHaprD6vRB35H9JXctz1gdQZx+RMbEINMv+Mn4hOPKm0I5o8kBk3Ctrq9wNlVldmShOXaNkYgLvAbpnmyhqYd3M+ZhMPE/sGaQHHeU55hPwfkJlGVVSNnF9klO/LEJtKtqGUKEZNDFhZqoSKvwqRc+UMWpWZiAXv0sCV5oUNtJ7cPORthAdYmOaYnkXtnXdtfCb2izqqWlwCnqGcg2VYLf90QyhPQWpvPsocbjYb7cWc9V8zf8603E9spMK7AQAv2ybEMOkcTgeUQ== your_email@example.com" }
    "partner2" = { ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCjPV9jyNqWx2sBpOWb5S40/9P1zLE19ZIa2Tt66FFqA20YurLzev/B0FR6x3Or4Aw3DtBYw8MToNRwD2kJhKQ6QYlA/d8rfg2TOC38OqlrHXnD1X9S+sjBQVbneebK0bwLRqmPYqIoCqEixCLeXcidNBNe8CSU9rUGd31fX/hXChqfIwhgdBysQUiwlOYqudvNIWQARYHw0/mUMJF/ZW9pF8BCBuGFznOGTtbz4vrO1nQFmnEBDM23YUxB96Cd5W5b7mYZ2VAeVfHvDME8lSKHBPKAeHF5tZTHPpubTOld+7Iq+0t4/7U+KhoLikXzNJkQJPXkqgmE+o8bxdNivEF6Dv0M98641d0kgjyDysiDaoeAC1vF6TymWnHZ6M0y/WtDeXLcx/YgoiFk/7qSaW6NtR+aig+1KZ8R/4t2Sj+GpYJqUJh2iUbF94M3NCggunghK8+mtRZQZgRHhYF6HsBm1cWLphxt8zl8Clohz+KN0kV/NRDkEaAUpHIVayy081JJWsOk/7d922do8wnVylgVwuFKvzHtj9jeMDwN89YkG30FnDhTl7OrOW7qu6PwSMFMr42o1YCRBOYNiwpI5MG5Elg5C4WeJL3uTX+ww5QW8b+XpcWHkjikLyEvgUP51JkeQCcbiQzudJQZ+1KNQmnP7SmVB7Gb/yKxl9pltRlwVQ== your_email@example.com" }
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_1_cidr" {
  description = "CIDR block for the first public subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "subnet_2_cidr" {
  description = "CIDR block for the second public subnet"
  type        = string
  default     = "10.10.2.0/24"
}

variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed to access SFTP port 22"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict to partner IPs in production
}
