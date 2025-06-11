# Setting up ACM Certificates for n8n on AWS EKS

This guide explains how to create and manage SSL certificates using AWS Certificate Manager (ACM) for your n8n deployment on AWS EKS.

## Prerequisites

1. An AWS account with appropriate permissions
2. A registered domain in Route53 (in this case, dev.lapislegal.com)
3. AWS CLI installed and configured

## Step 1: Request an SSL Certificate in ACM

You can request a certificate using the AWS Management Console or the AWS CLI:

### Using AWS CLI:

```bash
aws acm request-certificate \
  --domain-name n8n.dev.lapislegal.com \
  --validation-method DNS \
  --region us-east-2
  --profile lapis-dev  # Use the same region as your EKS cluster
```

Note: If your load balancer is in a different region than us-east-1, make sure to request the certificate in the same region as your load balancer.

The command will return a certificate ARN that looks like:
```
{
    "CertificateArn": "arn:aws:acm:us-east-2:640168410456:certificate/8d8cf0c5-6da6-4ec6-b823-e98b9771e1dc"
}
```

Save this ARN as you'll need it for the next steps.

### Using AWS Management Console:

1. Open the AWS Certificate Manager console
2. Click "Request a certificate"
3. Select "Request a public certificate" and click "Next"
4. Enter your domain name (e.g., n8n.dev.lapislegal.com)
5. Select "DNS validation" as the validation method
6. Click "Request"

## Step 2: Validate the Certificate

If your domain is managed by Route53, ACM can automatically create the validation records:

1. In the ACM console, select your certificate
2. Click "Create records in Route 53"
3. Click "Create records"

If you're using the AWS CLI or if your domain is not in Route53, you'll need to create the validation records manually:

```bash
# Get the validation details
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 \
  --region us-east-1

# Create the validation record in Route53
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_HOSTED_ZONE_ID \
  --change-batch file://validation-record.json
```

Where validation-record.json contains the CNAME record details from the describe-certificate output.

## Step 3: Update the n8n Service with the Certificate ARN

Once the certificate is validated and issued, update the n8n-service.yaml file with the certificate ARN:

```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
```

Replace the ARN with your actual certificate ARN.

## Step 4: Apply the Updated Service Configuration

Apply the updated service configuration:

```bash
kubectl apply -f n8n-service.yaml
```

## Step 5: Verify the Certificate is Being Used

After applying the updated service configuration, verify that the load balancer is using the certificate:

1. Get the load balancer name:
   ```bash
   kubectl get svc n8n -n n8n -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```

2. Describe the load balancer in AWS CLI:
   ```bash
   aws elbv2 describe-listeners \
     --load-balancer-arn $(aws elbv2 describe-load-balancers \
       --names YOUR_LOAD_BALANCER_NAME \
       --query 'LoadBalancers[0].LoadBalancerArn' \
       --output text) \
     --query 'Listeners[?Port==`443`]'
   ```

   Replace YOUR_LOAD_BALANCER_NAME with the actual load balancer name.

3. Verify that the certificate ARN is listed in the output.

## Certificate Renewal

ACM automatically renews certificates that are issued through it. You don't need to manually renew certificates as long as the validation records remain in place.

## Troubleshooting

### Certificate Not Being Used by Load Balancer

If the load balancer is not using the certificate:

1. Verify that the certificate is in the "Issued" state in ACM
2. Ensure the certificate ARN in the service annotation is correct
3. Check that the certificate is in the same region as the load balancer
4. Verify that the AWS Load Balancer Controller has the necessary permissions to access the certificate

### Certificate Validation Issues

If the certificate is stuck in the "Pending validation" state:

1. Verify that the validation records are correctly set up in your DNS
2. For Route53, ensure that ACM has permissions to create validation records
3. DNS propagation can take time; wait up to 24 hours for validation to complete

## Additional Resources

- [AWS Certificate Manager User Guide](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)
- [Using ACM with Elastic Load Balancing](https://docs.aws.amazon.com/acm/latest/userguide/acm-services.html#acm-elastic-load-balancing)
- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/)