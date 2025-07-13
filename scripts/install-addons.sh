#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
CLUSTER_NAME=""
AWS_REGION="ap-southeast-2"
EMAIL=""
DOMAIN=""
INSTALL_ALL=true
INSTALL_ALB=false
INSTALL_AUTOSCALER=false
INSTALL_MONITORING=false
INSTALL_INGRESS=false
INSTALL_EXTERNAL_DNS=false
INSTALL_CERT_MANAGER=false

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -e, --environment ENV     Environment (dev, staging, production) [default: production]"
    echo "  -n, --cluster-name NAME  Cluster name [required]"
    echo "  -r, --region REGION      AWS region [default: ap-southeast-2]"
    echo "  --email EMAIL            Email for Let's Encrypt certificates [required for cert-manager]"
    echo "  --domain DOMAIN          Domain for External DNS [required for external-dns]"
    echo "  --alb                    Install AWS Load Balancer Controller only"
    echo "  --autoscaler             Install Cluster Autoscaler only"
    echo "  --monitoring             Install monitoring stack only"
    echo "  --ingress                Install NGINX Ingress Controller only"
    echo "  --external-dns           Install External DNS only"
    echo "  --cert-manager           Install Cert Manager only"
    echo "  -h, --help               Show this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -n|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --alb)
            INSTALL_ALL=false
            INSTALL_ALB=true
            shift
            ;;
        --autoscaler)
            INSTALL_ALL=false
            INSTALL_AUTOSCALER=true
            shift
            ;;
        --monitoring)
            INSTALL_ALL=false
            INSTALL_MONITORING=true
            shift
            ;;
        --ingress)
            INSTALL_ALL=false
            INSTALL_INGRESS=true
            shift
            ;;
        --external-dns)
            INSTALL_ALL=false
            INSTALL_EXTERNAL_DNS=true
            shift
            ;;
        --cert-manager)
            INSTALL_ALL=false
            INSTALL_CERT_MANAGER=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CLUSTER_NAME" ]]; then
    echo -e "${RED}Error: Cluster name is required${NC}"
    exit 1
fi

# Get the directory of the current script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ADDONS_DIR="$SCRIPT_DIR/../addons"

# Install AWS Load Balancer Controller
install_alb_controller() {
    echo -e "${GREEN}Installing AWS Load Balancer Controller...${NC}"
    bash "$ADDONS_DIR/aws-load-balancer-controller/install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION"
}

# Install Cluster Autoscaler
install_cluster_autoscaler() {
    echo -e "${GREEN}Installing Cluster Autoscaler...${NC}"
    bash "$ADDONS_DIR/cluster-autoscaler/install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION"
}

# Install monitoring stack
install_monitoring() {
    echo -e "${GREEN}Installing monitoring stack (Prometheus & Grafana)...${NC}"
    bash "$ADDONS_DIR/monitoring/install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION"
}

# Install NGINX Ingress Controller
install_ingress() {
    echo -e "${GREEN}Installing NGINX Ingress Controller...${NC}"
    bash "$ADDONS_DIR/ingress-nginx/install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION"
}

# Install External DNS
install_external_dns() {
    if [[ -z "$DOMAIN" ]]; then
        echo -e "${RED}Error: Domain is required for External DNS installation${NC}"
        echo "Use --domain parameter to specify the domain"
        exit 1
    fi
    
    echo -e "${GREEN}Installing External DNS...${NC}"
    bash "$ADDONS_DIR/external-dns/install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --domain-filter "$DOMAIN"
}

# Install Cert Manager
install_cert_manager() {
    if [[ -z "$EMAIL" ]]; then
        echo -e "${RED}Error: Email is required for Cert Manager installation${NC}"
        echo "Use --email parameter to specify the email for Let's Encrypt"
        exit 1
    fi
    
    echo -e "${GREEN}Installing Cert Manager...${NC}"
    bash "$ADDONS_DIR/cert-manager/install.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --email "$EMAIL"
}

# Main installation logic
if [[ "$INSTALL_ALL" == "true" ]]; then
    install_alb_controller
    install_cluster_autoscaler
    install_monitoring
    install_ingress
    
    if [[ -n "$DOMAIN" ]]; then
        install_external_dns
    else
        echo -e "${YELLOW}Skipping External DNS - domain not specified${NC}"
    fi
    
    if [[ -n "$EMAIL" ]]; then
        install_cert_manager
    else
        echo -e "${YELLOW}Skipping Cert Manager - email not specified${NC}"
    fi
else
    if [[ "$INSTALL_ALB" == "true" ]]; then
        install_alb_controller
    fi
    if [[ "$INSTALL_AUTOSCALER" == "true" ]]; then
        install_cluster_autoscaler
    fi
    if [[ "$INSTALL_MONITORING" == "true" ]]; then
        install_monitoring
    fi
    if [[ "$INSTALL_INGRESS" == "true" ]]; then
        install_ingress
    fi
    if [[ "$INSTALL_EXTERNAL_DNS" == "true" ]]; then
        install_external_dns
    fi
    if [[ "$INSTALL_CERT_MANAGER" == "true" ]]; then
        install_cert_manager
    fi
fi

echo -e "${GREEN}Add-ons installation completed!${NC}"
echo ""
echo "Verification commands:"
echo "1. Check pods: kubectl get pods -A"
echo "2. Check services: kubectl get svc -A"
echo "3. Check ingress: kubectl get ingress -A"
echo "4. Check certificates: kubectl get certificates -A"
echo "5. Check cluster issuers: kubectl get clusterissuers"
echo "6. Grafana dashboard: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80" 