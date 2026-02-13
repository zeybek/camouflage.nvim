# Main Terraform configuration for production infrastructure
# This file contains sensitive values that should be masked

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket     = "terraform-state-prod"
    key        = "infrastructure/terraform.tfstate"
    region     = "us-east-1"
    access_key = "AKIAIOSFODNN7EXAMPLE"
    secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  }
}

# Variables with sensitive default values
variable "db_username" {
  description = "Database administrator username"
  type        = string
  default     = "admin_user"
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  default     = "SuperSecretP@ssw0rd123!"
  sensitive   = true
}

variable "api_key" {
  description = "API key for external service"
  type        = string
  default     = "sk-proj-abc123def456ghi789jkl012mno345pqr678"
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "instance_count" {
  description = "Number of instances to create"
  type        = number
  default     = 3
}

variable "replica_count" {
  type    = number
  default = 2
}

# Provider configuration with credentials
provider "aws" {
  region     = "us-west-2"
  access_key = "AKIAI44QH8DHBEXAMPLE"
  secret_key = "je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY"

  assume_role {
    role_arn     = "arn:aws:iam::123456789012:role/TerraformRole"
    session_name = "terraform-session"
    external_id  = "ext-id-secret-12345"
  }
}

provider "random" {}

# Local values with connection strings and secrets
locals {
  environment = "production"
  
  db_connection_string = "postgresql://admin_user:SuperSecretP@ssw0rd123!@db.example.com:5432/myapp"
  
  redis_url = "redis://:RedisP@ssword789@redis.example.com:6379/0"
  
  api_credentials = {
    stripe_key    = "sk_test_EXAMPLE_KEY_1234567890abcdef"
    sendgrid_key  = "SG.abcdefghijklmnop.qrstuvwxyz123456789"
    twilio_token  = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "Terraform"
    CostCenter  = "12345"
  }
}

# RDS Database instance with sensitive attributes
resource "aws_db_instance" "main" {
  identifier     = "myapp-db-production"
  engine         = "postgres"
  engine_version = "15.3"
  instance_class = "db.t3.medium"

  allocated_storage     = 100
  max_allocated_storage = 500
  storage_encrypted     = true

  db_name  = "myapp"
  username = "db_admin"
  password = "Pr0duct10nDBP@ss!"
  port     = 5432

  vpc_security_group_ids = ["sg-0abc123def456789"]
  db_subnet_group_name   = "main-subnet-group"

  backup_retention_period = 30
  skip_final_snapshot     = false
  final_snapshot_identifier = "myapp-db-final-snapshot"

  tags = local.tags
}

# IAM User with access keys
resource "aws_iam_access_key" "app_user" {
  user = aws_iam_user.app.name
}

resource "aws_iam_user" "app" {
  name = "myapp-service-account"
  path = "/system/"
}

# Secrets Manager secret
resource "aws_secretsmanager_secret_version" "api_keys" {
  secret_id = aws_secretsmanager_secret.api_keys.id
  secret_string = jsonencode({
    github_token  = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    openai_key    = "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    datadog_key   = "ddxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    pagerduty_key = "u+abcdefghijklmnopqrstuvwxyz"
  })
}

resource "aws_secretsmanager_secret" "api_keys" {
  name        = "production/api-keys"
  description = "API keys for external services"
}

# ElastiCache Redis with auth token
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "myapp-redis"
  description          = "Redis cluster for session storage"

  node_type            = "cache.t3.medium"
  num_cache_clusters   = 2
  port                 = 6379

  transit_encryption_enabled = true
  auth_token                 = "MyR3d1sAuthT0k3n!@#$%"

  snapshot_retention_limit = 7

  tags = local.tags
}

# Output sensitive values
output "db_connection_string" {
  description = "Database connection string"
  value       = local.db_connection_string
  sensitive   = true
}

output "db_password" {
  description = "Database password"
  value       = aws_db_instance.main.password
  sensitive   = true
}

output "redis_auth_token" {
  description = "Redis authentication token"
  value       = aws_elasticache_replication_group.redis.auth_token
  sensitive   = true
}

output "iam_access_key_id" {
  description = "IAM access key ID"
  value       = aws_iam_access_key.app_user.id
}

output "iam_secret_access_key" {
  description = "IAM secret access key"
  value       = aws_iam_access_key.app_user.secret
  sensitive   = true
}
