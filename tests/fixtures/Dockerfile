# Test Dockerfile for camouflage.nvim
# Contains various ENV, ARG, and LABEL patterns

FROM alpine:3.19 AS builder

# Build arguments with default values
ARG APP_VERSION=1.0.0
ARG BUILD_ENV=production
ARG DB_PASSWORD=build_time_secret_123
ARG API_KEY=test_api_key_for_build

# Environment variables - KEY=value format
ENV NODE_ENV=production
ENV APP_SECRET=my_application_secret_key
ENV DATABASE_URL=postgres://user:password123@localhost:5432/myapp
ENV REDIS_PASSWORD=redis_secret_pass

# Environment variables - quoted values
ENV JWT_SECRET="jwt_signing_secret_token_here"
ENV ENCRYPTION_KEY='aes256_encryption_key_base64'

# Multiple ENV in one line
ENV CACHE_HOST=redis.local CACHE_PORT=6379 CACHE_PASS=cache_password

# Legacy ENV format (space separated)
ENV LEGACY_SECRET super_secret_value_here

# Labels with metadata
LABEL maintainer="dev@example.com"
LABEL version="1.0.0"
LABEL description="Test application image"
LABEL api.key="label_api_key_value"
LABEL config.secret="label_secret_config"

# ARG without default (should be skipped)
ARG RUNTIME_SECRET

# Working directory and user
WORKDIR /app
USER appuser

# Copy and run commands (not masked)
COPY package.json ./
RUN npm install --production

# Multi-stage build
FROM node:20-alpine AS runtime

# Copy from builder
COPY --from=builder /app /app

# Runtime environment
ENV PORT=3000
ENV HOST=0.0.0.0
ENV SESSION_SECRET=runtime_session_secret
ENV OAUTH_CLIENT_SECRET=oauth_client_secret_value

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:3000/health || exit 1

# Entry point
ENTRYPOINT ["node", "server.js"]
CMD ["--env", "production"]
