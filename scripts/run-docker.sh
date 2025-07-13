#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
COMMAND=""
ENVIRONMENT="production"
BUILD_IMAGE=false
INTERACTIVE=true

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Run EKS management tools in Docker container"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV     Environment (dev, staging, production) [default: production]"
    echo "  -b, --build               Build the Docker image before running"
    echo "  -n, --non-interactive     Run in non-interactive mode"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Commands:"
    echo "  bash                      Start interactive bash shell (default)"
    echo "  create-cluster            Create EKS cluster"
    echo "  delete-cluster            Delete EKS cluster"
    echo ""
    echo "  scale-cluster             Scale cluster nodes"
    echo "  <custom-command>          Run custom command in container"
    echo ""
    echo "Examples:"
    echo "  $0                        # Start interactive shell"
    echo "  $0 --build bash           # Build image and start shell"
    echo "  $0 create-cluster -e dev  # Create development cluster"
    echo "  $0 \"kubectl get nodes\"    # Run kubectl command"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -b|--build)
            BUILD_IMAGE=true
            shift
            ;;
        -n|--non-interactive)
            INTERACTIVE=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            COMMAND="$1"
            shift
            break
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment. Must be one of: dev, staging, production${NC}"
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker.${NC}"
    exit 1
fi

# Check if AWS credentials exist
if [[ ! -d "$HOME/.aws" ]]; then
    echo -e "${RED}Error: AWS credentials not found. Please configure AWS CLI first.${NC}"
    echo "Run: aws configure"
    exit 1
fi

# Create .kube directory if it doesn't exist
mkdir -p "$HOME/.kube"

# Build image if requested
if [[ "$BUILD_IMAGE" == "true" ]]; then
    echo -e "${YELLOW}Building Docker image...${NC}"
    docker build -t eks-cluster-manager .
fi

# Set Docker run options
DOCKER_OPTS=""
if [[ "$INTERACTIVE" == "true" ]]; then
    DOCKER_OPTS="-it"
fi

# Determine command to run
if [[ -z "$COMMAND" ]]; then
    COMMAND="bash"
fi

# Handle special commands
case "$COMMAND" in
    "create-cluster")
        COMMAND="bash scripts/create-cluster.sh --environment $ENVIRONMENT"
        ;;
    "delete-cluster")
        COMMAND="bash scripts/delete-cluster.sh --environment $ENVIRONMENT"
        ;;

    "scale-cluster")
        COMMAND="bash scripts/scale-cluster.sh --environment $ENVIRONMENT"
        ;;
esac

# Run the container
echo -e "${GREEN}Starting EKS management container...${NC}"
echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}Command: $COMMAND${NC}"
echo ""

# Export environment variables
export AWS_REGION="${AWS_REGION:-ap-southeast-2}"
export CLUSTER_NAME="${CLUSTER_NAME:-${ENVIRONMENT}-eks}"
export AWS_PROFILE="${AWS_PROFILE:-default}"

# Run Docker container
docker run --rm $DOCKER_OPTS \
    --name eks-cluster-manager \
    -v "$HOME/.aws:/root/.aws:ro" \
    -v "$HOME/.kube:/root/.kube" \
    -v "$(pwd):/eks-cluster" \
    -v "/var/run/docker.sock:/var/run/docker.sock" \
    -e AWS_REGION="$AWS_REGION" \
    -e CLUSTER_NAME="$CLUSTER_NAME" \
    -e AWS_PROFILE="$AWS_PROFILE" \
    -e ENVIRONMENT="$ENVIRONMENT" \
    -w /eks-cluster \
    eks-cluster-manager \
    $COMMAND 