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

# Default values
DEFAULT_CLUSTER_NAME="n8n"
DEFAULT_AWS_REGION="us-east-1"
DEFAULT_AWS_PROFILE="default"
DEFAULT_NAMESPACE="n8n"

# Parse command line arguments
CLUSTER_NAME=""
AWS_REGION=""
AWS_PROFILE=""
NAMESPACE=""
CONFIRM=false

show_help() {
    echo "N8N on AWS EKS Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help                  Show this help message"
    echo "  --cluster-name=NAME     EKS cluster name to delete (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --namespace=NAME        Kubernetes namespace for n8n (default: $DEFAULT_NAMESPACE)"
    echo "  --aws-region=REGION     AWS region (default: $DEFAULT_AWS_REGION)"
    echo "  --aws-profile=PROFILE   AWS CLI profile to use (default: $DEFAULT_AWS_PROFILE)"
    echo "  --confirm               Skip confirmation prompts"
    echo ""
    echo "Example:"
    echo "  $0 --cluster-name=my-n8n --namespace=production --aws-region=us-west-2 --confirm"
    echo ""
    exit 0
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            show_help
            ;;
        --cluster-name=*)
            CLUSTER_NAME="${1#*=}"
            shift
            ;;
        --aws-region=*)
            AWS_REGION="${1#*=}"
            shift
            ;;
        --aws-profile=*)
            AWS_PROFILE="${1#*=}"
            shift
            ;;
        --namespace=*)
            NAMESPACE="${1#*=}"
            shift
            ;;
        --confirm)
            CONFIRM=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${YELLOW}N8N on AWS EKS Cleanup Script${NC}"
echo "================================"
echo ""

# Get configuration values (use defaults if not provided via CLI)
if [ -z "$CLUSTER_NAME" ]; then
    if [ "$CONFIRM" = true ]; then
        CLUSTER_NAME=$DEFAULT_CLUSTER_NAME
    else
        read -p "Cluster name to delete (default: $DEFAULT_CLUSTER_NAME): " CLUSTER_NAME
        CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    fi
else
    echo "Using cluster name from CLI: $CLUSTER_NAME"
fi

if [ -z "$AWS_REGION" ]; then
    if [ "$CONFIRM" = true ]; then
        AWS_REGION=$DEFAULT_AWS_REGION
    else
        read -p "AWS Region (default: $DEFAULT_AWS_REGION): " AWS_REGION
        AWS_REGION=${AWS_REGION:-$DEFAULT_AWS_REGION}
    fi
else
    echo "Using AWS region from CLI: $AWS_REGION"
fi

if [ -z "$AWS_PROFILE" ]; then
    if [ "$CONFIRM" = true ]; then
        AWS_PROFILE=$DEFAULT_AWS_PROFILE
    else
        read -p "AWS Profile (default: $DEFAULT_AWS_PROFILE): " AWS_PROFILE
        AWS_PROFILE=${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}
    fi
else
    echo "Using AWS profile from CLI: $AWS_PROFILE"
fi

if [ -z "$NAMESPACE" ]; then
    if [ "$CONFIRM" = true ]; then
        NAMESPACE=$DEFAULT_NAMESPACE
    else
        read -p "Kubernetes namespace (default: $DEFAULT_NAMESPACE): " NAMESPACE
        NAMESPACE=${NAMESPACE:-$DEFAULT_NAMESPACE}
    fi
else
    echo "Using namespace from CLI: $NAMESPACE"
fi

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile $AWS_PROFILE --query Account --output text)

echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "Cluster Name: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "AWS Region: $AWS_REGION"
echo "AWS Profile: $AWS_PROFILE"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""
echo -e "${RED}WARNING: This will delete all resources associated with the n8n deployment!${NC}"
echo ""

if [ "$CONFIRM" != true ]; then
    read -p "Are you sure you want to continue? (yes/no) " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cleanup cancelled."
        exit 1
    fi
fi

# Check if kubectl is configured for the cluster
echo "Checking kubectl configuration..."
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [[ ! "$CURRENT_CONTEXT" =~ "$CLUSTER_NAME" ]]; then
    echo "Updating kubectl configuration for cluster $CLUSTER_NAME..."
    aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE 2>/dev/null || echo "Cluster not accessible, continuing with cleanup..."
fi

# Step 1: Delete n8n resources
echo ""
echo -e "${GREEN}Step 1: Deleting n8n Kubernetes resources...${NC}"

# Delete resources in reverse order
kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml -n $NAMESPACE --ignore-not-found=true 2>/dev/null || \
kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-service.yaml -n $NAMESPACE --ignore-not-found=true 2>/dev/null || true

kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-deployment-configured.yaml -n $NAMESPACE --ignore-not-found=true 2>/dev/null || \
kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-deployment.yaml -n $NAMESPACE --ignore-not-found=true 2>/dev/null || true

kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-claim0-persistentvolumeclaim-configured.yaml -n $NAMESPACE --ignore-not-found=true 2>/dev/null || \
kubectl delete -f $PROJECT_ROOT/kubernetes/n8n/n8n-claim0-persistentvolumeclaim.yaml -n $NAMESPACE --ignore-not-found=true 2>/dev/null || true

# Delete postgres resources (both configured and original)
for file in postgres-service postgres-deployment postgres-claim0-persistentvolumeclaim postgres-configmap; do
    kubectl delete -f $PROJECT_ROOT/kubernetes/postgres/$file-configured.yaml -n $NAMESPACE --ignore-not-found=true 2>/dev/null || \
    kubectl delete -f $PROJECT_ROOT/kubernetes/postgres/$file.yaml -n $NAMESPACE --ignore-not-found=true 2>/dev/null || true
done

kubectl delete secret postgres-secret -n $NAMESPACE --ignore-not-found=true 2>/dev/null || true

# Step 2: Delete External DNS
echo ""
echo -e "${GREEN}Step 2: Deleting External DNS...${NC}"

kubectl delete -f $PROJECT_ROOT/kubernetes/external-dns-configured.yaml --ignore-not-found=true 2>/dev/null || \
kubectl delete -f $PROJECT_ROOT/kubernetes/external-dns.yaml --ignore-not-found=true 2>/dev/null || true

# Step 3: Delete AWS Load Balancer Controller
echo ""
echo -e "${GREEN}Step 3: Deleting AWS Load Balancer Controller...${NC}"

helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || echo "AWS Load Balancer Controller not found"

# Step 4: Delete namespace
echo ""
echo -e "${GREEN}Step 4: Deleting namespace $NAMESPACE...${NC}"

kubectl delete namespace $NAMESPACE --ignore-not-found=true 2>/dev/null || true

# Wait for namespace to be deleted (with shorter timeout)
echo "Waiting for namespace deletion to complete..."
kubectl wait --for=delete namespace/$NAMESPACE --timeout=60s 2>/dev/null || echo "Namespace deletion completed or timed out"

# Step 5: Check for any remaining Load Balancers
echo ""
echo -e "${GREEN}Step 5: Checking for remaining Load Balancers...${NC}"

# Kubernetes load balancer names use the pattern k8s-<namespace>-<service>
LB_PATTERN="k8s-${NAMESPACE}-n8n"
LB_ARNS=$(aws elbv2 describe-load-balancers \
  --profile $AWS_PROFILE \
  --region $AWS_REGION \
  --query "LoadBalancers[?contains(LoadBalancerName, '${LB_PATTERN}')].LoadBalancerArn" \
  --output text 2>/dev/null || echo "")

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
  --region=$AWS_REGION 2>/dev/null || echo "Service account not found"

eksctl delete iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=external-dns \
  --profile=$AWS_PROFILE \
  --region=$AWS_REGION 2>/dev/null || echo "Service account not found"

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

DELETE_POLICIES=false
if [ "$CONFIRM" = true ]; then
    # In confirm mode, skip policy deletion by default
    DELETE_POLICIES=false
else
    read -p "Do you want to delete these IAM policies? (yes/no) " -r
    echo ""
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        DELETE_POLICIES=true
    fi
fi

if [ "$DELETE_POLICIES" = true ]; then
    aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy --profile $AWS_PROFILE 2>/dev/null || echo "Policy not found or in use"
    aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerAdditionalPolicy --profile $AWS_PROFILE 2>/dev/null || echo "Policy not found or in use"
    aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AllowExternalDNSUpdates --profile $AWS_PROFILE 2>/dev/null || echo "Policy not found or in use"
fi

# Step 9: Clean up local files
echo ""
echo -e "${GREEN}Step 9: Cleaning up local configuration files...${NC}"

rm -f $PROJECT_ROOT/kubernetes/namespace-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/external-dns-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/n8n/n8n-deployment-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/n8n/n8n-claim0-persistentvolumeclaim-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/postgres/*-configured.yaml
rm -f $PROJECT_ROOT/kubernetes/*.yaml.bak $PROJECT_ROOT/kubernetes/n8n/*.yaml.bak $PROJECT_ROOT/kubernetes/postgres/*.yaml.bak
rm -f $SCRIPT_DIR/password-output.txt
rm -f /tmp/validation-record.json
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