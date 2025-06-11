#!/bin/bash

# N8N on AWS EKS Cleanup Script
# This script removes all resources created by the n8n deployment

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}N8N on AWS EKS Cleanup Script${NC}"
echo "================================"
echo ""

# Get configuration values
read -p "Cluster name to delete (default: n8n): " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-n8n}

read -p "AWS Region (default: us-east-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "AWS Profile (default: default): " AWS_PROFILE
AWS_PROFILE=${AWS_PROFILE:-default}

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile $AWS_PROFILE --query Account --output text)

echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "Cluster Name: $CLUSTER_NAME"
echo "AWS Region: $AWS_REGION"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""
echo -e "${RED}WARNING: This will delete all resources associated with the n8n deployment!${NC}"
echo ""

read -p "Are you sure you want to continue? (yes/no) " -r
echo ""
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 1
fi

# Step 1: Delete n8n resources
echo ""
echo -e "${GREEN}Step 1: Deleting n8n Kubernetes resources...${NC}"

# Delete resources in reverse order
kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml -n n8n --ignore-not-found=true || \
kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-service.yaml -n n8n --ignore-not-found=true

kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-deployment-configured.yaml -n n8n --ignore-not-found=true || \
kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-deployment.yaml -n n8n --ignore-not-found=true

kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-claim0-persistentvolumeclaim.yaml -n n8n --ignore-not-found=true
kubectl delete -f $PROJECT_ROOT/kubernetes/postgres/postgres-service.yaml -n n8n --ignore-not-found=true
kubectl delete -f $PROJECT_ROOT/kubernetes/postgres/postgres-deployment.yaml -n n8n --ignore-not-found=true
kubectl delete -f $PROJECT_ROOT/kubernetes/postgres/postgres-claim0-persistentvolumeclaim.yaml -n n8n --ignore-not-found=true
kubectl delete -f $PROJECT_ROOT/kubernetes/postgres/postgres-configmap.yaml -n n8n --ignore-not-found=true
kubectl delete secret postgres-secret -n n8n --ignore-not-found=true

# Step 2: Delete External DNS
echo ""
echo -e "${GREEN}Step 2: Deleting External DNS...${NC}"

kubectl delete -f $PROJECT_ROOT/kubernetes/external-dns-configured.yaml --ignore-not-found=true || \
kubectl delete -f $PROJECT_ROOT/kubernetes/external-dns.yaml --ignore-not-found=true

# Step 3: Delete AWS Load Balancer Controller
echo ""
echo -e "${GREEN}Step 3: Deleting AWS Load Balancer Controller...${NC}"

helm uninstall aws-load-balancer-controller -n kube-system || echo "AWS Load Balancer Controller not found"

# Step 4: Delete namespace
echo ""
echo -e "${GREEN}Step 4: Deleting n8n namespace...${NC}"

kubectl delete namespace n8n --ignore-not-found=true

# Wait for namespace to be deleted
echo "Waiting for namespace deletion to complete..."
kubectl wait --for=delete namespace/n8n --timeout=60s || echo "Namespace already deleted"

# Step 5: Check for any remaining Load Balancers
echo ""
echo -e "${GREEN}Step 5: Checking for remaining Load Balancers...${NC}"

LB_ARNS=$(aws elbv2 describe-load-balancers \
  --profile $AWS_PROFILE \
  --region $AWS_REGION \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-n8n-n8n')].LoadBalancerArn" \
  --output text)

if [ ! -z "$LB_ARNS" ]; then
    echo "Found Load Balancers to delete:"
    for LB_ARN in $LB_ARNS; do
        echo "Deleting Load Balancer: $LB_ARN"
        aws elbv2 delete-load-balancer --load-balancer-arn $LB_ARN --profile $AWS_PROFILE --region $AWS_REGION
    done
fi

# Step 6: Delete IAM service accounts
echo ""
echo -e "${GREEN}Step 6: Deleting IAM service accounts...${NC}"

eksctl delete iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --profile=$AWS_PROFILE \
  --region=$AWS_REGION || echo "Service account not found"

eksctl delete iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=external-dns \
  --profile=$AWS_PROFILE \
  --region=$AWS_REGION || echo "Service account not found"

# Step 7: Delete EKS cluster
echo ""
echo -e "${GREEN}Step 7: Deleting EKS cluster...${NC}"
echo "This will take approximately 15-20 minutes..."

eksctl delete cluster --name=$CLUSTER_NAME --region=$AWS_REGION --profile=$AWS_PROFILE

# Step 8: Optional - Delete IAM policies
echo ""
echo -e "${YELLOW}Optional: Delete IAM policies${NC}"
echo "The following IAM policies can be deleted if not used by other clusters:"
echo "- AWSLoadBalancerControllerIAMPolicy"
echo "- AWSLoadBalancerControllerAdditionalPolicy"
echo "- AllowExternalDNSUpdates"
echo ""
read -p "Do you want to delete these IAM policies? (yes/no) " -r
echo ""
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy --profile $AWS_PROFILE || echo "Policy not found"
    aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerAdditionalPolicy --profile $AWS_PROFILE || echo "Policy not found"
    aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AllowExternalDNSUpdates --profile $AWS_PROFILE || echo "Policy not found"
fi

# Step 9: Clean up local files
echo ""
echo -e "${GREEN}Step 9: Cleaning up local configuration files...${NC}"

rm -f $PROJECT_ROOT/kubernetes/external-dns-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/n8n/n8n-deployment-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/*.yaml.bak $PROJECT_ROOT/kubernetes/n8n/*.yaml.bak $PROJECT_ROOT/kubernetes/postgres/*.yaml.bak
rm -f $SCRIPT_DIR/password-output.txt
rm -f validation.json
rm -f validation-record.json
rm -f certificate-validation.json
rm -f n8n-dns-record.json

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
echo ""
echo "All n8n-related resources have been removed."
echo ""
echo "Notes:"
echo "- DNS records created by External DNS may take a few minutes to be removed."
echo "- ACM certificates were not deleted as they may be in use elsewhere."
echo "- IAM policies may remain temporarily attached while CloudFormation stacks complete deletion."
echo "- If policy deletion failed, they can be manually deleted once the cluster deletion is complete."