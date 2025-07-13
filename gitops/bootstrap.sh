#!/bin/bash

# ArgoCD Bootstrap Script
# This script sets up ArgoCD and deploys the initial applications using GitOps

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ARGOCD_NAMESPACE="argocd"
REPO_URL="https://github.com/manota01/eks-cloudformation.git"  # Update with your repo
ENVIRONMENT="production"  # Default environment
CLUSTER_NAME="${ENVIRONMENT}-cluster"  # Will be updated based on environment
REGION="ap-southeast-2"
DOMAIN="example.com"  # Update with your domain
EMAIL="admin@example.com"  # Update with your email

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install kubectl first."
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    fi
    
    # Check if cluster is EKS
    if ! kubectl get nodes -o wide | grep -q "eks"; then
        warn "This script is designed for EKS clusters. Some features may not work correctly."
    fi
    
    log "Prerequisites check passed!"
}

install_argocd() {
    log "Installing ArgoCD..."
    
    # Create namespace
    kubectl apply -f gitops/argocd/namespace.yaml
    
    # Install ArgoCD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    log "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-application-controller -n argocd
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
    
    # Apply custom configuration
    kubectl apply -f gitops/argocd/install.yaml
    
    log "ArgoCD installed successfully!"
}

setup_applications() {
    log "Setting up ArgoCD applications for ${ENVIRONMENT} environment..."
    
    # Determine which bootstrap application to use
    local bootstrap_app=""
    case "${ENVIRONMENT}" in
        "dev")
            bootstrap_app="environments/dev/bootstrap-dev.yaml"
            ;;
        "staging")
            bootstrap_app="environments/staging/bootstrap-staging.yaml"
            ;;
        "production")
            bootstrap_app="environments/production/bootstrap-production.yaml"
            ;;
        *)
            # Fall back to original bootstrap for backward compatibility
            bootstrap_app="argocd/bootstrap-app.yaml"
            ;;
    esac
    
    # Update bootstrap application with correct repo URL
    sed -i.bak "s|repoURL: https://github.com/manota01/eks-cloudformation.git|repoURL: ${REPO_URL}|g" "${bootstrap_app}"
    
    # Apply bootstrap application
    kubectl apply -f "${bootstrap_app}"
    
    log "Bootstrap application for ${ENVIRONMENT} environment created!"
    log "ArgoCD will now automatically deploy all applications from the Git repository."
}

get_argocd_password() {
    log "Getting ArgoCD admin password..."
    
    # Wait for secret to be created
    kubectl wait --for=condition=ready --timeout=300s secret/argocd-initial-admin-secret -n argocd
    
    # Get password
    local password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    info "ArgoCD admin password: ${password}"
    info "Save this password - you'll need it to access the ArgoCD UI"
}

setup_port_forward() {
    log "Setting up port forwarding to ArgoCD..."
    
    info "Run the following command to access ArgoCD UI:"
    info "kubectl port-forward svc/argocd-server -n argocd 8080:443"
    info "Then open: https://localhost:8080"
    info "Username: admin"
    
    # Start port forward in background
    if [[ "${1:-}" == "--port-forward" ]]; then
        log "Starting port forward in background..."
        kubectl port-forward svc/argocd-server -n argocd 8080:443 &
        local port_forward_pid=$!
        info "Port forward started with PID: ${port_forward_pid}"
        info "ArgoCD UI available at: https://localhost:8080"
    fi
}

update_application_configs() {
    log "Updating application configurations for ${ENVIRONMENT} environment..."
    
    # Update cluster name in applications
    find gitops/applications -name "*.yaml" -exec sed -i.bak "s/production-cluster/${CLUSTER_NAME}/g" {} \;
    
    # Update cluster name in environment-specific patches
    find gitops/environments -name "*.yaml" -exec sed -i.bak "s/production-cluster/${CLUSTER_NAME}/g" {} \;
    find gitops/environments -name "*.yaml" -exec sed -i.bak "s/dev-cluster/${CLUSTER_NAME}/g" {} \;
    find gitops/environments -name "*.yaml" -exec sed -i.bak "s/staging-cluster/${CLUSTER_NAME}/g" {} \;
    
    # Update region
    find gitops/applications -name "*.yaml" -exec sed -i.bak "s/ap-southeast-2/${REGION}/g" {} \;
    find gitops/environments -name "*.yaml" -exec sed -i.bak "s/ap-southeast-2/${REGION}/g" {} \;
    
    # Update domain
    find gitops/applications -name "*.yaml" -exec sed -i.bak "s/example.com/${DOMAIN}/g" {} \;
    find gitops/environments -name "*.yaml" -exec sed -i.bak "s/example.com/${DOMAIN}/g" {} \;
    
    # Update repository URL in bootstrap applications
    find gitops/environments -name "bootstrap-*.yaml" -exec sed -i.bak "s|repoURL: https://github.com/manota01/eks-cloudformation.git|repoURL: ${REPO_URL}|g" {} \;
    
    # Clean up backup files
    find gitops -name "*.bak" -delete
    
    log "Application configurations updated for ${ENVIRONMENT} environment!"
}

show_status() {
    log "Checking application status..."
    
    # Wait a bit for applications to be created
    sleep 30
    
    # Show ArgoCD applications
    kubectl get applications -n argocd
    
    info "Monitor applications with:"
    info "kubectl get applications -n argocd -w"
    info "kubectl get pods -A | grep -E '(argocd|kube-system|monitoring|ingress-nginx|external-dns|cert-manager)'"
}

create_sample_issuer() {
    log "Creating sample cert-manager ClusterIssuer..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        route53:
          region: ${REGION}
      selector:
        dnsZones:
        - "${DOMAIN}"
EOF
    
    info "ClusterIssuer created. Update the email and domain as needed."
}

main() {
    info "Starting ArgoCD GitOps Bootstrap"
    info "Environment: ${ENVIRONMENT}"
    info "Cluster: ${CLUSTER_NAME}"
    info "Region: ${REGION}"
    info "Domain: ${DOMAIN}"
    info "Repository: ${REPO_URL}"
    
    check_prerequisites
    
    # Handle --update-configs flag
    local update_configs=false
    local create_issuer=false
    local port_forward=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                ENVIRONMENT="$2"
                CLUSTER_NAME="${ENVIRONMENT}-cluster"
                shift 2
                ;;
            --update-configs)
                update_configs=true
                shift
                ;;
            --create-issuer)
                create_issuer=true
                shift
                ;;
            --port-forward)
                port_forward=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ "${update_configs}" == "true" ]]; then
        update_application_configs
        exit 0
    fi
    
    install_argocd
    setup_applications
    get_argocd_password
    
    if [[ "${port_forward}" == "true" ]]; then
        setup_port_forward --port-forward
    else
        setup_port_forward
    fi
    
    # Wait for cert-manager to be ready before creating issuer
    if [[ "${create_issuer}" == "true" ]]; then
        log "Waiting for cert-manager to be ready..."
        kubectl wait --for=condition=available --timeout=600s deployment/cert-manager -n cert-manager
        create_sample_issuer
    fi
    
    show_status
    
    log "GitOps bootstrap completed for ${ENVIRONMENT} environment!"
    info "Next steps:"
    info "1. Access ArgoCD UI at https://localhost:8080 (if port-forward is running)"
    info "2. Monitor applications: kubectl get applications -n argocd -w"
    info "3. Check pod status: kubectl get pods -A"
    info "4. Update IAM roles for service accounts (see documentation)"
    info "5. Configure DNS and certificates for your domain"
}

# Help function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --environment ENV Environment to deploy (dev, staging, production)"
    echo "  --port-forward    Start port forward to ArgoCD UI"
    echo "  --create-issuer   Create sample cert-manager ClusterIssuer"
    echo "  --update-configs  Update application configurations with current values"
    echo "  --help           Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  ENVIRONMENT   Environment name (default: production)"
    echo "  CLUSTER_NAME  Name of the EKS cluster (default: {ENVIRONMENT}-cluster)"
    echo "  REGION        AWS region (default: ap-southeast-2)"
    echo "  DOMAIN        Your domain name (default: example.com)"
    echo "  EMAIL         Email for cert-manager (default: admin@example.com)"
    echo "  REPO_URL      Git repository URL (default: https://github.com/manota01/eks-cloudformation.git)"
    echo ""
    echo "Examples:"
    echo "  $0 --environment dev --port-forward"
    echo "  $0 --environment staging --create-issuer"
    echo "  $0 --environment production"
}

# Parse command line arguments
case "${1:-}" in
    --help)
        usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac 