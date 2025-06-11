# Setting up ExternalDNS for Automatic DNS Management with Route53

This guide explains how to set up ExternalDNS in your AWS EKS cluster to automatically manage DNS records in Route53 for your n8n deployment.

## Prerequisites

1. An AWS EKS cluster
2. A domain configured in Route53
3. kubectl configured to communicate with your EKS cluster
4. AWS CLI installed and configured

## Step 1: Create IAM Policy for ExternalDNS

ExternalDNS needs permissions to manage DNS records in Route53. Create an IAM policy with the following permissions:

```bash
cat > external-dns-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF

# Create the policy
aws iam create-policy \
  --policy-name "AllowExternalDNSUpdates" \
  --policy-document file://external-dns-policy.json
```

Note the ARN of the created policy for the next step.

## Step 2: Create IAM Role for ExternalDNS

You can create an IAM role for the ExternalDNS service account using eksctl or the AWS Management Console.

### Using eksctl:

```bash
eksctl create iamserviceaccount \
  --cluster=<CLUSTER_NAME> \
  --namespace=kube-system \
  --name=external-dns \
  --attach-policy-arn=arn:aws:iam::<AWS_ACCOUNT_ID>:policy/AllowExternalDNSUpdates \
  --region <AWS_REGION> \
  --approve
```

Replace `<CLUSTER_NAME>`, `<AWS_ACCOUNT_ID>`, and `<AWS_REGION>` with your actual values.

**Important**: If you use eksctl to create the service account, you must remove the ServiceAccount section from the external-dns.yaml file before applying it, as eksctl already creates the service account with the proper IAM role annotation.

## Step 3: Deploy ExternalDNS

Create a file named `external-dns.yaml` with the following content:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services","endpoints","pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions","networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: k8s.gcr.io/external-dns/external-dns:v0.10.2
        args:
        - --source=service
        - --source=ingress
        - --domain-filter=dev.lapislegal.com # Replace with your domain
        - --provider=aws
        - --policy=upsert-only # Prevent ExternalDNS from deleting existing records
        - --aws-zone-type=public # Only look at public hosted zones
        - --registry=txt
        - --txt-owner-id=my-eks-cluster # Replace with your cluster name
```

**Note**: If you used eksctl to create the service account in Step 2, remove the ServiceAccount section (lines 74-78) from the YAML above before applying.

Apply the configuration:

```bash
# If you used eksctl, first remove the ServiceAccount section
sed -i '/^apiVersion: v1$/,/^---$/d' external-dns.yaml

# Then apply
kubectl apply -f external-dns.yaml
```

## Step 4: Verify ExternalDNS Installation

Check if the ExternalDNS pod is running:

```bash
kubectl get pods -n kube-system | grep external-dns
```

## Step 5: Add Annotations to Your Services

The n8n-service.yaml file has already been updated with the necessary annotation:

```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: "n8n.dev.lapislegal.com"
```

This annotation tells ExternalDNS to create a DNS record for this service with the specified hostname.

## Step 6: Verify DNS Record Creation

After deploying your service, verify that the DNS record has been created in Route53. 

**Note**: External DNS may take 2-5 minutes to create DNS records after the Load Balancer is fully provisioned. The Load Balancer itself takes 2-3 minutes to provision after the service is created.

```bash 
aws route53 list-resource-record-sets \
  --hosted-zone-id <YOUR_HOSTED_ZONE_ID> \
  --query "ResourceRecordSets[?Name=='n8n.dev.lapislegal.com.']"
```

Replace `<YOUR_HOSTED_ZONE_ID>` with your actual Route53 hosted zone ID.

## Troubleshooting

If DNS records are not being created, check the ExternalDNS logs:

```bash
kubectl logs -n kube-system $(kubectl get pods -n kube-system -l app=external-dns -o name)
```

## Additional Resources

- [ExternalDNS GitHub Repository](https://github.com/kubernetes-sigs/external-dns)
- [ExternalDNS AWS Tutorial](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)