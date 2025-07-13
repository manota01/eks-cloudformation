# Production-Grade EKS Cluster Management

🚀 **Production-ready EKS cluster management using eksctl in Docker**

This repository provides a comprehensive solution for creating and managing production-grade Amazon EKS clusters using `eksctl` with a Docker-based approach. No need to install tools locally - everything runs in containers!

## 🎯 Features

- **Docker-based**: All tools (eksctl, kubectl, helm, AWS CLI) run in containers
- **Production-ready**: Multiple environments (dev, staging, production)
- **Comprehensive**: Includes monitoring, autoscaling, security, and networking
- **Automated**: Scripts for cluster lifecycle management
- **Flexible**: Multiple node groups (system, application, spot instances)
- **Observable**: Built-in monitoring with Prometheus and Grafana
- **Secure**: RBAC, OIDC, secrets encryption, and security best practices

## 📋 Prerequisites

- Docker installed and running
- AWS CLI configured locally (`~/.aws/credentials`)
- Sufficient AWS permissions for EKS cluster creation

## 🚀 Quick Start

1. **Clone and setup**:
   ```bash
   git clone <repository-url>
   cd eks-cloudformation
   ```

2. **Build the Docker image**:
   ```bash
   make build
   ```

3. **Create a development cluster**:
   ```bash
   make create-dev
   ```

4. **Access the cluster**:
   ```bash
   make dev-shell
   kubectl get nodes
   ```

## 🏗️ Architecture

### Cluster Components
- **Control Plane**: Managed by AWS EKS
- **Node Groups**: 
  - System nodes (t3.medium) - for system workloads
  - Application nodes (t3.large) - for application workloads  
  - Spot instances - for cost-optimized batch workloads
- **Networking**: Custom VPC with public/private subnets
- **Security**: RBAC, OIDC, secrets encryption
- **Monitoring**: Prometheus, Grafana, CloudWatch

### Add-ons Included
- **AWS Load Balancer Controller** - Manages AWS ALB/NLB for ingress
- **Cluster Autoscaler** - Automatically scales node groups
- **External DNS** - Automatic DNS record management
- **Cert Manager** - Automated SSL/TLS certificate management
- **Monitoring Stack** - Prometheus, Grafana, and CloudWatch
- **NGINX Ingress Controller** - HTTP/HTTPS ingress controller

*All add-ons are modular and can be installed independently*

## 📁 Project Structure

```
eks-cloudformation/
├── cluster-config/           # EKS cluster configurations
│   ├── production-cluster.yaml
│   └── dev-cluster.yaml
├── scripts/                 # Management scripts
│   ├── create-cluster.sh
│   ├── delete-cluster.sh
│   └── run-docker.sh
├── Dockerfile              # Container with all tools
├── docker-compose.yml      # Container orchestration
├── Makefile               # Convenience commands
└── config.env             # Environment configuration
```

## 🔧 Usage

### Using Make Commands

```bash
# View all available commands
make help

# Build Docker image
make build

# Create clusters
make create-cluster ENVIRONMENT=production
make create-dev

# Delete clusters
make delete-cluster ENVIRONMENT=production
make delete-dev

# Access interactive shell
make shell ENVIRONMENT=production
make dev-shell

# Cluster management
make status
make nodes
make pods

# GitOps deployment (recommended)
make gitops-bootstrap-dev         # Development environment
make gitops-bootstrap-staging     # Staging environment
make gitops-bootstrap-prod        # Production environment

# Monitor GitOps
make gitops-status-dev           # Check dev applications
make gitops-status-staging       # Check staging applications
make gitops-status-prod          # Check production applications
make argocd-ui                   # Access ArgoCD dashboard

# Monitoring
make monitoring  # Access Grafana dashboard
```

### Using Docker Directly

```bash
# Build image
docker build -t eks-cluster-manager .

# Run interactive shell
./scripts/run-docker.sh --environment production bash

# Create cluster
./scripts/run-docker.sh --environment dev create-cluster

# Delete cluster
./scripts/run-docker.sh --environment dev delete-cluster
```

### Using Scripts Directly

```bash
# Create development cluster
./scripts/create-cluster.sh --environment dev

# Install add-ons using GitOps
make gitops-bootstrap-dev

# Delete cluster
./scripts/delete-cluster.sh --environment dev --cluster-name dev-eks
```

## 🌍 Environment Configurations

### Development
- Minimal resources for cost savings
- Single NAT Gateway
- Smaller instance types (t3.small)
- Reduced monitoring retention

### Production
- High availability with multiple AZs
- Highly available NAT Gateways
- Larger instances (t3.medium, t3.large)
- Comprehensive monitoring and logging
- Spot instances for cost optimization

## 📊 Monitoring

### Accessing Grafana Dashboard
```bash
# Port-forward to Grafana
make monitoring

# Access dashboard at http://localhost:3000
# Default credentials: admin/prom-operator
```

### Monitoring Stack Includes
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **CloudWatch**: AWS native monitoring
- **Container Insights**: Container-level metrics

## 🔐 Security Features

- **RBAC**: Role-based access control
- **OIDC**: OpenID Connect for service accounts
- **Secrets Encryption**: AWS KMS encryption at rest
- **Network Policies**: Pod-to-pod communication control
- **Security Groups**: Network-level security
- **IAM Roles**: Service-specific permissions

## 🔄 Autoscaling

### Cluster Autoscaler
- Automatically scales node groups based on demand
- Supports multiple node groups
- Cost-optimized with spot instances

### Horizontal Pod Autoscaler
- Scales pods based on CPU/memory metrics
- Custom metrics support

## 🔧 Add-on Management

All EKS add-ons are now managed through GitOps for consistency, reliability, and best practices. The GitOps approach provides:

- **Declarative configuration**: Define desired state in Git
- **Automatic synchronization**: Changes applied automatically
- **Environment consistency**: Same deployment method across dev/staging/production
- **Version control**: All changes tracked in Git
- **Easy rollbacks**: Git-based rollback capabilities

### Installing Add-ons

```bash
# Deploy to specific environments using GitOps
make gitops-bootstrap-dev         # Development environment
make gitops-bootstrap-staging     # Staging environment  
make gitops-bootstrap-prod        # Production environment

# Monitor deployment status
make gitops-status-dev           # Check dev status
make gitops-status-staging       # Check staging status
make gitops-status-prod          # Check production status
```

### Environment-Specific Configurations

- **Development**: Optimized for cost and speed (smaller resources, faster scaling)
- **Staging**: Production-like validation environment (moderate resources)
- **Production**: Full enterprise-grade configuration (high availability, full resources)

### Included Add-ons

All environments include the same core add-ons with environment-appropriate sizing:

- **AWS Load Balancer Controller** - ALB/NLB management
- **Cluster Autoscaler** - Node auto-scaling
- **Monitoring Stack** - Prometheus + Grafana
- **NGINX Ingress** - Ingress controller
- **External DNS** - Route53 DNS management
- **Cert Manager** - SSL/TLS certificates

## 🔄 GitOps with ArgoCD (Recommended for Production)

For production environments, we recommend using GitOps with ArgoCD instead of shell scripts. This provides:

- **Declarative management**: Define desired state in Git
- **Automatic synchronization**: Changes are automatically applied
- **Self-healing**: Automatically fixes configuration drift
- **Rollback capabilities**: Easy to revert to previous versions
- **Audit trail**: All changes tracked in Git history

### Quick Start with GitOps

```bash
# 1. Bootstrap ArgoCD and all applications
make gitops-bootstrap

# 2. Access ArgoCD UI
make argocd-password  # Get admin password
make argocd-ui       # Start port-forward to UI

# 3. Monitor applications
make gitops-status   # Check all applications
make argocd-apps     # List ArgoCD applications
```

### GitOps vs Shell Scripts

| Feature | Shell Scripts | GitOps with ArgoCD |
|---------|---------------|-------------------|
| **Deployment** | Imperative | Declarative |
| **State Management** | Manual | Automatic |
| **Rollback** | Manual | Git-based |
| **Audit Trail** | Limited | Complete |
| **Multi-Environment** | Script copies | Git branches |
| **Collaboration** | Complex | Git workflow |
| **Self-Healing** | None | Automatic |
| **UI/Dashboard** | None | Built-in |

### Migration Path

```bash
# Remove existing shell script installations (if any)
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall cluster-autoscaler -n kube-system

# Bootstrap GitOps
make gitops-bootstrap

# Monitor transition
make gitops-status
```

### GitOps Applications Included

- **AWS Load Balancer Controller** - ALB/NLB management
- **Cluster Autoscaler** - Node auto-scaling
- **Monitoring Stack** - Prometheus + Grafana
- **NGINX Ingress** - Ingress controller
- **External DNS** - Route53 DNS management
- **Cert Manager** - SSL/TLS certificates

For detailed GitOps documentation, see [`gitops/README.md`](gitops/README.md).

## 📚 Configuration

### Environment Variables
Copy `config.env` and customize:
```bash
# AWS Configuration
AWS_REGION=ap-southeast-2
CLUSTER_NAME=production-eks
ENVIRONMENT=production

# Node Configuration
APPLICATION_NODE_INSTANCE_TYPE=t3.large
APPLICATION_NODE_MIN_SIZE=2
APPLICATION_NODE_MAX_SIZE=10
```

### Cluster Configuration
Edit `cluster-config/production-cluster.yaml` for:
- Node group specifications
- VPC configuration
- Security settings
- Add-on configurations

## 🛠️ Troubleshooting

### Common Issues

1. **Docker not running**:
   ```bash
   # Start Docker Desktop or Docker daemon
   docker info
   ```

2. **AWS credentials not configured**:
   ```bash
   aws configure
   # Or set up credentials file
   ```

3. **Cluster creation fails**:
   ```bash
   # Check AWS permissions
   # Verify configuration file
   make validate-cluster
   ```

4. **kubectl connection issues**:
   ```bash
   # Update kubeconfig
   make update-kubeconfig
   ```

## 🚨 Important Notes

- **Cost**: EKS clusters incur charges (~$0.10/hour for control plane)
- **Cleanup**: Always delete clusters when not needed
- **Permissions**: Ensure your AWS user has sufficient EKS permissions
- **Regions**: Default is ap-southeast-2, adjust as needed

## 🔄 Cluster Update Strategies

### Update Commands

```bash
# Complete cluster update
make update-cluster                    # Update everything
make update-cluster-dry-run           # Preview changes

# Specific updates
make update-k8s-version VERSION=1.29  # Kubernetes version
make update-nodegroups                # Node groups (AMI, scaling)
make update-addons                    # EKS addons (VPC CNI, CoreDNS, etc.)

# Validation
make validate-pre-update              # Before updates
make validate-post-update             # After updates
make validate-health                  # Quick health check
```

### Safe Update Workflow

1. **Validate** → 2. **Update** → 3. **Validate** → 4. **Monitor**

```bash
# Example: Kubernetes version update
make validate-pre-update
make update-k8s-version VERSION=1.29
make validate-post-update
make gitops-status
```

### Environment Strategies

| Environment | Update Speed | Validation | Risk Tolerance |
|-------------|--------------|------------|----------------|
| **Dev** | Fast | Basic | High |
| **Staging** | Moderate | Comprehensive | Medium |
| **Production** | Conservative | Strict | Zero |

### Backup & Rollback

- **Automatic backups** created before updates in `backups/` directory
- **Rollback validation**: `./scripts/validate-cluster.sh --rollback --backup-dir <backup>`
- **Manual rollback** using backup files for complex scenarios

### Troubleshooting

```bash
# Check update status
eksctl get nodegroup --cluster=<cluster-name>
kubectl get nodes
kubectl get applications -n argocd

# Common fixes
kubectl describe pod <pod-name>     # Pod issues
aws eks describe-addon --cluster-name=<cluster> --addon-name=vpc-cni  # Addon issues
```

## 🔧 Customization

### Adding New Environments
1. Create new cluster config: `cluster-config/staging-cluster.yaml`
2. Add Makefile targets for staging environment
3. Update scripts to support new environment

### Custom Add-ons
1. Add new ArgoCD Application to `gitops/applications/`
2. Create environment-specific patches in `gitops/environments/*/patches/`
3. Update Helm values in Application manifests
4. Commit changes to Git for automatic deployment

## 📖 Additional Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [eksctl Documentation](https://eksctl.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Happy Kubernetes clustering! 🎉**
