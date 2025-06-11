#!/bin/bash

# This script updates the IAM role used by the AWS Load Balancer Controller
# with additional permissions required for SSL certificate management.

# Exit on error
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}AWS Load Balancer Controller Permission Update Script${NC}"
echo "===================================================="
echo ""

# Get the service account role dynamically
echo "Getting AWS Load Balancer Controller service account role..."
ROLE_NAME=$(kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | awk -F'/' '{print $NF}')

if [ -z "$ROLE_NAME" ]; then
    echo -e "${RED}Error: Could not find AWS Load Balancer Controller service account role.${NC}"
    echo "Make sure the AWS Load Balancer Controller is installed with a service account."
    exit 1
fi

echo "Found role: $ROLE_NAME"

# Variables
POLICY_NAME="AWSLoadBalancerControllerAdditionalPolicy"
POLICY_FILE="aws-load-balancer-controller-additional-policy.json"

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Check if the additional policy already exists
echo "Checking if additional policy already exists..."
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

if ! aws iam get-policy --policy-arn $POLICY_ARN >/dev/null 2>&1; then
    echo "Creating additional policy for AWS Load Balancer Controller..."
    aws iam create-policy \
      --policy-name $POLICY_NAME \
      --policy-document file://$POLICY_FILE
    echo -e "${GREEN}Policy created successfully.${NC}"
else
    echo -e "${YELLOW}Policy already exists.${NC}"
fi

# Check if the policy is already attached
echo "Checking if policy is attached to role..."
if aws iam list-attached-role-policies --role-name $ROLE_NAME | grep -q $POLICY_NAME; then
    echo -e "${YELLOW}Policy is already attached to the role.${NC}"
else
    echo "Attaching policy to role $ROLE_NAME..."
    aws iam attach-role-policy \
      --role-name $ROLE_NAME \
      --policy-arn $POLICY_ARN
    echo -e "${GREEN}Policy attached successfully.${NC}"
fi

# Restart the AWS Load Balancer Controller pods to pick up the new permissions
echo ""
echo "Restarting AWS Load Balancer Controller to pick up new permissions..."
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

echo "Waiting for pods to restart..."
kubectl rollout status deployment aws-load-balancer-controller -n kube-system

echo ""
echo -e "${GREEN}Done! The AWS Load Balancer Controller now has the necessary permissions.${NC}"
echo ""
echo "If you had issues with Load Balancer provisioning, you may need to:"
echo "1. Delete the service: kubectl delete svc n8n -n n8n"
echo "2. Recreate it: kubectl apply -f n8n-service-configured.yaml"
echo ""
echo "Check the status with: kubectl get svc n8n -n n8n"