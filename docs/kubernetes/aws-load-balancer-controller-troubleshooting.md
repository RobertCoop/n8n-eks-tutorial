# AWS Load Balancer Controller Troubleshooting

This guide provides solutions for common issues with the AWS Load Balancer Controller.

## Leader Election Error

If you see an error like this in the logs:

```
{"level":"error","ts":"2025-05-19T23:57:12Z","msg":"error initially creating leader election record: leases.coordination.k8s.io \"aws-load-balancer-controller-leader\" already exists","errorError":"PANIC=runtime error: invalid memory address or nil pointer dereference"}
```

This indicates a problem with the leader election lease. Follow these steps to fix it:

### Step 1: Delete the existing leader election lease

```bash
kubectl delete lease aws-load-balancer-controller-leader -n kube-system
```

### Step 2: Check for any existing AWS Load Balancer Controller resources

```bash
# Check for existing deployments
kubectl get deployments -n kube-system | grep aws-load-balancer-controller

# Check for existing pods
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

### Step 3: Delete any existing AWS Load Balancer Controller resources

```bash
# Delete the deployment
kubectl delete deployment aws-load-balancer-controller -n kube-system

# Delete any pods (if they still exist)
kubectl delete pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Step 4: Reinstall the AWS Load Balancer Controller

If you installed with Helm:

```bash
helm uninstall aws-load-balancer-controller -n kube-system

# Then reinstall
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --set clusterName=n8n \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --namespace kube-system \
  --set region=us-east-2 \
  --set vpcId=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=n8n-vpc" --query "Vpcs[0].VpcId" --output text --profile lapis-dev)
```

If you're not sure about the VPC ID, you can find it with:

```bash
aws ec2 describe-vpcs --profile lapis-dev
```

Look for the VPC that's associated with your EKS cluster.

### Step 5: Verify the controller is running

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

You should see the controller pods in a Running state.

## Other Common Issues

### Missing IAM Permissions

If the controller is running but not creating load balancers, check the IAM permissions:

```bash
# Get the IAM role ARN
kubectl describe serviceaccount aws-load-balancer-controller -n kube-system

# Check the policies attached to the role
aws iam list-attached-role-policies --role-name ROLE_NAME --profile lapis-dev
```

Replace ROLE_NAME with the name of the IAM role (not the full ARN).

Common permission errors include:

1. **AccessDenied: User is not authorized to perform: ec2:GetSecurityGroupsForVpc**
2. **AccessDenied: User is not authorized to perform: elasticloadbalancing:DescribeListenerAttributes**

To fix these permission issues, we've provided an additional IAM policy and a script to apply it:

1. `aws-load-balancer-controller-additional-policy.json`: Contains the missing permissions
2. `update-aws-load-balancer-controller-permissions.sh`: Script to create and attach the policy

Run the script to add the missing permissions:

```bash
chmod +x update-aws-load-balancer-controller-permissions.sh
./update-aws-load-balancer-controller-permissions.sh
```

This will:
- Create a new IAM policy with the missing permissions
- Attach it to the IAM role used by the AWS Load Balancer Controller
- Restart the controller pods to pick up the new permissions

### Controller Not Watching Services

If the controller is running but not processing your service, check if it's configured to watch the correct namespace:

```bash
kubectl get deployment aws-load-balancer-controller -n kube-system -o yaml
```

Look for the `--watch-namespace` argument. If it's set, make sure it includes the namespace where your service is deployed.

### Incorrect Annotations

If the controller is running but not creating the load balancer correctly, check your service annotations:

```bash
kubectl get svc n8n -n n8n -o yaml
```

Make sure the annotations are correct, especially:
- `service.beta.kubernetes.io/aws-load-balancer-type: "external"`
- `service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"`

### Checking Controller Logs

For more detailed troubleshooting, check the controller logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

Look for any error messages that might indicate what's going wrong.