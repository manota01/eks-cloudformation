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
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -e, --environment ENV     Environment (dev, staging, production) [default: production]"
    echo "  -n, --cluster-name NAME  Cluster name [required]"
    echo "  -r, --region REGION      AWS region [default: ap-southeast-2]"
    echo "  -f, --force              Force delete without additional checks"
    echo "  -y, --yes                Skip confirmation prompts"
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
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
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

# Check if cluster exists
echo -e "${YELLOW}Checking if cluster $CLUSTER_NAME exists...${NC}"
if ! eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cluster $CLUSTER_NAME does not exist${NC}"
    exit 1
fi

# Show cluster info
echo -e "${YELLOW}Cluster Information:${NC}"
eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION"
echo ""

# Check for running workloads
if [[ "$FORCE_DELETE" == "false" ]]; then
    echo -e "${YELLOW}Checking for running workloads...${NC}"
    
    # Update kubeconfig
    aws eks update-kubeconfig --name="$CLUSTER_NAME" --region="$AWS_REGION" --alias "$CLUSTER_NAME"
    
    # List all pods
    echo -e "${YELLOW}Running pods:${NC}"
    kubectl get pods --all-namespaces --field-selector=status.phase=Running
    
    # List all services
    echo -e "${YELLOW}Active services:${NC}"
    kubectl get svc --all-namespaces --field-selector=spec.type=LoadBalancer
    
    # List all ingress
    echo -e "${YELLOW}Active ingress:${NC}"
    kubectl get ingress --all-namespaces
fi

# Confirmation
if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
    echo ""
    echo -e "${RED}WARNING: This will permanently delete the cluster $CLUSTER_NAME and all associated resources!${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to delete the cluster? Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        echo -e "${YELLOW}Cluster deletion cancelled${NC}"
        exit 0
    fi
fi

# Delete Load Balancers first (to avoid VPC deletion issues)
echo -e "${YELLOW}Cleaning up Load Balancers...${NC}"
kubectl delete svc --all-namespaces --field-selector=spec.type=LoadBalancer --ignore-not-found=true

# Delete Ingress resources
echo -e "${YELLOW}Cleaning up Ingress resources...${NC}"
kubectl delete ingress --all-namespaces --all --ignore-not-found=true

# Wait for cleanup
echo -e "${YELLOW}Waiting for AWS resources to be cleaned up...${NC}"
sleep 30

# Delete the cluster
echo -e "${GREEN}Deleting EKS cluster: $CLUSTER_NAME${NC}"
eksctl delete cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" --wait

# Clean up kubeconfig
echo -e "${YELLOW}Cleaning up kubeconfig...${NC}"
kubectl config delete-context "$CLUSTER_NAME" 2>/dev/null || true
kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true

# Verify deletion
echo -e "${YELLOW}Verifying cluster deletion...${NC}"
if eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" 2>/dev/null; then
    echo -e "${RED}Warning: Cluster may still exist. Please check manually.${NC}"
else
    echo -e "${GREEN}Cluster $CLUSTER_NAME deleted successfully!${NC}"
fi

echo ""
echo "Cleanup completed!"
echo "Note: Some AWS resources (like security groups) may take additional time to be deleted." 