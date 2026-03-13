# AWS EKS Cluster with Terraform

This Terraform configuration deploys a production-ready AWS EKS (Elastic Kubernetes Service) cluster.

## Why EKS over self-managed kubeadm?

✅ **Fully managed control plane** - AWS handles master nodes, upgrades, and patches  
✅ **Reliable and tested** - Production-ready, used by thousands of companies  
✅ **Auto-scaling** - Built-in support for cluster autoscaler  
✅ **AWS integration** - Native integration with ALB, EBS, IAM, CloudWatch  
✅ **Security** - Automatic security patches and compliance certifications  
✅ **No repository issues** - Uses AWS-managed Kubernetes packages  

## Architecture

- **VPC Module**: Creates VPC with public and private subnets across 2 AZs
- **NAT Gateway**: Enables private subnet internet access (for pulling container images)
- **EKS Control Plane**: AWS-managed Kubernetes master nodes (HA across multiple AZs)
- **EKS Managed Node Group**: Auto-scaling worker nodes in private subnets
- **Add-ons**: CoreDNS, kube-proxy, VPC CNI

## Prerequisites

1. **AWS CLI configured** with appropriate credentials
   ```bash
   aws configure
   aws sts get-caller-identity  # Verify credentials
   ```

2. **Terraform installed** (version >= 1.0)
   ```bash
   terraform version
   ```

3. **kubectl installed** (optional, for cluster management)
   ```bash
   kubectl version --client
   ```

4. **Sufficient AWS permissions** to create:
   - VPC, subnets, route tables, NAT gateway
   - EKS cluster and node groups
   - IAM roles and policies
   - Security groups
   - EC2 instances

## Quick Start

### 1. Initialize Terraform
```bash
cd eks-cluster
terraform init
terraform validate
```

### 2. Review the Plan
```bash
terraform plan -out tfplan1
```

### 3. Deploy the Cluster
```bash
terraform apply
```
Type `yes` when prompted. **Deployment takes 10-15 minutes.**

### 4. Configure kubectl
After deployment completes, configure kubectl to access your cluster:

```bash
# Get the command from Terraform output
terraform output configure_kubectl

# Run the command (example):
aws eks update-kubeconfig --region us-east-1 --name my-eks-cluster

# Verify cluster access
kubectl get nodes
kubectl get pods -A
```

## Configuration Variables

Customize the deployment by creating a `terraform.tfvars` file:

```hcl
cluster_name    = "production-eks"
cluster_version = "1.31"

node_desired_size   = 3
node_min_size       = 2
node_max_size       = 5
node_instance_types = ["t3.medium"]

aws_region = "us-west-2"

tags = {
  Environment = "production"
  Team        = "platform"
}
```

## Default Configuration

- **Region**: us-east-1
- **Kubernetes Version**: 1.31
- **Worker Nodes**: 2x t3.small (min: 1, max: 3)
- **VPC CIDR**: 10.0.0.0/16
- **Private Subnets**: 10.0.1.0/24, 10.0.2.0/24 (for nodes)
- **Public Subnets**: 10.0.101.0/24, 10.0.102.0/24 (for load balancers)
- **NAT Gateway**: Single NAT (use `single_nat_gateway = false` for HA)

## Post-Deployment

### Access the Cluster
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name my-eks-cluster

# View cluster info
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

### Deploy a Sample Application
```bash
# Create a deployment
kubectl create deployment nginx --image=nginx

# Expose it with a LoadBalancer
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Get the external URL (takes a few minutes)
kubectl get svc nginx
```

### Install Common Add-ons

**AWS Load Balancer Controller** (for ALB ingress):
```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-eks-cluster
```

**Cluster Autoscaler**:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

**Metrics Server**:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Cost Breakdown

**EKS Control Plane**: $0.10/hour (~$73/month)  
**NAT Gateway**: $0.045/hour (~$32/month)  
**Worker Nodes (2x t3.small)**: $0.042/hour (~$60/month)  
**Data Transfer**: Variable  

**Total estimated cost**: ~$165/month for the default configuration

💡 **Cost savings tips**:
- Use Spot instances for non-production workloads
- Scale down nodes when not in use
- Use a single NAT gateway (already default)
- Consider Fargate for specific workloads

## Upgrading Kubernetes Version

EKS supports in-place upgrades:

```bash
# Update cluster_version in variables.tf or terraform.tfvars
cluster_version = "1.32"

# Apply the change
terraform apply
```

Node groups will be updated automatically with a rolling update strategy.

## Scaling

### Manual Scaling
Edit the variables and apply:
```hcl
node_desired_size = 5
```

```bash
terraform apply
```

### Auto Scaling
Install the Cluster Autoscaler (see Post-Deployment section above).

## Security Best Practices

✅ **Enabled by default**:
- Private worker nodes (in private subnets)
- IMDSv2 required for EC2 metadata
- IAM roles for service accounts (IRSA)
- Encryption at rest for secrets
- Security groups with minimal access

⚠️ **Additional recommendations for production**:
- Enable VPC Flow Logs
- Enable CloudWatch Container Insights
- Use AWS Secrets Manager for sensitive data
- Implement Pod Security Standards
- Enable audit logging
- Use private cluster endpoint (set `cluster_endpoint_public_access = false`)

## Troubleshooting

### Nodes Not Joining Cluster
```bash
# Check node group status in AWS Console or:
aws eks describe-nodegroup --cluster-name my-eks-cluster --nodegroup-name <nodegroup-name>

# Check EC2 instances
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=my-eks-cluster"
```

### kubectl Connection Issues
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name my-eks-cluster

# Test connection
kubectl get svc
```

### Pods Stuck in Pending
```bash
# Check node resources
kubectl describe nodes

# Check pod events
kubectl describe pod <pod-name>

# Common causes:
# - Insufficient capacity (scale up nodes)
# - Resource requests too high
# - Node selector mismatch
```

## Cleanup

To destroy all resources:

```bash
# Delete any LoadBalancer services first (to remove AWS ALBs/NLBs)
kubectl delete svc --all

# Destroy the cluster
terraform destroy
```

Type `yes` when prompted. **Destruction takes 10-15 minutes.**

⚠️ **Important**: Ensure all LoadBalancer and PersistentVolumeClaim resources are deleted first, or Terraform may fail to delete the VPC due to leftover ENIs and EBS volumes.

## Comparison: EKS vs Self-Managed kubeadm

| Feature | EKS | Self-Managed kubeadm |
|---------|-----|---------------------|
| Control plane management | AWS managed | You manage |
| Upgrades | One-click | Manual, complex |
| HA control plane | Built-in | Manual setup required |
| Cost | $73/mo + nodes | Nodes only |
| Reliability | 99.95% SLA | Your responsibility |
| Setup time | 15 minutes | 30-60 minutes (when it works) |
| Maintenance | Minimal | Ongoing |
| AWS integration | Native | Manual configuration |
| Security patches | Automatic | Manual |
| Support | AWS support available | Community only |

## Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Terraform AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws)
- [Terraform AWS VPC Module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
