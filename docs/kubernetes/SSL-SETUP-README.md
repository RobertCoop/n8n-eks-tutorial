# Automatic SSL Certificate Setup for n8n on AWS EKS

This document provides an overview of the changes made to automatically set up SSL certificates for the n8n deployment on AWS EKS using Route53 and AWS Certificate Manager (ACM).

## Changes Made

1. **Updated n8n-service.yaml**:
   - Added annotations to configure the AWS Load Balancer to use ACM certificates
   - Changed the protocol for port 443 from SSL to TCP (AWS Load Balancer Controller handles SSL termination)
   - Added annotations for ExternalDNS integration

2. **Created Documentation**:
   - `acm-certificate-setup.md`: Instructions for creating and managing ACM certificates
   - `external-dns-setup.md`: Instructions for setting up ExternalDNS for automatic DNS management
   - `aws-load-balancer-controller-setup.md`: Instructions for installing the AWS Load Balancer Controller

## Overview of the Solution

The solution consists of three main components:

1. **AWS Load Balancer Controller**:
   - Provisions and manages AWS Load Balancers based on Kubernetes service annotations
   - Handles SSL termination using ACM certificates
   - **This component is required and must be installed first**

2. **SSL Certificate Management with ACM**:
   - Request and validate an SSL certificate in AWS Certificate Manager
   - Configure the AWS Load Balancer to use this certificate for SSL termination
   - The Load Balancer handles the SSL/TLS termination and forwards decrypted traffic to the n8n service

3. **Automatic DNS Management with ExternalDNS**:
   - Deploy ExternalDNS in the EKS cluster
   - ExternalDNS automatically creates and updates DNS records in Route53 based on Kubernetes service annotations
   - This ensures that your domain name always points to the correct Load Balancer

## Implementation Steps

1. **Install AWS Load Balancer Controller**:
   - Follow the instructions in `aws-load-balancer-controller-setup.md` to install the AWS Load Balancer Controller
   - This is a critical component and must be installed for the SSL certificate setup to work

2. **Create an ACM Certificate**:
   - Follow the instructions in `acm-certificate-setup.md` to request and validate an SSL certificate
   - Update the n8n-service.yaml file with the certificate ARN

3. **Set Up ExternalDNS**:
   - Follow the instructions in `external-dns-setup.md` to deploy ExternalDNS
   - The n8n service is already annotated with the correct hostname

4. **Apply the Updated Configuration**:
   - Apply the updated n8n-service.yaml file to your cluster
   - Verify that the Load Balancer is using the certificate and that DNS records are created

## Key Annotations in n8n-service.yaml

```yaml
annotations:
  # Specify the ARN of your ACM certificate
  service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:REGION:ACCOUNT_ID:certificate/CERTIFICATE_ID"
  # Specify which ports should use SSL
  service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
  # Specify the SSL policy
  service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: "ELBSecurityPolicy-TLS13-1-2-2021-06"
  # Specify the backend protocol
  service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
  # Enable cross-zone load balancing
  service.beta.kubernetes.io/aws-load-balancer-attributes: "load_balancing.cross_zone.enabled=true"
  # Set the load balancer type to be managed by AWS Load Balancer Controller
  service.beta.kubernetes.io/aws-load-balancer-type: "external"
  # Set the target type to instance
  service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"
  # Set the scheme to internet-facing
  service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  # Add DNS record annotation for ExternalDNS
  external-dns.alpha.kubernetes.io/hostname: "n8n.dev.lapislegal.com"
```

## Prerequisites

- AWS EKS cluster
- Domain configured in Route53 (dev.lapislegal.com)
- IAM permissions to create and manage ACM certificates and Route53 records
- AWS Load Balancer Controller installed in the cluster

## Troubleshooting

If you're experiencing issues with the SSL certificate setup, check the following:

1. **AWS Load Balancer Controller**: Ensure the controller is installed and running correctly
2. **LoadBalancer Provisioning**: Check if the LoadBalancer has been provisioned with an external IP/hostname
3. **ACM Certificate**: Verify that the certificate is in the "Issued" state and the ARN is correct
4. **ExternalDNS**: Check the ExternalDNS logs for any errors

## Troubleshooting

If you encounter issues with the SSL certificate setup, refer to these troubleshooting guides:

- [AWS Load Balancer Controller Troubleshooting](aws-load-balancer-controller-troubleshooting.md): Solutions for common issues with the AWS Load Balancer Controller, including leader election errors, missing IAM permissions, and more.

Common issues include:

1. **AWS Load Balancer Controller Installation Failures**:
   - Leader election errors
   - Missing IAM permissions
   - See the [troubleshooting guide](aws-load-balancer-controller-troubleshooting.md) for solutions

2. **LoadBalancer Not Being Provisioned**:
   - Check the AWS Load Balancer Controller logs
   - Verify the service annotations are correct
   - Ensure the controller has the necessary IAM permissions
   - **IAM Permission Issues**: The controller may be missing required permissions like `ec2:GetSecurityGroupsForVpc` or `elasticloadbalancing:DescribeListenerAttributes`
   - Use the provided `update-aws-load-balancer-controller-permissions.sh` script to add the missing permissions

3. **SSL Certificate Not Being Used**:
   - Verify the certificate ARN is correct
   - Check that the certificate is in the "Issued" state in ACM
   - Ensure the certificate is in the same region as your EKS cluster

4. **DNS Records Not Being Created**:
   - Verify that ExternalDNS is running correctly
   - Check that ExternalDNS has the necessary IAM permissions
   - Ensure the LoadBalancer has been provisioned with an external IP/hostname

## Additional Files

We've created the following additional files to help troubleshoot and fix issues:

1. `aws-load-balancer-controller-additional-policy.json`: Contains additional IAM permissions required by the AWS Load Balancer Controller for SSL certificate management.

2. `update-aws-load-balancer-controller-permissions.sh`: Script to create and attach the additional IAM policy to the AWS Load Balancer Controller role.

To use these files:

```bash
# Make the script executable
chmod +x update-aws-load-balancer-controller-permissions.sh

# Run the script to add the missing permissions
./update-aws-load-balancer-controller-permissions.sh
```

## Additional Resources

- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [ExternalDNS GitHub Repository](https://github.com/kubernetes-sigs/external-dns)
- [AWS Certificate Manager User Guide](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)