#!/bin/bash

# Initialize Vault with secrets for the ecommerce application
# This script runs after Vault is deployed and ready

set -e

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"

echo "Configuring Vault at ${VAULT_ADDR}..."

# Export for vault CLI
export VAULT_ADDR
export VAULT_TOKEN

# Wait for Vault to be ready
echo "Waiting for Vault to be ready..."
until vault status >/dev/null 2>&1; do
    sleep 2
done
echo "Vault is ready!"

# Enable KV secrets engine v2 (if not already enabled in dev mode)
vault secrets enable -path=secret -version=2 kv 2>/dev/null || echo "KV engine already enabled"

# Database credentials
echo "Writing database secrets..."
vault kv put secret/ecommerce/database \
    username="ecommerce_user" \
    password="$(openssl rand -base64 24)"

# Redis credentials
echo "Writing Redis secrets..."
vault kv put secret/ecommerce/redis \
    password="$(openssl rand -base64 24)"

# RabbitMQ credentials
echo "Writing RabbitMQ secrets..."
vault kv put secret/ecommerce/rabbitmq \
    username="rabbitmq" \
    password="$(openssl rand -base64 24)"

# Application secrets
echo "Writing application secrets..."
vault kv put secret/ecommerce/app \
    jwt_secret="$(openssl rand -base64 48)"

# Razorpay credentials (placeholder for lab)
echo "Writing Razorpay secrets..."
vault kv put secret/ecommerce/razorpay \
    key_id="rzp_test_placeholder" \
    key_secret="placeholder_secret_key" \
    webhook_secret="whsec_placeholder"

# AWS credentials (placeholder for lab)
echo "Writing AWS secrets..."
vault kv put secret/ecommerce/aws \
    access_key_id="AKIAIOSFODNN7EXAMPLE" \
    secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

echo ""
echo "All secrets written to Vault!"
echo ""
echo "You can verify secrets with:"
echo "  vault kv list secret/ecommerce"
echo "  vault kv get secret/ecommerce/database"
