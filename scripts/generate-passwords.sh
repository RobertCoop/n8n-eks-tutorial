#!/bin/bash

# Script to generate secure passwords for PostgreSQL setup

echo "Generating secure passwords for PostgreSQL..."
echo ""

# Generate random passwords
POSTGRES_PASSWORD=$(openssl rand -base64 20)
N8N_PASSWORD=$(openssl rand -base64 20)

echo "Generated passwords:"
echo "==================="
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "POSTGRES_NON_ROOT_PASSWORD: $N8N_PASSWORD"
echo ""
echo "Copy these passwords and update the postgres-secret.yaml file"
echo ""
echo "You can also create the secret directly using:"
echo ""
echo "kubectl create secret generic postgres-secret \\"
echo "  --namespace=n8n \\"
echo "  --from-literal=POSTGRES_USER=postgres \\"
echo "  --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \\"
echo "  --from-literal=POSTGRES_DB=n8n \\"
echo "  --from-literal=POSTGRES_NON_ROOT_USER=n8n \\"
echo "  --from-literal=POSTGRES_NON_ROOT_PASSWORD=$N8N_PASSWORD"