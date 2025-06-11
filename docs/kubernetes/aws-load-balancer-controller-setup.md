# Installing AWS Load Balancer Controller for EKS

This guide explains how to install the AWS Load Balancer Controller, which is required for the SSL certificate annotations to work properly with your n8n service.

## Prerequisites

1. An AWS EKS cluster
2. kubectl configured to communicate with your EKS cluster
3. AWS CLI installed and configured
4. Helm installed (optional, but recommended)

## Step 1: Create IAM Policy for AWS Load Balancer Controller

The AWS Load Balancer Controller needs permissions to create and manage AWS resources. Create an IAM policy with the necessary permissions:

```bash
# Download the IAM policy document
curl -o aws-load-balancer-controller-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json

# Create the IAM policy
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://aws-load-balancer-controller-iam-policy.json
```

Note the ARN of the created policy for the next step.

### Additional Policy for SSL/TLS Support

**Important**: The default IAM policy is missing some permissions required for SSL/TLS configuration. Create an additional policy:

```bash
# Create additional IAM policy for SSL support
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerAdditionalPolicy \
    --policy-document file://aws-load-balancer-controller-additional-policy.json
```

This additional policy includes permissions for:
- `elasticloadbalancing:DescribeListenerAttributes`
- `elasticloadbalancing:DescribeListeners`
- `elasticloadbalancing:DescribeRules`
- And other SSL-related operations

## Step 2: Create IAM Role for AWS Load Balancer Controller

Create an IAM role for the AWS Load Balancer Controller service account using eksctl:

```bash
eksctl create iamserviceaccount \
  --cluster=<CLUSTER_NAME> \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<AWS_ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region <AWS_REGION> \
  --approve
```

Replace the policy ARN with the one you noted in the previous step.

### Attach Additional Policy

After creating the service account, attach the additional policy:

```bash
# Get the service account role name
SERVICE_ACCOUNT_ROLE=$(kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | awk -F'/' '{print $NF}')

# Attach the additional policy
aws iam attach-role-policy \
  --role-name $SERVICE_ACCOUNT_ROLE \
  --policy-arn arn:aws:iam::<AWS_ACCOUNT_ID>:policy/AWSLoadBalancerControllerAdditionalPolicy
```

## Step 3: Install AWS Load Balancer Controller using Helm (Recommended)

The easiest way to install the AWS Load Balancer Controller is using Helm:

```bash
# Add the EKS chart repository
helm repo add eks https://aws.github.io/eks-charts

# Update the repository
helm repo update

# Install the AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --set clusterName=<CLUSTER_NAME> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --namespace kube-system \
  --set region=<AWS_REGION> \
  --set vpcId=<VPC_ID>
```

Replace the region and VPC ID with the appropriate values for your EKS cluster.

## Step 4: Verify Installation

Verify that the AWS Load Balancer Controller is running:

```bash
kubectl get deployment aws-load-balancer-controller -n kube-system
```

You should see the controller running with 1/1 pods available.

## Step 5: Apply the n8n Service Configuration

Apply the updated n8n-service.yaml file:

```bash
kubectl apply -f n8n-service.yaml
```

## Step 6: Verify LoadBalancer Creation

Check if the LoadBalancer has been created:

```bash
kubectl get svc n8n -n n8n
```

The EXTERNAL-IP field should now show a DNS name instead of `<pending>`.

## Step 7: Verify DNS Record Creation

Once the LoadBalancer is provisioned, ExternalDNS should automatically create a DNS record for n8n.dev.lapislegal.com. Verify this:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id Z02949571EOMUK6WR3VW7 \
  --query "ResourceRecordSets[?Name=='n8n.dev.lapislegal.com.']" \
  --profile lapis-dev
```

## Troubleshooting

If the AWS Load Balancer Controller is not working properly, check the logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

## Troubleshooting

If you encounter issues with the AWS Load Balancer Controller installation or operation, refer to the [AWS Load Balancer Controller Troubleshooting Guide](aws-load-balancer-controller-troubleshooting.md) for solutions to common problems.

Common issues include:
- Leader election errors
- Missing IAM permissions
- Controller not watching services
- Incorrect annotations

## Additional Resources

- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [AWS Load Balancer Controller GitHub Repository](https://github.com/kubernetes-sigs/aws-load-balancer-controller)