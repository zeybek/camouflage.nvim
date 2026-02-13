# Terraform heredoc syntax examples
# This file demonstrates various heredoc patterns with sensitive content

# =============================================================================
# Standard Heredoc (<<EOF)
# =============================================================================

# Private key using standard heredoc
variable "ssh_private_key" {
  description = "SSH private key for instance access"
  type        = string
  default     = <<EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn/ygWyF8PbnGy0AHE8RzjHgWzZAFdmwbiH
BvdMfWjhIOmMPHkUxGnJFLMXPqVEJdRUoGeXFQuAqPOBbsC0WhfpJGkNmO6NPGRF
wNbXyBKhJFHQaZTtlGkQbC3VJxWpY5wDgXz5fGvBAUxHog4KLMfqgYmQWCQyMDLp
ExAMPLEKEYwJalrXUtnFEMI/K7MDENGbPxRfiCYEXAMPLEKEYsRQ8tR/lPsNPz1p
abc123DEFghiJKLmnoPQRstuVWXyzSecretKeyMaterial0123456789ABCDEF+/
xyz789UVWsecretKEYdataNeedsToBeProtectedFromExposure1234567890ab
EXAMPLEKEYMATERIALTHATWOULDNORMALLYBEMUCHTLONGERANDMORERANDOM==
-----END RSA PRIVATE KEY-----
EOF
}

# AWS credentials file content
locals {
  aws_credentials_content = <<EOF
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

[production]
aws_access_key_id = AKIAI44QH8DHBEXAMPLE
aws_secret_access_key = je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
region = us-west-2

[staging]
aws_access_key_id = AKIAXXXXXXXXXXXXXXXX
aws_secret_access_key = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
EOF

  # Database configuration
  database_config = <<EOF
host=db.production.example.com
port=5432
database=myapp_production
username=admin_user
password=SuperSecretDBP@ssw0rd!2024
sslmode=require
EOF
}

# =============================================================================
# Indented Heredoc (<<-EOT)
# =============================================================================

# User data script with embedded secrets
resource "aws_instance" "app_server" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.medium"

  user_data = <<-EOT
    #!/bin/bash
    set -e

    # Configure environment variables
    export DB_HOST="db.production.example.com"
    export DB_USER="application_user"
    export DB_PASSWORD="Pr0duct10nAppP@ssw0rd!"
    export DB_NAME="myapp"

    # Set API keys
    export STRIPE_API_KEY="sk_test_EXAMPLE_KEY_1234567890abcdef"
    export OPENAI_API_KEY="sk-proj-aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"
    export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    # AWS credentials for the application
    export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
    export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

    # Configure application
    cat > /etc/myapp/config.yml <<CONFIG
    database:
      host: ${DB_HOST}
      username: ${DB_USER}
      password: ${DB_PASSWORD}
      connection_string: "postgresql://application_user:Pr0duct10nAppP@ssw0rd!@db.production.example.com:5432/myapp"

    redis:
      url: "redis://:RedisAuthT0k3n!@redis.example.com:6379/0"

    secrets:
      jwt_secret: "jwt-signing-secret-key-super-secure-123!"
      encryption_key: "aes-256-key-base64-encoded-here=="
    CONFIG

    # Start application
    systemctl enable myapp
    systemctl start myapp
  EOT

  tags = {
    Name = "app-server-production"
  }
}

# Docker compose configuration
resource "local_file" "docker_compose" {
  filename = "/opt/myapp/docker-compose.yml"
  content  = <<-EOT
    version: '3.8'
    services:
      app:
        image: myapp:latest
        environment:
          - DATABASE_URL=postgresql://dbuser:D0ck3rDBP@ss!@db:5432/myapp
          - REDIS_URL=redis://:R3d1sP@ssw0rd@redis:6379/0
          - SECRET_KEY=docker-app-secret-key-very-secure
          - API_KEY=api_key_for_external_service_12345
          - JWT_SECRET=jwt-token-signing-secret-key
        ports:
          - "8080:8080"

      db:
        image: postgres:15
        environment:
          - POSTGRES_USER=dbuser
          - POSTGRES_PASSWORD=D0ck3rDBP@ss!
          - POSTGRES_DB=myapp

      redis:
        image: redis:7
        command: redis-server --requirepass R3d1sP@ssw0rd
  EOT
}

# =============================================================================
# Kubernetes secrets manifest
# =============================================================================

resource "local_file" "k8s_secrets" {
  filename = "/opt/k8s/secrets.yaml"
  content  = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: app-secrets
      namespace: production
    type: Opaque
    stringData:
      DB_PASSWORD: "K8sDBSecretP@ssw0rd!"
      API_KEY: "sk-k8s-api-key-secret-value-here"
      JWT_SECRET: "kubernetes-jwt-signing-secret"
      ENCRYPTION_KEY: "k8s-encryption-key-32-chars-min"
      AWS_ACCESS_KEY_ID: "AKIAK8SEXAMPLEKEY12"
      AWS_SECRET_ACCESS_KEY: "K8sSecretAccessKey/Example+Value/12345"
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: tls-certs
      namespace: production
    type: kubernetes.io/tls
    data:
      tls.key: |
        LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2Z0lCQURBTkJna3Foa2lH
        OXcwQkFRRUZBQVNDQktnd2dnU2tBZ0VBQW9JQkFRREVxTjdNZ0hCQkRvSEsKYWJj
        ZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXowMTIzNDU2Nzg5QUJDREVGR0hJSktMTU5P
        UFFSU1RVVldYWVoxMjM0NTY3ODkwYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo=
      tls.crt: |
        LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURYVENDQWtXZ0F3SUJBZ0lK
        QUxyZllPdm1CUUhSTUEwR0NTcUdTSWIzRFFFQkN3VUFNRVl4Q3pBSkJnTlYK
  YAML
}

# =============================================================================
# GCP Service Account Key (JSON heredoc)
# =============================================================================

locals {
  gcp_service_account_key = <<-JSON
    {
      "type": "service_account",
      "project_id": "my-production-project",
      "private_key_id": "key123456789abcdef",
      "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC0example\nprivateKEYmaterialTHATneedsTObeKEPTsecret123456789ABCDEF\nGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\n-----END PRIVATE KEY-----\n",
      "client_email": "terraform@my-production-project.iam.gserviceaccount.com",
      "client_id": "123456789012345678901",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/terraform%40my-production-project.iam.gserviceaccount.com"
    }
  JSON
}

# =============================================================================
# Environment file generation
# =============================================================================

resource "local_file" "env_file" {
  filename = "/opt/myapp/.env"
  content  = <<-ENV
    # Application Configuration
    APP_ENV=production
    APP_DEBUG=false
    APP_SECRET=app-secret-key-for-production-use

    # Database
    DB_CONNECTION=pgsql
    DB_HOST=db.production.example.com
    DB_PORT=5432
    DB_DATABASE=myapp
    DB_USERNAME=app_user
    DB_PASSWORD=Env@FileDBP@ssword123!

    # Redis
    REDIS_HOST=redis.example.com
    REDIS_PASSWORD=EnvRedisP@ssword!
    REDIS_PORT=6379

    # Mail
    MAIL_MAILER=smtp
    MAIL_HOST=smtp.sendgrid.net
    MAIL_PORT=587
    MAIL_USERNAME=apikey
    MAIL_PASSWORD=SG.EnvFileSendGridKey123456789

    # AWS
    AWS_ACCESS_KEY_ID=AKIAENVFILEEXAMPLE
    AWS_SECRET_ACCESS_KEY=EnvFileAWSSecretKey/Example+12345

    # Third-party APIs
    STRIPE_KEY=sk_test_envfile_example_key_123
    STRIPE_SECRET=sk_test_envfile_example_secret_456
    PUSHER_APP_SECRET=envfilepushersecret123

    # Security
    JWT_SECRET=env-file-jwt-secret-min-32-characters!
    ENCRYPTION_KEY=base64:EnvFileEncryptionKeyBase64Encoded==
  ENV
}

# =============================================================================
# SSL Certificate and Key
# =============================================================================

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Inline certificate for demonstration
locals {
  ssl_certificate = <<-CERT
    -----BEGIN CERTIFICATE-----
    MIIDXTCCAkWgAwIBAgIJALrfYOvmBQHRMA0GCSqGSIb3DQEBCwUAMEYxCzAJBgNV
    BAYTAlVTMRMwEQYDVQQIDApTb21lLVN0YXRlMSIwIAYDVQQKDBlJbnRlcm5ldCBX
    aWRnaXRzIFB0eSBMdGQwHhcNMjQwMTAxMDAwMDAwWhcNMjUwMTAxMDAwMDAwWjBG
    ExampleCertificateDataThatWouldBeRealInProductionEnvironment123
    ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz012345678
    -----END CERTIFICATE-----
  CERT

  ssl_private_key = <<-KEY
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDEqN7MgHBBDoHK
    ExamplePrivateKeyDataForSSL/TLSCertificateUsageInTerraform123
    SecretKeyMaterial0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef+/
    ghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabc=
    -----END PRIVATE KEY-----
  KEY
}
