#!/bin/bash

# EKS Cluster Update Script
# Handles Kubernetes version updates, node group updates, EKS addons updates, and configuration changes
# Usage: ./update-cluster.sh [OPTIONS]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
CLUSTER_NAME=""
AWS_REGION="ap-southeast-2"
CONFIG_FILE=""
DRY_RUN="false"
FORCE_UPDATE="false"
UPDATE_TYPE="all"  # all, k8s-version, nodegroups, addons, config
TARGET_VERSION=""
BACKUP_ENABLED="true"
ROLLBACK_ENABLED="true"
VALIDATION_ENABLED="true"

# Update options
UPDATE_CONTROL_PLANE="true"
UPDATE_NODEGROUPS="true"
UPDATE_ADDONS="true"
UPDATE_CONFIG="false"

# Functions
usage() {
    echo "EKS Cluster Update Script"
    echo "========================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENVIRONMENT    Environment (dev, staging, production) [default: production]"
    echo "  -c, --cluster-name NAME          Cluster name [default: {environment}-eks]"
    echo "  -r, --region REGION              AWS region [default: ap-southeast-2]"
    echo "  -f, --config-file FILE           Cluster configuration file"
    echo "  -t, --update-type TYPE           Update type: all, k8s-version, nodegroups, addons, config [default: all]"
    echo "  -v, --target-version VERSION     Target Kubernetes version (e.g., 1.29)"
    echo "  -d, --dry-run                    Show what would be updated without making changes"
    echo "  -F, --force                      Force update without confirmation"
    echo "  --skip-backup                    Skip backup creation"
    echo "  --skip-validation                Skip pre and post-update validation"
    echo "  --skip-rollback                  Disable rollback capabilities"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo "Update Types:"
    echo "  all          - Update control plane, node groups, and addons"
    echo "  k8s-version  - Update Kubernetes version (control plane and nodes)"
    echo "  nodegroups   - Update node group configurations (AMI, instance types, scaling)"
    echo "  addons       - Update EKS addons (VPC CNI, CoreDNS, kube-proxy, EBS CSI)"
    echo "  config       - Update cluster configuration from file"
    echo ""
    echo "Examples:"
    echo "  $0 --environment dev --update-type k8s-version --target-version 1.29"
    echo "  $0 --environment production --update-type nodegroups --dry-run"
    echo "  $0 --environment staging --update-type addons"
    echo "  $0 --config-file cluster-config/production-cluster.yaml --update-type config"
    exit 1
}

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -f|--config-file)
            CONFIG_FILE="$2"
            UPDATE_CONFIG="true"
            shift 2
            ;;
        -t|--update-type)
            UPDATE_TYPE="$2"
            shift 2
            ;;
        -v|--target-version)
            TARGET_VERSION="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -F|--force)
            FORCE_UPDATE="true"
            shift
            ;;
        --skip-backup)
            BACKUP_ENABLED="false"
            shift
            ;;
        --skip-validation)
            VALIDATION_ENABLED="false"
            shift
            ;;
        --skip-rollback)
            ROLLBACK_ENABLED="false"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Set defaults
if [[ -z "$CLUSTER_NAME" ]]; then
    CLUSTER_NAME="${ENVIRONMENT}-eks"
fi

if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG_FILE="cluster-config/${ENVIRONMENT}-cluster.yaml"
fi

# Validate inputs
validate_inputs() {
    log "Validating inputs..."
    
    # Check if cluster config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Cluster configuration file not found: $CONFIG_FILE"
    fi
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
        error "Invalid environment: $ENVIRONMENT. Must be dev, staging, or production"
    fi
    
    # Validate update type
    if [[ ! "$UPDATE_TYPE" =~ ^(all|k8s-version|nodegroups|addons|config)$ ]]; then
        error "Invalid update type: $UPDATE_TYPE"
    fi
    
    # Validate target version format if provided
    if [[ -n "$TARGET_VERSION" && ! "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
        error "Invalid target version format: $TARGET_VERSION. Use format like 1.29"
    fi
    
    log "Input validation passed!"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        error "Invalid AWS credentials. Please configure AWS CLI"
    fi
    
    # Check required tools
    for tool in eksctl kubectl helm jq yq; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed"
        fi
    done
    
    # Check if cluster exists
    if ! eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" > /dev/null 2>&1; then
        error "Cluster $CLUSTER_NAME does not exist in region $AWS_REGION"
    fi
    
    # Update kubeconfig
    aws eks update-kubeconfig --name="$CLUSTER_NAME" --region="$AWS_REGION" --alias "$CLUSTER_NAME"
    
    # Check cluster connectivity
    if ! kubectl cluster-info > /dev/null 2>&1; then
        error "Cannot connect to cluster $CLUSTER_NAME"
    fi
    
    log "Prerequisites check passed!"
}

# Get current cluster information
get_cluster_info() {
    log "Getting current cluster information..."
    
    # Get current Kubernetes version
    CURRENT_K8S_VERSION=$(eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" -o json | jq -r '.[0].Version')
    
    # Get node groups
    NODE_GROUPS=$(eksctl get nodegroup --cluster="$CLUSTER_NAME" --region="$AWS_REGION" -o json | jq -r '.[].Name')
    
    # Get current addons
    CURRENT_ADDONS=$(aws eks describe-cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" --query 'cluster.addons' --output json)
    
    info "Current Kubernetes version: $CURRENT_K8S_VERSION"
    info "Node groups: $(echo $NODE_GROUPS | tr '\n' ' ')"
    info "Current addons: $(echo $CURRENT_ADDONS | jq -r '.[].name' | tr '\n' ' ')"
    
    # Set target version if not specified
    if [[ -z "$TARGET_VERSION" && "$UPDATE_TYPE" == "k8s-version" ]]; then
        # Get latest available version
        AVAILABLE_VERSIONS=$(aws eks describe-addon-versions --addon-name vpc-cni --query 'addons[0].clusterVersions[*].clusterVersion' --output json | jq -r '.[]' | sort -V)
        TARGET_VERSION=$(echo "$AVAILABLE_VERSIONS" | tail -1)
        info "Target version set to latest available: $TARGET_VERSION"
    fi
}

# Create backup
create_backup() {
    if [[ "$BACKUP_ENABLED" == "false" ]]; then
        log "Backup creation skipped"
        return 0
    fi
    
    log "Creating cluster backup..."
    
    local backup_dir="backups/${CLUSTER_NAME}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup cluster configuration
    eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" -o yaml > "$backup_dir/cluster-config.yaml"
    
    # Backup node group configurations
    eksctl get nodegroup --cluster="$CLUSTER_NAME" --region="$AWS_REGION" -o yaml > "$backup_dir/nodegroups.yaml"
    
    # Backup addons
    aws eks list-addons --cluster-name="$CLUSTER_NAME" --region="$AWS_REGION" > "$backup_dir/addons.json"
    
    # Backup important Kubernetes resources
    kubectl get nodes -o yaml > "$backup_dir/nodes.yaml"
    kubectl get configmaps -A -o yaml > "$backup_dir/configmaps.yaml"
    kubectl get secrets -A -o yaml > "$backup_dir/secrets.yaml"
    
    log "Backup created in: $backup_dir"
    echo "$backup_dir" > "/tmp/last-backup-${CLUSTER_NAME}"
}

# Pre-update validation
pre_update_validation() {
    if [[ "$VALIDATION_ENABLED" == "false" ]]; then
        log "Pre-update validation skipped"
        return 0
    fi
    
    log "Running pre-update validation..."
    
    # Check cluster health
    if ! kubectl get nodes | grep -q "Ready"; then
        error "Cluster has unhealthy nodes"
    fi
    
    # Check critical pods
    if kubectl get pods -A | grep -E "(crashloopbackoff|error|pending)" > /dev/null; then
        warn "Some pods are not in a healthy state"
        kubectl get pods -A | grep -E "(crashloopbackoff|error|pending)"
        
        if [[ "$FORCE_UPDATE" == "false" ]]; then
            error "Cluster has unhealthy pods. Use --force to proceed anyway"
        fi
    fi
    
    # Check node group health
    for ng in $NODE_GROUPS; do
        local ng_status=$(eksctl get nodegroup --cluster="$CLUSTER_NAME" --name="$ng" --region="$AWS_REGION" -o json | jq -r '.[0].Status')
        if [[ "$ng_status" != "ACTIVE" ]]; then
            error "Node group $ng is not in ACTIVE state: $ng_status"
        fi
    done
    
    log "Pre-update validation passed!"
}

# Update Kubernetes version
update_k8s_version() {
    if [[ "$UPDATE_TYPE" != "all" && "$UPDATE_TYPE" != "k8s-version" ]]; then
        return 0
    fi
    
    log "Updating Kubernetes version from $CURRENT_K8S_VERSION to $TARGET_VERSION..."
    
    if [[ "$CURRENT_K8S_VERSION" == "$TARGET_VERSION" ]]; then
        info "Cluster is already at target version $TARGET_VERSION"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would update control plane from $CURRENT_K8S_VERSION to $TARGET_VERSION"
        return 0
    fi
    
    # Update control plane
    log "Updating control plane to $TARGET_VERSION..."
    aws eks update-cluster-version --name="$CLUSTER_NAME" --kubernetes-version="$TARGET_VERSION" --region="$AWS_REGION"
    
    # Wait for control plane update to complete
    log "Waiting for control plane update to complete..."
    while true; do
        local status=$(aws eks describe-cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" --query 'cluster.status' --output text)
        if [[ "$status" == "ACTIVE" ]]; then
            break
        fi
        log "Control plane status: $status. Waiting..."
        sleep 60
    done
    
    # Update node groups
    log "Updating node groups to $TARGET_VERSION..."
    for ng in $NODE_GROUPS; do
        log "Updating node group: $ng"
        eksctl upgrade nodegroup --cluster="$CLUSTER_NAME" --name="$ng" --region="$AWS_REGION" --kubernetes-version="$TARGET_VERSION"
    done
    
    log "Kubernetes version update completed!"
}

# Update node groups
update_nodegroups() {
    if [[ "$UPDATE_TYPE" != "all" && "$UPDATE_TYPE" != "nodegroups" ]]; then
        return 0
    fi
    
    log "Updating node groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would update node groups with latest AMI"
        return 0
    fi
    
    # Update each node group with latest AMI
    for ng in $NODE_GROUPS; do
        log "Updating node group $ng with latest AMI..."
        
        # Get current node group info
        local ng_info=$(eksctl get nodegroup --cluster="$CLUSTER_NAME" --name="$ng" --region="$AWS_REGION" -o json)
        local instance_type=$(echo "$ng_info" | jq -r '.[0].InstanceType')
        local min_size=$(echo "$ng_info" | jq -r '.[0].MinSize')
        local max_size=$(echo "$ng_info" | jq -r '.[0].MaxSize')
        local desired_size=$(echo "$ng_info" | jq -r '.[0].DesiredCapacity')
        
        info "Node group $ng: $instance_type, min=$min_size, max=$max_size, desired=$desired_size"
        
        # Update node group
        eksctl upgrade nodegroup --cluster="$CLUSTER_NAME" --name="$ng" --region="$AWS_REGION"
        
        # Wait for update to complete
        log "Waiting for node group $ng update to complete..."
        while true; do
            local status=$(eksctl get nodegroup --cluster="$CLUSTER_NAME" --name="$ng" --region="$AWS_REGION" -o json | jq -r '.[0].Status')
            if [[ "$status" == "ACTIVE" ]]; then
                break
            fi
            log "Node group $ng status: $status. Waiting..."
            sleep 30
        done
        
        log "Node group $ng update completed!"
    done
    
    log "Node groups update completed!"
}

# Update EKS addons
update_addons() {
    if [[ "$UPDATE_TYPE" != "all" && "$UPDATE_TYPE" != "addons" ]]; then
        return 0
    fi
    
    log "Updating EKS addons..."
    
    local addons=("vpc-cni" "coredns" "kube-proxy" "aws-ebs-csi-driver")
    
    for addon in "${addons[@]}"; do
        log "Checking addon: $addon"
        
        # Check if addon is installed
        if ! aws eks describe-addon --cluster-name="$CLUSTER_NAME" --addon-name="$addon" --region="$AWS_REGION" > /dev/null 2>&1; then
            info "Addon $addon is not installed, skipping..."
            continue
        fi
        
        # Get current version
        local current_version=$(aws eks describe-addon --cluster-name="$CLUSTER_NAME" --addon-name="$addon" --region="$AWS_REGION" --query 'addon.addonVersion' --output text)
        
        # Get latest version
        local latest_version=$(aws eks describe-addon-versions --addon-name="$addon" --kubernetes-version="$TARGET_VERSION" --query 'addons[0].addonVersions[0].addonVersion' --output text)
        
        info "Addon $addon: current=$current_version, latest=$latest_version"
        
        if [[ "$current_version" == "$latest_version" ]]; then
            info "Addon $addon is already at latest version"
            continue
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would update addon $addon from $current_version to $latest_version"
            continue
        fi
        
        # Update addon
        log "Updating addon $addon to $latest_version..."
        aws eks update-addon --cluster-name="$CLUSTER_NAME" --addon-name="$addon" --addon-version="$latest_version" --region="$AWS_REGION" --resolve-conflicts OVERWRITE
        
        # Wait for update to complete
        log "Waiting for addon $addon update to complete..."
        while true; do
            local status=$(aws eks describe-addon --cluster-name="$CLUSTER_NAME" --addon-name="$addon" --region="$AWS_REGION" --query 'addon.status' --output text)
            if [[ "$status" == "ACTIVE" ]]; then
                break
            fi
            log "Addon $addon status: $status. Waiting..."
            sleep 30
        done
        
        log "Addon $addon update completed!"
    done
    
    log "EKS addons update completed!"
}

# Update cluster configuration
update_cluster_config() {
    if [[ "$UPDATE_TYPE" != "config" ]]; then
        return 0
    fi
    
    log "Updating cluster configuration from $CONFIG_FILE..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would update cluster configuration"
        eksctl create cluster --config-file="$CONFIG_FILE" --dry-run
        return 0
    fi
    
    # This is a complex operation that might require recreating resources
    warn "Configuration updates may require recreating resources"
    warn "This operation should be used with caution in production"
    
    if [[ "$FORCE_UPDATE" == "false" ]]; then
        read -p "Are you sure you want to proceed with configuration update? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Configuration update cancelled"
            return 0
        fi
    fi
    
    # Apply configuration changes
    log "Applying configuration changes..."
    # Note: This is a simplified approach. In practice, you'd need to analyze
    # the differences and apply specific updates
    warn "Configuration updates are not yet fully implemented"
    warn "Please use eksctl and kubectl commands manually for complex configuration changes"
}

# Post-update validation
post_update_validation() {
    if [[ "$VALIDATION_ENABLED" == "false" ]]; then
        log "Post-update validation skipped"
        return 0
    fi
    
    log "Running post-update validation..."
    
    # Wait for cluster to stabilize
    log "Waiting for cluster to stabilize..."
    sleep 60
    
    # Check cluster health
    if ! kubectl get nodes | grep -q "Ready"; then
        error "Cluster has unhealthy nodes after update"
    fi
    
    # Check all nodes are ready
    local not_ready_nodes=$(kubectl get nodes | grep -v "Ready" | grep -v "NAME" | wc -l)
    if [[ "$not_ready_nodes" -gt 0 ]]; then
        error "Some nodes are not ready after update"
    fi
    
    # Check critical system pods
    log "Checking critical system pods..."
    local critical_namespaces=("kube-system" "argocd")
    for ns in "${critical_namespaces[@]}"; do
        if kubectl get ns "$ns" > /dev/null 2>&1; then
            local not_ready_pods=$(kubectl get pods -n "$ns" | grep -v "Running\|Completed" | grep -v "NAME" | wc -l)
            if [[ "$not_ready_pods" -gt 0 ]]; then
                warn "Some pods in namespace $ns are not ready"
                kubectl get pods -n "$ns" | grep -v "Running\|Completed"
            fi
        fi
    done
    
    # Test basic functionality
    log "Testing basic cluster functionality..."
    
    # Create a test pod
    kubectl run test-pod --image=alpine --command -- sleep 3600 > /dev/null
    
    # Wait for pod to be ready
    kubectl wait --for=condition=ready pod/test-pod --timeout=300s
    
    # Test pod functionality
    kubectl exec test-pod -- echo "Cluster is functional"
    
    # Clean up test pod
    kubectl delete pod test-pod
    
    log "Post-update validation passed!"
}

# Show update summary
show_update_summary() {
    log "Update Summary"
    log "=============="
    log "Cluster: $CLUSTER_NAME"
    log "Environment: $ENVIRONMENT"
    log "Region: $AWS_REGION"
    log "Update Type: $UPDATE_TYPE"
    
    if [[ "$UPDATE_TYPE" == "all" || "$UPDATE_TYPE" == "k8s-version" ]]; then
        log "Kubernetes Version: $CURRENT_K8S_VERSION → $TARGET_VERSION"
    fi
    
    log "Node Groups Updated: $(echo $NODE_GROUPS | tr '\n' ' ')"
    
    # Get updated cluster info
    local new_k8s_version=$(eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" -o json | jq -r '.[0].Version')
    log "Current Kubernetes Version: $new_k8s_version"
    
    # Show node status
    log "Node Status:"
    kubectl get nodes -o wide
    
    # Show addon status
    log "Addon Status:"
    aws eks list-addons --cluster-name="$CLUSTER_NAME" --region="$AWS_REGION" --output table
    
    log "Update completed successfully!"
}

# Rollback function
rollback_cluster() {
    if [[ "$ROLLBACK_ENABLED" == "false" ]]; then
        error "Rollback is disabled"
    fi
    
    local backup_dir
    if [[ -f "/tmp/last-backup-${CLUSTER_NAME}" ]]; then
        backup_dir=$(cat "/tmp/last-backup-${CLUSTER_NAME}")
    else
        error "No backup found for rollback"
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        error "Backup directory not found: $backup_dir"
    fi
    
    warn "Rolling back cluster to previous state..."
    warn "This operation is complex and may require manual intervention"
    
    # This is a simplified rollback - in practice, you'd need to:
    # 1. Restore cluster configuration
    # 2. Downgrade Kubernetes version (if supported)
    # 3. Restore node groups
    # 4. Restore addons
    
    error "Rollback functionality is not yet fully implemented"
    error "Please use the backup in $backup_dir to manually restore the cluster"
}

# Main execution
main() {
    log "EKS Cluster Update Script"
    log "========================="
    log "Environment: $ENVIRONMENT"
    log "Cluster: $CLUSTER_NAME"
    log "Region: $AWS_REGION"
    log "Update Type: $UPDATE_TYPE"
    log "Dry Run: $DRY_RUN"
    
    # Validate inputs
    validate_inputs
    
    # Check prerequisites
    check_prerequisites
    
    # Get current cluster information
    get_cluster_info
    
    # Create backup
    create_backup
    
    # Pre-update validation
    pre_update_validation
    
    # Confirmation (unless force or dry-run)
    if [[ "$DRY_RUN" == "false" && "$FORCE_UPDATE" == "false" ]]; then
        echo ""
        warn "This will update the cluster $CLUSTER_NAME"
        warn "Update type: $UPDATE_TYPE"
        if [[ -n "$TARGET_VERSION" ]]; then
            warn "Target version: $TARGET_VERSION"
        fi
        warn "This operation may cause downtime"
        echo ""
        read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Update cancelled"
            exit 0
        fi
    fi
    
    # Perform updates
    case "$UPDATE_TYPE" in
        "all")
            update_k8s_version
            update_nodegroups
            update_addons
            ;;
        "k8s-version")
            update_k8s_version
            ;;
        "nodegroups")
            update_nodegroups
            ;;
        "addons")
            update_addons
            ;;
        "config")
            update_cluster_config
            ;;
    esac
    
    # Post-update validation
    post_update_validation
    
    # Show summary
    show_update_summary
    
    log "Cluster update completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Backup created in: $(cat /tmp/last-backup-${CLUSTER_NAME} 2>/dev/null || echo 'N/A')"
        info "Monitor your applications and use 'make gitops-status' to check ArgoCD applications"
    fi
}

# Trap errors for potential rollback
trap 'error "Update failed! Check the logs above for details."' ERR

# Run main function
main "$@" 