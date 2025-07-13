#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
CONFIG_FILE=""
CLUSTER_NAME=""
AWS_REGION="ap-southeast-2"
DRY_RUN=false

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -e, --environment ENV     Environment (dev, staging, production) [default: production]"
    echo "  -c, --config FILE        Custom config file path"
    echo "  -n, --cluster-name NAME  Cluster name override"
    echo "  -r, --region REGION      AWS region [default: ap-southeast-2]"
    echo "  -d, --dry-run            Perform a dry run"
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
        -c|--config)
            CONFIG_FILE="$2"
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
        -d|--dry-run)
            DRY_RUN=true
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

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment. Must be one of: dev, staging, production${NC}"
    exit 1
fi

# Set config file if not provided
if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG_FILE="cluster-config/${ENVIRONMENT}-cluster.yaml"
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Validate AWS credentials
echo -e "${YELLOW}Validating AWS credentials...${NC}"
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}Error: Invalid AWS credentials. Please configure AWS CLI.${NC}"
    exit 1
fi

# Validate required tools
echo -e "${YELLOW}Checking required tools...${NC}"
for tool in eksctl kubectl helm; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${RED}Error: $tool is not installed${NC}"
        exit 1
    fi
done

# Dry run
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}Performing dry run...${NC}"
    eksctl create cluster --config-file="$CONFIG_FILE" --dry-run
    exit 0
fi

# Extract cluster name from config if not provided
if [[ -z "$CLUSTER_NAME" ]]; then
    CLUSTER_NAME=$(yq eval '.metadata.name' "$CONFIG_FILE")
fi

# Check if cluster already exists
echo -e "${YELLOW}Checking if cluster $CLUSTER_NAME already exists...${NC}"
if eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cluster $CLUSTER_NAME already exists${NC}"
    exit 1
fi

# Create cluster
echo -e "${GREEN}Creating EKS cluster: $CLUSTER_NAME${NC}"
echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}Config file: $CONFIG_FILE${NC}"
echo -e "${YELLOW}Region: $AWS_REGION${NC}"
echo ""

# Ask for confirmation
read -p "Do you want to proceed with cluster creation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cluster creation cancelled${NC}"
    exit 0
fi

# Create the cluster
echo -e "${GREEN}Starting cluster creation...${NC}"
eksctl create cluster --config-file="$CONFIG_FILE" --verbose=2

# Verify cluster creation
echo -e "${YELLOW}Verifying cluster creation...${NC}"
kubectl get nodes

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --name="$CLUSTER_NAME" --region="$AWS_REGION"

# Install essential add-ons
echo -e "${GREEN}Installing essential add-ons...${NC}"
bash scripts/install-addons.sh --environment="$ENVIRONMENT" --cluster-name="$CLUSTER_NAME"

echo -e "${GREEN}Cluster $CLUSTER_NAME created successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Verify cluster: kubectl get nodes"
echo "2. Deploy applications: kubectl apply -f your-app.yaml"
echo "3. Monitor cluster: kubectl get pods --all-namespaces" 