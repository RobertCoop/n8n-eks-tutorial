# Troubleshooting Guide for n8n on AWS EKS

This guide covers common issues and their solutions when deploying n8n on AWS EKS.

## Table of Contents

- [Load Balancer Issues](#load-balancer-issues)
- [DNS and Certificate Issues](#dns-and-certificate-issues)
- [Deployment Issues](#deployment-issues)
- [Networking Issues](#networking-issues)
- [Database Issues](#database-issues)
- [Performance Issues](#performance-issues)
- [SSL/TLS Issues](#ssltls-issues)
- [Storage Issues](#storage-issues)
- [Debugging Commands](#debugging-commands)

## Load Balancer Issues

### Load Balancer Stuck in Pending State (Most Common Issue)

**Symptoms:**
- `kubectl get svc n8n -n n8n` shows `<pending>` for EXTERNAL-IP
- Service events show "FailedDeployModel" errors
- Errors about `elasticloadbalancing:DescribeListenerAttributes`

**Root Cause:**
The AWS Load Balancer Controller IAM policy is missing permissions for SSL/TLS configuration.

**Solution:**

1. Check service events to confirm the issue:
```bash
kubectl describe svc n8n -n n8n | grep -A 10 Events
```

2. If you see permission errors, attach the additional policy:
```bash
# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get the service account role
SERVICE_ACCOUNT_ROLE=$(kubectl get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | awk -F'/' '{print $NF}')

# Attach the additional policy (should already exist)
aws iam attach-role-policy \
  --role-name $SERVICE_ACCOUNT_ROLE \
  --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerAdditionalPolicy

# Restart the controller to pick up new permissions
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system

# Delete and recreate the service
kubectl delete svc n8n -n n8n
kubectl apply -f kubernetes/n8n/n8n-service-configured.yaml
```

3. Wait for the Load Balancer to be provisioned (2-3 minutes):
```bash
kubectl get svc n8n -n n8n -w
```

## DNS and Certificate Issues

### DNS Record Not Created by External DNS

**Symptoms:**
- Domain doesn't resolve
- No DNS record in Route53 for your n8n domain

**Solution:**

1. Check External DNS logs:
```bash
kubectl logs -n kube-system deployment/external-dns --tail=20
```

2. Verify the Load Balancer has an external hostname:
```bash
kubectl get svc n8n -n n8n
```

3. Check if DNS record exists:
```bash
# Get your hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='your-domain.com.'].Id" --output text | cut -d'/' -f3)

# Check for n8n records
aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID | grep n8n
```

4. Force External DNS to rescan:
```bash
kubectl rollout restart deployment/external-dns -n kube-system
```

Note: External DNS may take 2-5 minutes to create records after the Load Balancer is ready.

### Certificate Stuck in PENDING_VALIDATION

**Symptoms:**
- ACM certificate not validating
- Certificate status shows "PENDING_VALIDATION"

**Solution:**

1. Get validation records:
```bash
aws acm describe-certificate \
  --certificate-arn <YOUR_CERT_ARN> \
  --region <YOUR_REGION> \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

2. Add the validation record to Route53:
```bash
# Create validation record JSON
cat > validation.json << EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "<VALIDATION_NAME>",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{
        "Value": "<VALIDATION_VALUE>"
      }]
    }
  }]
}
EOF

# Apply the change
aws route53 change-resource-record-sets \
  --hosted-zone-id <YOUR_ZONE_ID> \
  --change-batch file://validation.json
```

## Deployment Issues

### Pod Stuck in Pending State

**Symptoms:**
- Pods remain in "Pending" status
- Events show scheduling failures

**Solutions:**

1. Check node resources:
```bash
kubectl describe nodes
kubectl top nodes
```

2. Check pod events:
```bash
kubectl describe pod -n n8n <pod-name>
```

3. Verify persistent volume claims:
```bash
kubectl get pvc -n n8n
kubectl describe pvc -n n8n <pvc-name>
```

4. Check if EBS CSI driver is installed:
```bash
kubectl get pods -n kube-system | grep ebs-csi
```

### Pod CrashLoopBackOff

**Symptoms:**
- Pod repeatedly crashes and restarts
- Status shows "CrashLoopBackOff"

**Solutions:**

1. Check pod logs:
```bash
kubectl logs -n n8n <pod-name> --previous
```

2. Check environment variables:
```bash
kubectl describe pod -n n8n <pod-name>
```

3. Verify database connectivity:
```bash
kubectl exec -it -n n8n deployment/n8n -- nc -zv postgres-service 5432
```

## Networking Issues

### Load Balancer Not Getting External IP

**Symptoms:**
- Service shows `<pending>` for EXTERNAL-IP
- No load balancer created in AWS

**Solutions:**

1. Check AWS Load Balancer Controller:
```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

2. Verify IAM permissions:
```bash
eksctl get iamserviceaccount --cluster=<cluster-name>
```

3. Check service annotations:
```bash
kubectl describe svc n8n -n n8n
```

4. Verify subnets are tagged correctly:
- Public subnets: `kubernetes.io/role/elb: 1`
- Private subnets: `kubernetes.io/role/internal-elb: 1`

### DNS Record Not Created

**Symptoms:**
- Domain doesn't resolve to load balancer
- No Route53 record created

**Solutions:**

1. Check External DNS logs:
```bash
kubectl logs -n kube-system deployment/external-dns
```

2. Verify Route53 permissions:
```bash
aws iam get-role-policy --role-name <external-dns-role> --policy-name <policy-name>
```

3. Check domain filter configuration:
```bash
kubectl describe deployment external-dns -n kube-system
```

4. Verify hosted zone exists:
```bash
aws route53 list-hosted-zones
```

## Database Issues

### PostgreSQL Connection Failed

**Symptoms:**
- n8n pod can't connect to database
- Error: "connection refused" or "no pg_hba.conf entry"

**Solutions:**

1. Check PostgreSQL pod status:
```bash
kubectl get pod -n n8n -l service=postgres-n8n
kubectl logs -n n8n deployment/postgres
```

2. Verify secret exists:
```bash
kubectl get secret postgres-secret -n n8n
kubectl describe secret postgres-secret -n n8n
```

3. Test database connection:
```bash
kubectl exec -it -n n8n deployment/postgres -- psql -U postgres -d n8n -c "\l"
```

4. Check PostgreSQL service:
```bash
kubectl get svc postgres-service -n n8n
kubectl describe svc postgres-service -n n8n
```

### Database Disk Full

**Symptoms:**
- PostgreSQL errors about disk space
- Pods failing to write data

**Solutions:**

1. Check PVC usage:
```bash
kubectl exec -n n8n deployment/postgres -- df -h /var/lib/postgresql/data
```

2. Expand PVC (if using dynamic provisioning):
```bash
kubectl edit pvc postgresql-pv -n n8n
# Change spec.resources.requests.storage to larger value
```

3. Clean up old data:
```bash
kubectl exec -n n8n deployment/postgres -- psql -U postgres -d n8n -c "VACUUM FULL;"
```

## Performance Issues

### Slow Response Times

**Symptoms:**
- n8n UI is slow
- Workflows execute slowly

**Solutions:**

1. Check resource usage:
```bash
kubectl top pod -n n8n
kubectl top node
```

2. Increase resource limits:
```yaml
# Edit n8n-deployment.yaml
resources:
  requests:
    memory: "500Mi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "2000m"
```

3. Scale horizontally:
```bash
kubectl scale deployment n8n -n n8n --replicas=3
```

4. Enable horizontal pod autoscaling:
```bash
kubectl autoscale deployment n8n -n n8n --min=1 --max=5 --cpu-percent=80
```

## SSL/TLS Issues

### Certificate Not Working

**Symptoms:**
- HTTPS not working
- Certificate errors in browser

**Solutions:**

1. Verify certificate status in ACM:
```bash
aws acm describe-certificate --certificate-arn <cert-arn>
```

2. Check service annotations:
```bash
kubectl get svc n8n -n n8n -o yaml | grep -A 5 annotations
```

3. Verify load balancer listeners:
```bash
aws elbv2 describe-load-balancers --names <load-balancer-name>
aws elbv2 describe-listeners --load-balancer-arn <lb-arn>
```

4. Check certificate validation:
```bash
openssl s_client -connect <your-domain>:443 -servername <your-domain>
```

## Storage Issues

### Persistent Volume Claim Pending

**Symptoms:**
- PVC stuck in "Pending" status
- Pods can't start due to volume issues

**Solutions:**

1. Check storage class:
```bash
kubectl get storageclass
kubectl describe storageclass gp2
```

2. Verify EBS CSI driver:
```bash
kubectl get pods -n kube-system | grep ebs-csi
kubectl logs -n kube-system -l app=ebs-csi-controller
```

3. Check IAM permissions for EBS:
```bash
aws iam get-role-policy --role-name <node-instance-role> --policy-name <policy-name>
```

4. Manually create PV if needed:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gp2
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: <volume-id>
```

## Debugging Commands

### General Debugging

```bash
# Get all resources in n8n namespace
kubectl get all -n n8n

# Describe all pods with issues
kubectl get pods -n n8n | grep -v Running | tail -n +2 | awk '{print $1}' | xargs -I {} kubectl describe pod {} -n n8n

# Get recent events
kubectl get events -n n8n --sort-by='.lastTimestamp'

# Check cluster status
kubectl cluster-info
eksctl get cluster --name=<cluster-name>

# Check node status
kubectl get nodes
kubectl describe nodes

# View controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
kubectl logs -n kube-system deployment/external-dns
kubectl logs -n kube-system daemonset/ebs-csi-node
```

### Advanced Debugging

```bash
# Enable verbose logging for n8n
kubectl set env deployment/n8n -n n8n N8N_LOG_LEVEL=debug

# Port forward to access n8n directly
kubectl port-forward -n n8n deployment/n8n 5678:5678

# Execute commands in pods
kubectl exec -it -n n8n deployment/n8n -- /bin/sh
kubectl exec -it -n n8n deployment/postgres -- psql -U postgres

# Check AWS resources
aws eks describe-cluster --name <cluster-name>
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned"
aws elbv2 describe-load-balancers
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

### Collecting Diagnostics

Create a diagnostic bundle:

```bash
#!/bin/bash
# Save as collect-diagnostics.sh

DIAG_DIR="n8n-diagnostics-$(date +%Y%m%d-%H%M%S)"
mkdir -p $DIAG_DIR

echo "Collecting diagnostics..."

# Cluster info
kubectl cluster-info dump > $DIAG_DIR/cluster-info-dump.txt

# n8n namespace resources
kubectl get all -n n8n -o yaml > $DIAG_DIR/n8n-resources.yaml

# Pod logs
for pod in $(kubectl get pods -n n8n -o name); do
  kubectl logs -n n8n $pod > $DIAG_DIR/${pod##*/}-logs.txt
done

# Events
kubectl get events -n n8n > $DIAG_DIR/events.txt

# Node info
kubectl describe nodes > $DIAG_DIR/nodes.txt

# Create archive
tar -czf $DIAG_DIR.tar.gz $DIAG_DIR/
rm -rf $DIAG_DIR

echo "Diagnostics saved to $DIAG_DIR.tar.gz"
```

## Getting Help

If you're still experiencing issues:

1. Check the [n8n community forum](https://community.n8n.io/)
2. Review [AWS EKS troubleshooting guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
3. Open an issue in this repository with:
   - Description of the problem
   - Steps to reproduce
   - Diagnostic bundle (see above)
   - Expected vs actual behavior