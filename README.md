# n8n on AWS EKS - Complete Deployment Guide

This repository provides a comprehensive guide and automation scripts for deploying [n8n](https://n8n.io) (a workflow automation tool) on Amazon Elastic Kubernetes Service (EKS) with SSL/TLS support, automatic DNS management, and PostgreSQL database.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup Guide](#detailed-setup-guide)
- [Configuration](#configuration)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Troubleshooting](#troubleshooting)
- [Cost Considerations](#cost-considerations)
- [Security Best Practices](#security-best-practices)
- [Contributing](#contributing)

## Overview

This deployment guide sets up a production-ready n8n instance on AWS EKS with:

- **High Availability**: Kubernetes deployment with auto-scaling capabilities
- **SSL/TLS**: Automatic SSL certificate management via AWS Certificate Manager
- **Database**: PostgreSQL for persistent data storage
- **DNS Management**: Automatic DNS record creation with External DNS
- **Load Balancing**: AWS Network Load Balancer (NLB) with SSL termination
- **Storage**: Persistent volumes for data retention

## Architecture

```
┌─────────────────┐     ┌──────────────────┐
│   Route 53      │────▶│  Load Balancer   │
│   (DNS)         │     │  (NLB + SSL)     │
└─────────────────┘     └──────────────────┘
                                │
                                ▼
                        ┌───────────────┐
                        │   EKS Cluster │
                        ├───────────────┤
                        │  ┌─────────┐  │
                        │  │   n8n   │  │
                        │  └─────────┘  │
                        │       │       │
                        │  ┌─────────┐  │
                        │  │PostgreSQL│ │
                        │  └─────────┘  │
                        └───────────────┘
```

## Repository Structure

```
n8n-eks-tutorial/
├── README.md                       # This guide
├── LICENSE                         # Public domain dedication
├── docs/                          # Additional documentation
│   ├── TROUBLESHOOTING.md         # Common issues and solutions
│   └── kubernetes/                # Kubernetes-specific documentation
├── scripts/                       # Automation scripts
│   ├── setup-n8n-eks.sh          # Main setup script
│   ├── cleanup-n8n-eks.sh        # Cleanup script
│   └── generate-passwords.sh      # Password generation helper
├── policies/                      # IAM policy definitions
│   ├── aws-load-balancer-controller-iam-policy.json
│   ├── aws-load-balancer-controller-additional-policy.json
│   └── external-dns-policy.json
└── kubernetes/                    # Kubernetes manifests
    ├── namespace.yaml             # n8n namespace definition
    ├── external-dns.yaml          # External DNS configuration
    ├── n8n/                       # n8n application manifests
    │   ├── n8n-deployment.yaml
    │   ├── n8n-service.yaml
    │   └── n8n-claim0-persistentvolumeclaim.yaml
    └── postgres/                  # PostgreSQL database manifests
        ├── postgres-deployment.yaml
        ├── postgres-service.yaml
        ├── postgres-configmap.yaml
        ├── postgres-secret.yaml
        └── postgres-claim0-persistentvolumeclaim.yaml
```

## Prerequisites

### Required Tools

Before starting, ensure you have the following tools installed:

1. **AWS CLI** (v2.x or later)
   ```bash
   # Install AWS CLI
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   
   # Configure AWS credentials
   aws configure
   ```

2. **eksctl** (v0.150.0 or later)
   ```bash
   # Install eksctl
   curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
   sudo mv /tmp/eksctl /usr/local/bin
   ```

3. **kubectl** (v1.27 or later)
   ```bash
   # Install kubectl
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```

4. **helm** (v3.x or later)
   ```bash
   # Install helm
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

5. **jq** (for JSON parsing)
   ```bash
   # Install jq (if not already installed)
   sudo apt-get update && sudo apt-get install -y jq
   ```

### Prerequisites Verification

Run this script to verify all tools are installed:

```bash
# Verify all tools are installed
echo "Checking prerequisites..."
command -v aws >/dev/null 2>&1 && echo "✓ AWS CLI installed" || echo "✗ AWS CLI missing"
command -v eksctl >/dev/null 2>&1 && echo "✓ eksctl installed" || echo "✗ eksctl missing"
command -v kubectl >/dev/null 2>&1 && echo "✓ kubectl installed" || echo "✗ kubectl missing"
command -v helm >/dev/null 2>&1 && echo "✓ helm installed" || echo "✗ helm missing"
command -v jq >/dev/null 2>&1 && echo "✓ jq installed" || echo "✗ jq missing"
```

### AWS Requirements

- An AWS account with appropriate permissions
- A Route53 hosted zone for your domain
- IAM permissions to create:
  - EKS clusters
  - EC2 instances
  - Load Balancers
  - IAM roles and policies
  - ACM certificates

### AWS Profile Support

> **Note**: If you're using AWS profiles, append `--profile <profile-name>` to all AWS CLI and eksctl commands throughout this tutorial.

### Set Persistent Environment Variables

Export these variables for use throughout the tutorial:

```bash
# Set environment variables (adjust as needed)
export CLUSTER_NAME="n8n"
export AWS_REGION="us-east-1"
export YOUR_DOMAIN="your-domain.com"
export AWS_PROFILE="default"  # Change if using a different profile
```

## Quick Start

For a fully automated deployment, use the provided setup script:

```bash
# Clone the repository
git clone https://github.com/your-username/n8n-eks-tutorial.git
cd n8n-eks-tutorial

# Make scripts executable
chmod +x scripts/setup-n8n-eks.sh scripts/generate-passwords.sh

# Run the setup script
./scripts/setup-n8n-eks.sh
```

The script will prompt you for:
- Cluster name (default: n8n)
- AWS Region (default: us-east-1)
- Your domain name (e.g., n8n.example.com)

## Detailed Setup Guide

If you prefer manual setup or need to customize the deployment, follow these steps:

> **Note**: When copying multi-line commands, ensure your shell properly handles line continuations. If you encounter errors, try running the command on a single line.

### Step 1: Create the EKS Cluster

```bash
# Set your configuration
export CLUSTER_NAME="n8n"
export AWS_REGION="us-east-1"

# Create the cluster
eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed
```

This creates a managed node group with auto-scaling capabilities. The process takes approximately 15-20 minutes.

> **Note**: You may see warnings about OIDC during cluster creation. This is normal and will be configured in Step 3.

> ✓ **Success Checkpoint - Step 1:**
> - Expected output: "EKS cluster 'n8n' in 'us-east-1' region is ready"
> - Verification command: `kubectl get nodes`
> - Common issues: AWS credentials errors (ensure AWS_PROFILE is set correctly)

### Step 2: Install the Amazon EBS CSI Driver

The EBS CSI driver is required for persistent volume support:

```bash
# Create the add-on
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION

# Get the node instance role
NODE_ROLE=$(aws eks describe-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name $(eksctl get nodegroup --cluster $CLUSTER_NAME -o json | jq -r '.[0].Name') \
  --region $AWS_REGION \
  --query 'nodegroup.nodeRole' \
  --output text | awk -F'/' '{print $NF}')

# Attach the required policy
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

> ✓ **Success Checkpoint - Step 2:**
> - Expected output: Policy attached successfully (no output means success)
> - Verification command: `kubectl get addon -n kube-system | grep ebs`
> - Common issues: Node role extraction may fail if nodegroup name differs

### Step 3: Set up OIDC Provider

```bash
eksctl utils associate-iam-oidc-provider \
  --region=$AWS_REGION \
  --cluster=$CLUSTER_NAME \
  --approve
```

> ✓ **Success Checkpoint - Step 3:**
> - Expected output: "created IAM Open ID Connect provider for cluster"
> - Verification command: `aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?contains(Arn, `$CLUSTER_NAME`)].Arn'`
> - Common issues: OIDC provider may already exist (can be safely ignored)

### Step 4: Install AWS Load Balancer Controller

The AWS Load Balancer Controller manages Network Load Balancers for the cluster:

```bash
# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create IAM policy (skip if already exists)
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://policies/aws-load-balancer-controller-iam-policy.json || true

# Create additional IAM policy for SSL support (skip if already exists)
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerAdditionalPolicy \
  --policy-document file://policies/aws-load-balancer-controller-additional-policy.json || true

# Create IAM service account
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region $AWS_REGION \
  --approve

# Attach additional policy for SSL support
SERVICE_ACCOUNT_ROLE=$(kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | awk -F'/' '{print $NF}')
aws iam attach-role-policy \
  --role-name $SERVICE_ACCOUNT_ROLE \
  --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerAdditionalPolicy

# Install using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

VPC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
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
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=120s
```

> ✓ **Success Checkpoint - Step 4:**
> - Expected output: "pod/aws-load-balancer-controller-[...] condition met"
> - Verification command: `helm list -n kube-system | grep aws-load-balancer-controller`
> - Common issues: Missing permissions (ensure additional policy is attached)

### Step 5: Set up External DNS

External DNS automatically creates Route53 records for your services:

```bash
# Create IAM policy (skip if already exists)
aws iam create-policy \
  --policy-name AllowExternalDNSUpdates \
  --policy-document file://policies/external-dns-policy.json || true

# Create IAM service account
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=external-dns \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AllowExternalDNSUpdates \
  --region $AWS_REGION \
  --approve

# Update the external-dns.yaml with your domain and cluster name
# Make a copy first to preserve the original
cp kubernetes/external-dns.yaml kubernetes/external-dns-configured.yaml
sed -i "s/<YOUR_DOMAIN>/your-domain.com/g" kubernetes/external-dns-configured.yaml
sed -i "s/<CLUSTER_NAME>/$CLUSTER_NAME/g" kubernetes/external-dns-configured.yaml

# Remove the ServiceAccount section (already created by eksctl)
sed -i '/^apiVersion: v1$/,/^---$/d' kubernetes/external-dns-configured.yaml

# Deploy External DNS
kubectl apply -f kubernetes/external-dns-configured.yaml

# Verify External DNS is running
kubectl get deployment -n kube-system external-dns
```

> ✓ **Success Checkpoint - Step 5:**
> - Expected output: "deployment.apps/external-dns created"
> - Verification command: `kubectl logs -n kube-system deployment/external-dns --tail=5`
> - Common issues: ServiceAccount section must be removed from YAML (already created by eksctl)

### Step 6: Request SSL Certificate

You can request a certificate via AWS CLI:

```bash
# Request certificate
CERTIFICATE_ARN=$(aws acm request-certificate \
  --domain-name "n8n.$YOUR_DOMAIN" \
  --validation-method DNS \
  --region $AWS_REGION \
  --query CertificateArn \
  --output text)

echo "Certificate ARN: $CERTIFICATE_ARN"

# Get validation records
aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN \
  --region $AWS_REGION \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'

# The validation record may be automatically added if your domain is in Route53
# If not, you'll need to manually create it:
# 1. Get the validation record details from the describe-certificate output above
# 2. Create a JSON file with the record details:
cat > /tmp/validation-record.json << EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "<VALIDATION_NAME>",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "<VALIDATION_VALUE>"}]
    }
  }]
}
EOF
# 3. Use aws route53 change-resource-record-sets to add the record:
# aws route53 change-resource-record-sets --hosted-zone-id <ZONE_ID> --change-batch file:///tmp/validation-record.json

# Wait for certificate to be issued (this may take a few minutes)
aws acm wait certificate-validated \
  --certificate-arn $CERTIFICATE_ARN \
  --region $AWS_REGION

echo "Certificate is now validated and ready to use!"
```

> ✓ **Success Checkpoint - Step 6:**
> - Expected output: Certificate status changes from "PENDING_VALIDATION" to "ISSUED"
> - Verification command: `aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --query Certificate.Status`
> - Common issues: Certificate stuck in PENDING_VALIDATION (manually add validation record)

Or use the AWS Console:
1. Go to AWS Certificate Manager in the AWS Console
2. Request a public certificate for your domain
3. Choose DNS validation
4. Add the validation records to your Route53 hosted zone
5. Wait for the certificate to be issued

### Step 7: Configure n8n

Update the configuration files with your values:

```bash
# Make copies to preserve originals
cp kubernetes/n8n/n8n-service.yaml kubernetes/n8n/n8n-service-configured.yaml
cp kubernetes/n8n/n8n-deployment.yaml kubernetes/n8n/n8n-deployment-configured.yaml

# Update n8n-service.yaml with your certificate ARN and domain
sed -i "s|arn:aws:acm:<REGION>:<AWS_ACCOUNT_ID>:certificate/<CERTIFICATE_ID>|$CERTIFICATE_ARN|g" kubernetes/n8n/n8n-service-configured.yaml
sed -i "s/<YOUR_DOMAIN>/n8n.$YOUR_DOMAIN/g" kubernetes/n8n/n8n-service-configured.yaml

# Update n8n-deployment.yaml with your domain
sed -i "s|<YOUR_DOMAIN>|n8n.$YOUR_DOMAIN|g" kubernetes/n8n/n8n-deployment-configured.yaml
```

> ✓ **Success Checkpoint - Step 7:**
> - Expected output: Files created and updated successfully
> - Verification command: `grep -n "n8n.$YOUR_DOMAIN" kubernetes/n8n/n8n-*-configured.yaml`
> - Common issues: Ensure $CERTIFICATE_ARN and $YOUR_DOMAIN variables are set

### Step 8: Create Namespace and PostgreSQL Secret

First create the namespace, then generate secure passwords:

```bash
# Create namespace
kubectl create namespace n8n

# Generate passwords and create secret using the helper script
./scripts/generate-passwords.sh

# The script will output the kubectl command to create the secret
# Copy and run it, or create the secret directly:
kubectl create secret generic postgres-secret \
  --namespace=n8n \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=$(openssl rand -base64 20) \
  --from-literal=POSTGRES_DB=n8n \
  --from-literal=POSTGRES_NON_ROOT_USER=n8n \
  --from-literal=POSTGRES_NON_ROOT_PASSWORD=$(openssl rand -base64 20)
```

> ✓ **Success Checkpoint - Step 8:**
> - Expected output: "namespace/n8n created" and "secret/postgres-secret created"
> - Verification command: `kubectl get secrets -n n8n`
> - Common issues: Multi-line command issues (run on single line if errors occur)

### Step 9: Deploy n8n

```bash
# Apply all configurations in order
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/postgres/postgres-configmap.yaml
kubectl apply -f kubernetes/postgres/postgres-claim0-persistentvolumeclaim.yaml
kubectl apply -f kubernetes/postgres/postgres-deployment.yaml
kubectl apply -f kubernetes/postgres/postgres-service.yaml
kubectl apply -f kubernetes/n8n/n8n-claim0-persistentvolumeclaim.yaml
kubectl apply -f kubernetes/n8n/n8n-deployment-configured.yaml
kubectl apply -f kubernetes/n8n/n8n-service-configured.yaml

# Wait for pods to be ready
# Note: Check actual pod labels with kubectl get pods -n n8n --show-labels
kubectl wait --for=condition=ready pod -l service=postgres-n8n -n n8n --timeout=120s
kubectl wait --for=condition=ready pod -l service=n8n -n n8n --timeout=120s

# Check deployment status
kubectl get all -n n8n

# Wait for Load Balancer to be provisioned (this may take 2-3 minutes)
echo "Waiting for Load Balancer to be provisioned..."
kubectl get svc n8n -n n8n -w
```

> ✓ **Success Checkpoint - Step 9:**
> - Expected output: Load Balancer shows EXTERNAL-IP as a hostname (elb.amazonaws.com)
> - Verification command: `kubectl get pods -n n8n` (all should be Running)
> - Common issues: Pod labels may differ (check with --show-labels)

### Step 10: Verify Deployment

Once the Load Balancer shows an external IP/hostname:

```bash
# Get the Load Balancer URL
LOAD_BALANCER_URL=$(kubectl get svc n8n -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Load Balancer URL: $LOAD_BALANCER_URL"

# Test HTTPS connection (may take a minute for the LB to be fully ready)
curl -I https://$LOAD_BALANCER_URL

# Check if DNS record was created
echo "Checking DNS record (may take 2-5 minutes to appear)..."
nslookup n8n.$YOUR_DOMAIN

# Once DNS propagates, access n8n at:
echo "n8n URL: https://n8n.$YOUR_DOMAIN"
```

### DNS Propagation Timeline

- **Route53 record creation**: 1-2 minutes (check External DNS logs)
- **Local DNS resolution**: 5-15 minutes
- **Global DNS propagation**: up to 48 hours (though usually much faster)

To verify DNS records are created in Route53:
```bash
# Get your hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones-by-name --query "HostedZones[?Name=='$YOUR_DOMAIN.'].Id" --output text | cut -d'/' -f3)

# Check if records exist
aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID --query "ResourceRecordSets[?Name=='n8n.$YOUR_DOMAIN.']"
```

> ✓ **Success Checkpoint - Step 10:**
> - Expected output: DNS records visible in Route53, Load Balancer responding to HTTPS
> - Verification command: `kubectl logs -n kube-system deployment/external-dns --tail=10`
> - Common issues: DNS propagation delays (be patient, check Route53 directly)

## Configuration

### Environment Variables

Key n8n environment variables in the deployment:

| Variable | Description | Default |
|----------|-------------|---------|
| `N8N_PROTOCOL` | Protocol for n8n | `http` |
| `N8N_PORT` | Port n8n listens on | `5678` |
| `N8N_EDITOR_BASE_URL` | Public URL for n8n | Set to your domain |
| `N8N_RUNNERS_ENABLED` | Enable task runners | `true` |

### Resource Limits

Default resource allocations:

```yaml
resources:
  requests:
    memory: "250Mi"
  limits:
    memory: "500Mi"
```

Adjust these based on your workload requirements.

## Monitoring and Maintenance

### Check Deployment Status

```bash
# Check all pods
kubectl get pods -n n8n

# Check services
kubectl get svc -n n8n

# View n8n logs
kubectl logs -n n8n deployment/n8n

# View PostgreSQL logs
kubectl logs -n n8n deployment/postgres
```

### Scaling

```bash
# Scale n8n deployment
kubectl scale deployment n8n -n n8n --replicas=3

# Enable horizontal pod autoscaling
kubectl autoscale deployment n8n -n n8n --min=1 --max=5 --cpu-percent=80
```

### Backup PostgreSQL

```bash
# Create a backup
kubectl exec -n n8n deployment/postgres -- pg_dump -U postgres n8n > n8n-backup.sql

# Restore from backup
kubectl exec -i -n n8n deployment/postgres -- psql -U postgres n8n < n8n-backup.sql
```

## Troubleshooting

### Common Issues

1. **Load Balancer stuck in pending state**
   - Check AWS Load Balancer Controller logs: `kubectl logs -n kube-system deployment/aws-load-balancer-controller`
   - Check service events: `kubectl describe svc n8n -n n8n`
   - **Missing Permissions Error**: If you see errors about `elasticloadbalancing:DescribeListenerAttributes`:
     ```bash
     # The additional policy should have been applied in Step 4, but if not:
     SERVICE_ACCOUNT_ROLE=$(kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | awk -F'/' '{print $NF}')
     aws iam attach-role-policy \
       --role-name $SERVICE_ACCOUNT_ROLE \
       --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerAdditionalPolicy
     
     # Restart the controller
     kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
     ```

2. **DNS record not created**
   - Check External DNS logs: `kubectl logs -n kube-system deployment/external-dns`
   - Verify the domain filter matches your Route53 hosted zone
   - Check if DNS record exists: `aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> | grep n8n`
   - External DNS may take 2-5 minutes to create records after Load Balancer is ready

3. **n8n pod not starting**
   - Check pod events: `kubectl describe pod -n n8n <pod-name>`
   - Verify PostgreSQL is running and accessible
   - Check if PersistentVolumeClaim is bound: `kubectl get pvc -n n8n`

4. **SSL certificate issues**
   - Ensure the ACM certificate is in "Issued" status
   - Verify the certificate ARN in n8n-service-configured.yaml is correct
   - Certificate must be in the same region as your EKS cluster

5. **Environment variables not set**
   - Error: "--cluster must be set" or similar
   - Solution: Ensure all environment variables are exported in your current shell
   - Run `echo $CLUSTER_NAME $AWS_REGION $YOUR_DOMAIN` to verify

6. **Certificate stuck in PENDING_VALIDATION**
   - Check if validation record exists in Route53
   - Manually create the validation record if needed (see Step 6)
   - Allow 5-10 minutes for validation after record creation

7. **Multi-line command errors**
   - Error: "command not found: --some-flag"
   - Solution: Put the entire command on one line or use proper line continuations
   - Avoid copying line numbers or extra whitespace

### Debug Commands

```bash
# Get detailed pod information
kubectl describe pod -n n8n -l service=n8n

# Check persistent volume claims
kubectl get pvc -n n8n

# View all events in the namespace
kubectl get events -n n8n --sort-by=.metadata.creationTimestamp
```

## Cost Considerations

Estimated monthly costs (varies by region and usage):

- **EKS Control Plane**: $72/month
- **EC2 Instances** (2 x t3.medium): ~$60/month
- **Load Balancer**: ~$20/month + data transfer
- **EBS Volumes**: ~$10/month for 20GB
- **Route53**: $0.50/hosted zone + queries

**Total**: Approximately $160-200/month

### Cost Optimization Tips

1. Use spot instances for worker nodes
2. Implement cluster autoscaling
3. Schedule non-production clusters to shut down outside business hours
4. Use GP3 volumes instead of GP2 for better price/performance

## Security Best Practices

1. **Secrets Management**
   - Use AWS Secrets Manager or Parameter Store for sensitive data
   - Rotate PostgreSQL passwords regularly
   - Never commit secrets to version control

2. **Network Security**
   - Implement network policies to restrict pod-to-pod communication
   - Use security groups to limit ingress/egress traffic
   - Enable VPC flow logs for auditing

3. **Access Control**
   - Use RBAC to limit kubectl access
   - Enable audit logging on the EKS cluster
   - Implement pod security policies

4. **Updates**
   - Keep n8n updated to the latest version
   - Regularly update EKS and node AMIs
   - Monitor security advisories

## Cleanup and Teardown

This section provides comprehensive instructions for removing all resources created by this tutorial. **Important**: Failing to properly clean up resources will result in ongoing AWS charges.

### Pre-Cleanup Checklist

Before starting cleanup, ensure you have:
- [ ] Backed up any important data from n8n
- [ ] Exported any workflows you want to keep
- [ ] Noted any custom configurations for future reference
- [ ] Set the same environment variables used during setup:
  ```bash
  export CLUSTER_NAME="n8n"
  export AWS_REGION="us-east-1"
  export YOUR_DOMAIN="your-domain.com"
  export AWS_PROFILE="default"  # Or your profile name
  ```

### Automated Cleanup (Recommended)

Use the provided cleanup script for the easiest teardown:

```bash
# Run the cleanup script
./scripts/cleanup-n8n-eks.sh
```

The script will prompt you for:
- Cluster name (default: n8n)
- AWS Region (default: us-east-1)
- AWS Profile (default: default)

**Note**: This script requires interactive confirmation. If you need to run it non-interactively, you'll need to modify the script or use the manual steps below.

### Cleanup Time Estimates

- Kubernetes resources deletion: 1-2 minutes
- EKS cluster deletion: 10-15 minutes
- Route53 propagation: Changes are immediate, but DNS caching may take 5-60 minutes
- Total cleanup time: 15-20 minutes

### Manual Cleanup Steps

If the automated script fails or you prefer manual cleanup, follow these steps in order:

#### 1. Delete Kubernetes Resources

```bash
# Delete n8n namespace (this removes all resources within it)
kubectl delete namespace n8n

# Delete EBS CSI driver addon
kubectl delete addon aws-ebs-csi-driver -n kube-system || echo "Addon may be managed by eksctl"

# Delete External DNS
kubectl delete deployment external-dns -n kube-system
kubectl delete clusterrole external-dns
kubectl delete clusterrolebinding external-dns-viewer

# Delete AWS Load Balancer Controller
helm uninstall aws-load-balancer-controller -n kube-system

# Wait for Load Balancers to be deleted (important to avoid orphaned resources)
echo "Waiting for Load Balancers to be deleted..."
sleep 60
```

#### 2. Delete the EKS Cluster

```bash
# Delete the cluster (this also removes node groups)
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE

# This process takes 10-15 minutes
```

#### 3. Clean Up IAM Resources

```bash
# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE)

# Delete IAM service account roles (created by eksctl)
# List them first
aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-$CLUSTER_NAME')].[RoleName]" --output table --profile $AWS_PROFILE

# Delete each role (eksctl should handle this, but verify)
# Example: aws iam delete-role --role-name eksctl-n8n-addon-iamserviceaccount-... --profile $AWS_PROFILE

# Delete IAM policies (only if not used by other clusters)
aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy --profile $AWS_PROFILE || echo "Policy may be in use or already deleted"
aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerAdditionalPolicy --profile $AWS_PROFILE || echo "Policy may be in use or already deleted"
aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AllowExternalDNSUpdates --profile $AWS_PROFILE || echo "Policy may be in use or already deleted"
```

#### 4. Clean Up Route53 Records

```bash
# Get hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones-by-name --query "HostedZones[?Name=='$YOUR_DOMAIN.'].Id" --output text --profile $AWS_PROFILE | cut -d'/' -f3)

# List ALL records created for n8n (including validation records)
aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID --query "ResourceRecordSets[?contains(Name, 'n8n')]" --profile $AWS_PROFILE

# Note: You'll need to delete:
# 1. A record (created by External DNS)
# 2. TXT record (created by External DNS)
# 3. CNAME validation record (if manually created for certificate validation)

# For A and TXT records, create a deletion batch file with the EXACT values from the list command
# The load balancer DNS name in the A record must match exactly what's shown

# Example deletion (replace with actual values from list command):
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "n8n.'$YOUR_DOMAIN'.",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "Z26RNL4JYFTOTI",
        "DNSName": "your-exact-load-balancer.elb.amazonaws.com.",
        "EvaluateTargetHealth": true
      }
    }
  }]
}' --profile $AWS_PROFILE 2>/dev/null || echo "A record may already be deleted"
```

**Important**: If you manually created a certificate validation CNAME record (Step 6), it must be deleted separately:
- Look for records starting with an underscore (e.g., `_554370f6336e40f691fab3c97ebaeaa8.n8n.yourdomain.com`)
- These won't be automatically removed and will persist in your Route53 zone

**Alternative method**: You can also delete Route53 records through the AWS Console:
1. Go to Route53 → Hosted zones → Your domain
2. Select all records containing "n8n"
3. Click "Delete"
4. Don't forget validation CNAME records (starting with underscore)

#### 5. Delete SSL Certificate

```bash
# List certificates for your domain
aws acm list-certificates --query "CertificateSummaryList[?DomainName=='n8n.$YOUR_DOMAIN'].CertificateArn" --region $AWS_REGION --profile $AWS_PROFILE

# Delete the certificate (replace with actual ARN)
# aws acm delete-certificate --certificate-arn arn:aws:acm:region:account:certificate/id --region $AWS_REGION --profile $AWS_PROFILE
```

#### 6. Verify CloudFormation Stacks

```bash
# Check for any remaining CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName, '$CLUSTER_NAME')].[StackName,StackStatus]" --output table --region $AWS_REGION --profile $AWS_PROFILE

# Delete any remaining stacks manually if needed
# aws cloudformation delete-stack --stack-name <stack-name> --region $AWS_REGION --profile $AWS_PROFILE
```

### Verification Steps

After cleanup, verify all resources are removed:

```bash
# 1. Check EKS clusters
aws eks list-clusters --region $AWS_REGION --profile $AWS_PROFILE

# 2. Check Load Balancers
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')]" --region $AWS_REGION --profile $AWS_PROFILE

# 3. Check EC2 instances
# Option 1: Simple table output
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --region $AWS_REGION --profile $AWS_PROFILE --output table

# Option 2: With jq (if installed) - shows only running instances
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --region $AWS_REGION --profile $AWS_PROFILE | jq '.Reservations[].Instances[] | select(.State.Name != "terminated") | {InstanceId, State: .State.Name}'

# 4. Check VPCs (if created by eksctl)
aws ec2 describe-vpcs --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=$CLUSTER_NAME" --region $AWS_REGION --profile $AWS_PROFILE

# 5. Check Security Groups
aws ec2 describe-security-groups --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --region $AWS_REGION --profile $AWS_PROFILE --query "SecurityGroups[].GroupId"

# 6. Check EBS volumes
# Option 1: Simple table output
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --region $AWS_REGION --profile $AWS_PROFILE --output table

# Option 2: With jq (if installed)
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --region $AWS_REGION --profile $AWS_PROFILE | jq '.Volumes[] | {VolumeId, State}'

# 7. Check IAM roles
aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-$CLUSTER_NAME')].[RoleName]" --output table --profile $AWS_PROFILE

# 8. Check CloudWatch Log Groups
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/$CLUSTER_NAME" --region $AWS_REGION --profile $AWS_PROFILE --query "logGroups[].logGroupName"
```

### Cost Implications

Resources that continue to incur charges if not deleted:
- **EKS Cluster**: $0.10/hour (~$72/month)
- **EC2 Instances**: Variable based on instance type
- **Load Balancers**: ~$0.025/hour plus data transfer
- **EBS Volumes**: $0.10/GB/month
- **Elastic IPs**: $0.005/hour if not attached

### Troubleshooting Cleanup Issues

1. **"Cannot delete cluster with nodegroups"**
   - Delete nodegroups first: `eksctl delete nodegroup --cluster=$CLUSTER_NAME --name=<nodegroup-name> --region=$AWS_REGION`

2. **"Load balancer still exists"**
   - Wait longer for automatic deletion
   - Manually delete via AWS Console or CLI

3. **"Stack deletion failed"**
   - Check CloudFormation console for specific errors
   - May need to manually delete resources blocking the stack

4. **"IAM role cannot be deleted"**
   - Detach all policies first
   - Remove trust relationships
   - Check for inline policies

### Final Notes

- Always verify all resources are deleted to avoid unexpected charges
- Some resources like CloudWatch logs may persist (minimal cost)
- If you plan to redeploy, keeping IAM policies can save time
- Check your AWS bill after 24 hours to ensure no unexpected resources remain

### Post-Cleanup Checklist

After running cleanup, ensure these items don't appear in your AWS bill next month:
- [ ] No EKS cluster charges ($0.10/hour)
- [ ] No EC2 instance charges
- [ ] No EBS volume charges
- [ ] No Load Balancer charges
- [ ] No NAT Gateway charges (if VPC was deleted)
- [ ] Check CloudTrail for any remaining API calls to these services

### Partial Cleanup Scenarios

If cleanup fails partway through:

1. **Cluster deleted but resources remain**: Check CloudFormation stacks for deletion failures
2. **Can't delete VPC**: Check for remaining ENIs (Elastic Network Interfaces)
3. **IAM roles won't delete**: Ensure all policies are detached first
4. **Route53 records won't delete**: Ensure you're using the exact values from the list command
5. **Security groups won't delete**: Check for dependencies (other resources using them)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is released into the public domain. See the LICENSE file for details.

## Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Community Forum](https://community.n8n.io/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Support

For issues specific to this deployment guide, please open an issue in this repository. For n8n-specific questions, visit the [n8n community forum](https://community.n8n.io/).