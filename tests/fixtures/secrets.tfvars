# Terraform variables file containing sensitive values
# This file should NEVER be committed to version control

# =============================================================================
# Database Credentials
# =============================================================================

db_username = "production_admin"
db_password = "xK9#mP2$vL5@nQ8wR3"

database_credentials = {
  master_username = "postgres_master"
  master_password = "M@st3rDBP@ssw0rd!2024"
  readonly_user   = "app_readonly"
  readonly_pass   = "R34d0nlyP@ss!"
}

# MongoDB connection string
mongodb_uri = "mongodb+srv://admin:MongoDBSecretPass123@cluster0.abc123.mongodb.net/production?retryWrites=true"

# =============================================================================
# API Keys and Tokens
# =============================================================================

# Payment processing
stripe_api_key        = "sk_test_EXAMPLE_KEY_FOR_TESTING_ONLY_1234567890"
stripe_webhook_secret = "whsec_abcdefghijklmnopqrstuvwxyz123456"

# AI/ML Services
openai_api_key    = "sk-proj-aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789ABCDEFGH"
anthropic_api_key = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP"

# Source control
github_token       = "ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456"
github_app_id      = "123456"
github_private_key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA0Z3..."
gitlab_token       = "glpat-xxxxxxxxxxxxxxxxxxxx"

# =============================================================================
# Cloud Provider Credentials
# =============================================================================

# AWS
aws_access_key_id     = "AKIAIOSFODNN7EXAMPLE"
aws_secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
aws_session_token     = "AQoDYXdzEJr...<remainder of token>"

# GCP
gcp_project_id       = "my-production-project-123456"
gcp_service_account  = "terraform@my-production-project.iam.gserviceaccount.com"
gcp_credentials_json = "{\"type\":\"service_account\",\"private_key\":\"-----BEGIN PRIVATE KEY-----\\nMIIEvgIBADANBg...\"}"

# Azure
azure_subscription_id = "12345678-1234-1234-1234-123456789012"
azure_client_id       = "87654321-4321-4321-4321-210987654321"
azure_client_secret   = "azureClientSecretValue~WithSpecialChars!@#"
azure_tenant_id       = "abcdef12-3456-7890-abcd-ef1234567890"

# =============================================================================
# Messaging and Communication
# =============================================================================

slack_bot_token      = "xoxb-fake-token-for-testing-purposes-only"
slack_signing_secret = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"

twilio_account_sid = "ACfake_test_account_sid_placeholder"
twilio_auth_token  = "your_twilio_auth_token_here_32chars"

sendgrid_api_key = "SG.aBcDeFgHiJkLmNoP.qRsTuVwXyZ0123456789-ABCDEFGHIJKLMNOP"

# =============================================================================
# Monitoring and Observability
# =============================================================================

datadog_api_key = "abcdef1234567890abcdef1234567890"
datadog_app_key = "fedcba0987654321fedcba0987654321fedcba09"

newrelic_license_key = "eu01xx0123456789abcdef0123456789abcd0123"
newrelic_api_key     = "NRAK-ABCDEFGHIJKLMNOPQRSTUVWXYZ"

pagerduty_token = "u+AbCdEfGhIjKlMnOpQrStUvWxYz"
opsgenie_api_key = "12345678-abcd-efgh-ijkl-1234567890ab"

sentry_dsn = "https://abc123def456@o123456.ingest.sentry.io/1234567"

# =============================================================================
# Encryption and Security
# =============================================================================

encryption_key     = "aes-256-gcm-key-base64-encoded-value=="
jwt_secret         = "your-super-secret-jwt-signing-key-min-32-chars!"
session_secret     = "session-encryption-secret-key-here"
cookie_secret      = "cookie-signing-secret-32-characters"
oauth_client_secret = "GOCSPX-abcdefghijklmnopqrstuvwxyz"

# SSL/TLS Certificates (base64 encoded)
tls_private_key = "LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2Z0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktnd2dnU2tBZ0VBQW9JQkFRQzB..."
tls_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURYVENDQWtXZ0F3SUJBZ0lKQUxyZllPdm..."

# =============================================================================
# Numeric and Boolean Values
# =============================================================================

# Instance configuration
instance_count     = 5
replica_count      = 3
max_connections    = 1000
timeout_seconds    = 30
retention_days     = 90
port               = 5432

# Feature flags
enable_debug_mode      = false
enable_ssl             = true
enable_monitoring      = true
enable_auto_scaling    = true
skip_final_snapshot    = false
multi_az_deployment    = true

# Pricing tiers (in cents)
price_per_unit = 9999
monthly_budget = 50000

# =============================================================================
# Complex nested structures
# =============================================================================

notification_config = {
  email = {
    smtp_host     = "smtp.sendgrid.net"
    smtp_port     = 587
    smtp_username = "apikey"
    smtp_password = "SG.SendGridSMTPPassword123456"
  }
  webhook = {
    url    = "https://hooks.example.com/notify"
    secret = "webhook-hmac-secret-key"
  }
}

redis_config = {
  host      = "redis.example.com"
  port      = 6379
  password  = "RedisClusterP@ssw0rd!"
  db_number = 0
  ssl       = true
}
