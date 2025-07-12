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
- AWS Load Balancer Controller
- Cluster Autoscaler
- External DNS
- Cert Manager
- Monitoring Stack (Prometheus/Grafana)
- NGINX Ingress Controller

## 📁 Project Structure

```
eks-cloudformation/
├── cluster-config/           # EKS cluster configurations
│   ├── production-cluster.yaml
│   └── dev-cluster.yaml
├── scripts/                 # Management scripts
│   ├── create-cluster.sh
│   ├── delete-cluster.sh
│   ├── install-addons.sh
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
make install-addons

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

# Install add-ons
./scripts/install-addons.sh --cluster-name dev-eks

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

## 🔧 Customization

### Adding New Environments
1. Create new cluster config: `cluster-config/staging-cluster.yaml`
2. Add Makefile targets for staging environment
3. Update scripts to support new environment

### Custom Add-ons
1. Modify `scripts/install-addons.sh`
2. Add Helm charts or kubectl manifests
3. Update configuration files

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
