#!/bin/bash

# N8N on AWS EKS Setup Script
# This script helps automate the deployment of n8n on AWS EKS

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
DOMAIN_NAME=""
NAMESPACE=""
CONFIRM=false

show_help() {
    echo "N8N on AWS EKS Setup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help                  Show this help message"
    echo "  --cluster-name=NAME     EKS cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  --namespace=NAME        Kubernetes namespace for n8n (default: $DEFAULT_NAMESPACE)"
    echo "  --aws-region=REGION     AWS region (default: $DEFAULT_AWS_REGION)"
    echo "  --aws-profile=PROFILE   AWS CLI profile to use (default: $DEFAULT_AWS_PROFILE)"
    echo "  --domain-name=DOMAIN    Domain name for n8n (required)"
    echo "  --confirm               Skip confirmation prompts"
    echo ""
    echo "Example:"
    echo "  $0 --cluster-name=my-n8n --namespace=production --aws-region=us-west-2 --domain-name=n8n.example.com --confirm"
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
        --domain-name=*)
            DOMAIN_NAME="${1#*=}"
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

echo -e "${GREEN}N8N on AWS EKS Setup Script${NC}"
echo "============================"
echo ""

# Check required tools
echo "Checking required tools..."
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v eksctl >/dev/null 2>&1 || { echo -e "${RED}eksctl is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}helm is required but not installed. Aborting.${NC}" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}jq is required but not installed. Aborting.${NC}" >&2; exit 1; }

echo -e "${GREEN}All required tools are installed.${NC}"
echo ""

# Get configuration values (use defaults if not provided via CLI)
if [ -z "$CLUSTER_NAME" ]; then
    if [ "$CONFIRM" = true ]; then
        CLUSTER_NAME=$DEFAULT_CLUSTER_NAME
    else
        read -p "Cluster name (default: $DEFAULT_CLUSTER_NAME): " CLUSTER_NAME
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

if [ -z "$DOMAIN_NAME" ]; then
    if [ "$CONFIRM" = true ]; then
        echo -e "${RED}Domain name is required. Please provide --domain-name parameter.${NC}"
        exit 1
    else
        read -p "Your domain for n8n (e.g., n8n.example.com): " DOMAIN_NAME
        if [ -z "$DOMAIN_NAME" ]; then
            echo -e "${RED}Domain name is required. Aborting.${NC}"
            exit 1
        fi
    fi
else
    echo "Using domain name from CLI: $DOMAIN_NAME"
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

# Extract AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile $AWS_PROFILE --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "Cluster Name: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "AWS Region: $AWS_REGION"
echo "AWS Profile: $AWS_PROFILE"
echo "Domain: $DOMAIN_NAME"
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

if [ "$CONFIRM" != true ]; then
    read -p "Continue with these settings? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 1
    fi
fi

# Step 1: Create EKS Cluster
echo ""
echo -e "${GREEN}Step 1: Creating EKS Cluster...${NC}"

# Check if cluster already exists
CLUSTER_EXISTS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE --query 'cluster.name' --output text 2>/dev/null || echo "")
if [ -n "$CLUSTER_EXISTS" ]; then
    echo -e "${YELLOW}Cluster '$CLUSTER_NAME' already exists. Skipping cluster creation.${NC}"
else
    echo "This will take approximately 15-20 minutes..."
    eksctl create cluster \
      --name $CLUSTER_NAME \
      --region $AWS_REGION \
      --profile $AWS_PROFILE \
      --node-type t3.medium \
      --nodes 2 \
      --nodes-min 1 \
      --nodes-max 4 \
      --managed
fi

# Verify cluster creation
echo "Verifying cluster creation..."
CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo -e "${RED}Error: Cluster creation failed or is not active. Status: $CLUSTER_STATUS${NC}"
    exit 1
fi

# Verify nodegroup creation
echo "Verifying nodegroup creation..."
NODEGROUP_COUNT=$(eksctl get nodegroup --cluster $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE -o json | jq '. | length' 2>/dev/null || echo "0")
if [ "$NODEGROUP_COUNT" -eq "0" ]; then
    echo -e "${RED}Error: No nodegroups found. Cluster creation incomplete.${NC}"
    echo "Please check CloudFormation console for any errors."
    exit 1
fi

echo -e "${GREEN}Cluster and nodegroup created successfully!${NC}"

# Update kubectl config
echo "Updating kubectl configuration..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE

# Step 2: Install EBS CSI Driver
echo ""
echo -e "${GREEN}Step 2: Installing EBS CSI Driver...${NC}"

eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --profile $AWS_PROFILE

# Get the node instance role
NODE_ROLE=$(aws eks describe-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name $(eksctl get nodegroup --cluster $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE -o json | jq -r '.[0].Name') \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query 'nodegroup.nodeRole' \
  --output text | awk -F'/' '{print $NF}')

# Attach EBS CSI policy to node role
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --profile $AWS_PROFILE

# Step 3: Associate OIDC Provider
echo ""
echo -e "${GREEN}Step 3: Associating OIDC Provider...${NC}"

eksctl utils associate-iam-oidc-provider \
  --region=$AWS_REGION \
  --cluster=$CLUSTER_NAME \
  --profile=$AWS_PROFILE \
  --approve

# Step 4: Create namespace
echo ""
echo -e "${GREEN}Step 4: Creating namespace $NAMESPACE...${NC}"

# Create namespace configuration from template
cat > $PROJECT_ROOT/kubernetes/namespace-configured.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
EOF

kubectl apply -f $PROJECT_ROOT/kubernetes/namespace-configured.yaml

# Step 5: Create IAM policies
echo ""
echo -e "${GREEN}Step 5: Creating IAM policies...${NC}"

# Create AWS Load Balancer Controller policy
if ! aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy --profile $AWS_PROFILE >/dev/null 2>&1; then
    echo "Creating AWS Load Balancer Controller IAM policy..."
    aws iam create-policy \
      --policy-name AWSLoadBalancerControllerIAMPolicy \
      --policy-document file://$PROJECT_ROOT/policies/aws-load-balancer-controller-iam-policy.json \
      --profile $AWS_PROFILE
else
    echo "AWS Load Balancer Controller IAM policy already exists"
fi

# Create External DNS policy
if ! aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AllowExternalDNSUpdates --profile $AWS_PROFILE >/dev/null 2>&1; then
    echo "Creating External DNS IAM policy..."
    aws iam create-policy \
      --policy-name AllowExternalDNSUpdates \
      --policy-document file://$PROJECT_ROOT/policies/external-dns-policy.json \
      --profile $AWS_PROFILE
else
    echo "External DNS IAM policy already exists"
fi

# Create additional AWS Load Balancer Controller policy for SSL
if ! aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerAdditionalPolicy --profile $AWS_PROFILE >/dev/null 2>&1; then
    echo "Creating additional AWS Load Balancer Controller IAM policy..."
    aws iam create-policy \
      --policy-name AWSLoadBalancerControllerAdditionalPolicy \
      --policy-document file://$PROJECT_ROOT/policies/aws-load-balancer-controller-additional-policy.json \
      --profile $AWS_PROFILE
else
    echo "Additional AWS Load Balancer Controller IAM policy already exists"
fi

# Step 6: Create IAM service accounts
echo ""
echo -e "${GREEN}Step 6: Creating IAM service accounts...${NC}"

# AWS Load Balancer Controller
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --approve

# Attach additional policy for SSL support to AWS Load Balancer Controller
echo "Attaching additional policy to AWS Load Balancer Controller..."
SERVICE_ACCOUNT_ROLE=$(kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | awk -F'/' '{print $NF}')
aws iam attach-role-policy \
  --role-name $SERVICE_ACCOUNT_ROLE \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerAdditionalPolicy \
  --profile $AWS_PROFILE

# External DNS
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=external-dns \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AllowExternalDNSUpdates \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --approve

# Step 7: Install AWS Load Balancer Controller
echo ""
echo -e "${GREEN}Step 7: Installing AWS Load Balancer Controller...${NC}"

helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get VPC ID
VPC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --namespace kube-system \
  --set region=$AWS_REGION \
  --set vpcId=$VPC_ID

# Wait for controller to be ready
echo "Waiting for AWS Load Balancer Controller to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=120s

# Step 8: Update configuration files
echo ""
echo -e "${GREEN}Step 8: Updating configuration files...${NC}"

# Create copies of configuration files
cp $PROJECT_ROOT/kubernetes/external-dns.yaml $PROJECT_ROOT/kubernetes/external-dns-configured.yaml
cp $PROJECT_ROOT/kubernetes/n8n/n8n-service.yaml $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml
cp $PROJECT_ROOT/kubernetes/n8n/n8n-deployment.yaml $PROJECT_ROOT/kubernetes/n8n/n8n-deployment-configured.yaml
cp $PROJECT_ROOT/kubernetes/n8n/n8n-claim0-persistentvolumeclaim.yaml $PROJECT_ROOT/kubernetes/n8n/n8n-claim0-persistentvolumeclaim-configured.yaml

# Extract base domain from full domain name (e.g., quellant.com from n8n-tutorial.quellant.com)
BASE_DOMAIN=$(echo "$DOMAIN_NAME" | sed 's/^[^.]*\.//')

# Update external-dns.yaml
sed -i "s/<YOUR_DOMAIN>/$BASE_DOMAIN/g" $PROJECT_ROOT/kubernetes/external-dns-configured.yaml
sed -i "s/<CLUSTER_NAME>/$CLUSTER_NAME/g" $PROJECT_ROOT/kubernetes/external-dns-configured.yaml

# Remove ServiceAccount section from external-dns-configured.yaml
sed -i '/^apiVersion: v1$/,/^---$/d' $PROJECT_ROOT/kubernetes/external-dns-configured.yaml

# Update namespace in n8n files
sed -i "s/namespace: n8n/namespace: $NAMESPACE/g" $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml
sed -i "s/namespace: n8n/namespace: $NAMESPACE/g" $PROJECT_ROOT/kubernetes/n8n/n8n-deployment-configured.yaml
sed -i "s/namespace: n8n/namespace: $NAMESPACE/g" $PROJECT_ROOT/kubernetes/n8n/n8n-claim0-persistentvolumeclaim-configured.yaml

# Deploy External DNS
echo "Deploying External DNS..."
kubectl apply -f $PROJECT_ROOT/kubernetes/external-dns-configured.yaml

# Step 9: Request ACM Certificate
echo ""
echo -e "${GREEN}Step 9: Requesting ACM Certificate...${NC}"

# Request certificate automatically
echo "Requesting certificate for $DOMAIN_NAME..."
CERTIFICATE_ARN=$(aws acm request-certificate \
  --domain-name "$DOMAIN_NAME" \
  --validation-method DNS \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query CertificateArn \
  --output text)

echo "Certificate ARN: $CERTIFICATE_ARN"

# Wait for validation records to be available
echo "Waiting for validation records to be generated..."
MAX_ATTEMPTS=30
ATTEMPT=0
VALIDATION_RECORD=""

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    VALIDATION_RECORD=$(aws acm describe-certificate \
      --certificate-arn $CERTIFICATE_ARN \
      --region $AWS_REGION \
      --profile $AWS_PROFILE \
      --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
      --output json 2>/dev/null || echo "")
    
    if [ ! -z "$VALIDATION_RECORD" ] && [ "$VALIDATION_RECORD" != "null" ]; then
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo -n "."
    sleep 2
done

echo ""

if [ -z "$VALIDATION_RECORD" ] || [ "$VALIDATION_RECORD" = "null" ]; then
    echo -e "${RED}Error: Unable to retrieve validation records after $MAX_ATTEMPTS attempts.${NC}"
    echo "Please check the certificate status in the AWS Console."
    exit 1
fi

echo "Validation record retrieved successfully!"
echo ""
echo -e "${YELLOW}DNS Validation Record:${NC}"
echo $VALIDATION_RECORD | jq .

# Extract the DNS record details for easier reading
RECORD_NAME=$(echo $VALIDATION_RECORD | jq -r '.Name')
RECORD_VALUE=$(echo $VALIDATION_RECORD | jq -r '.Value')
RECORD_TYPE=$(echo $VALIDATION_RECORD | jq -r '.Type')

echo ""
echo -e "${YELLOW}Please add the following DNS record to your Route53 hosted zone:${NC}"
echo "Type: $RECORD_TYPE"
echo "Name: $RECORD_NAME"
echo "Value: $RECORD_VALUE"
echo ""

# Check if we should try to add the record automatically
AUTO_ADD_DNS=false
if [ "$CONFIRM" = true ]; then
    # In confirm mode, try to add DNS record automatically
    AUTO_ADD_DNS=true
else
    read -p "Would you like to try adding this record automatically to Route53? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        AUTO_ADD_DNS=true
    fi
fi

if [ "$AUTO_ADD_DNS" = true ]; then
    # Try to find the hosted zone
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
      --profile $AWS_PROFILE \
      --query "HostedZones[?contains(Name, '${BASE_DOMAIN}.')].Id" \
      --output text | awk -F'/' '{print $3}' | head -n1)
    
    if [ ! -z "$HOSTED_ZONE_ID" ]; then
        echo "Found hosted zone: $HOSTED_ZONE_ID"
        echo "Adding validation record..."
        
        cat > /tmp/validation-record.json <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$RECORD_NAME",
      "Type": "$RECORD_TYPE",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$RECORD_VALUE"}]
    }
  }]
}
EOF
        
        aws route53 change-resource-record-sets \
          --hosted-zone-id $HOSTED_ZONE_ID \
          --change-batch file:///tmp/validation-record.json \
          --profile $AWS_PROFILE
        
        rm -f /tmp/validation-record.json
        echo -e "${GREEN}Validation record added successfully!${NC}"
    else
        echo -e "${YELLOW}Could not find hosted zone for $BASE_DOMAIN. Please add the record manually.${NC}"
    fi
fi

echo ""
echo "Waiting for certificate validation (this may take a few minutes)..."

# Wait for certificate to be validated
aws acm wait certificate-validated \
  --certificate-arn $CERTIFICATE_ARN \
  --region $AWS_REGION \
  --profile $AWS_PROFILE

echo -e "${GREEN}Certificate is now validated!${NC}"

# Update n8n-service.yaml
sed -i "s|arn:aws:acm:<REGION>:<AWS_ACCOUNT_ID>:certificate/<CERTIFICATE_ID>|$CERTIFICATE_ARN|g" $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml
sed -i "s/<YOUR_DOMAIN>/$DOMAIN_NAME/g" $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml

# Update n8n-deployment.yaml
sed -i "s|<YOUR_DOMAIN>|$DOMAIN_NAME|g" $PROJECT_ROOT/kubernetes/n8n/n8n-deployment-configured.yaml

# Step 10: Generate PostgreSQL passwords
echo ""
echo -e "${GREEN}Step 10: Generating PostgreSQL passwords...${NC}"
$SCRIPT_DIR/generate-passwords.sh > $SCRIPT_DIR/password-output.txt
echo "Passwords saved to $SCRIPT_DIR/password-output.txt"

# Create PostgreSQL secret
echo "Creating PostgreSQL secret..."
POSTGRES_PASSWORD=$(openssl rand -base64 20)
N8N_PASSWORD=$(openssl rand -base64 20)

kubectl create secret generic postgres-secret \
  --namespace=$NAMESPACE \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  --from-literal=POSTGRES_DB=n8n \
  --from-literal=POSTGRES_NON_ROOT_USER=n8n \
  --from-literal=POSTGRES_NON_ROOT_PASSWORD=$N8N_PASSWORD

# Step 11: Deploy n8n
echo ""
echo -e "${GREEN}Step 11: Deploying n8n...${NC}"

# Update all YAML files with the correct namespace
echo "Updating Kubernetes manifests with namespace $NAMESPACE..."

# Create postgres configs with namespace
for file in $PROJECT_ROOT/kubernetes/postgres/*.yaml; do
    filename=$(basename "$file")
    sed "s/namespace: n8n/namespace: $NAMESPACE/g" "$file" > "$PROJECT_ROOT/kubernetes/postgres/${filename%.yaml}-configured.yaml"
done

# Apply all configurations
kubectl apply -f $PROJECT_ROOT/kubernetes/postgres/postgres-configmap-configured.yaml
kubectl apply -f $PROJECT_ROOT/kubernetes/postgres/postgres-claim0-persistentvolumeclaim-configured.yaml
kubectl apply -f $PROJECT_ROOT/kubernetes/postgres/postgres-deployment-configured.yaml
kubectl apply -f $PROJECT_ROOT/kubernetes/postgres/postgres-service-configured.yaml
kubectl apply -f $PROJECT_ROOT/kubernetes/n8n/n8n-claim0-persistentvolumeclaim-configured.yaml
kubectl apply -f $PROJECT_ROOT/kubernetes/n8n/n8n-deployment-configured.yaml
kubectl apply -f $PROJECT_ROOT/kubernetes/n8n/n8n-service-configured.yaml

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l service=postgres-n8n -n $NAMESPACE --timeout=120s || {
    echo "Postgres pod not ready after 120s. Checking pod status..."
    kubectl get pods -n $NAMESPACE -l service=postgres-n8n
    kubectl describe pod -n $NAMESPACE -l service=postgres-n8n | tail -20
}
kubectl wait --for=condition=ready pod -l service=n8n -n $NAMESPACE --timeout=120s || {
    echo "n8n pod not ready after 120s. Checking pod status..."
    kubectl get pods -n $NAMESPACE -l service=n8n
    kubectl describe pod -n $NAMESPACE -l service=n8n | tail -20
}

echo ""
echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Wait for the Load Balancer to be provisioned (2-3 minutes)"
echo "   Check status: kubectl get svc n8n -n $NAMESPACE"
echo ""
echo "2. Once the Load Balancer is ready, External DNS will create the DNS record"
echo "   This may take 5-10 minutes"
echo ""
echo "3. Access your n8n instance at: https://$DOMAIN_NAME"
echo ""
echo "Useful commands:"
echo "- Check pod status: kubectl get pods -n $NAMESPACE"
echo "- View logs: kubectl logs -n $NAMESPACE deployment/n8n"
echo "- Get load balancer URL: kubectl get svc n8n -n $NAMESPACE"