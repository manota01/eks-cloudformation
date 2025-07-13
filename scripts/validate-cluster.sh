#!/bin/bash

# EKS Cluster Validation Script
# Validates cluster health, readiness for updates, and post-update validation
# Can also be used for rollback procedures
# Usage: ./validate-cluster.sh [OPTIONS]

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
VALIDATION_TYPE="all"  # all, pre-update, post-update, health, rollback
STRICT_MODE="false"
OUTPUT_FORMAT="text"  # text, json, yaml
BACKUP_DIR=""
ROLLBACK_ENABLED="false"

# Validation results
VALIDATION_PASSED=0
VALIDATION_FAILED=0
VALIDATION_WARNINGS=0

# Functions
usage() {
    echo "EKS Cluster Validation Script"
    echo "============================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENVIRONMENT    Environment (dev, staging, production) [default: production]"
    echo "  -c, --cluster-name NAME          Cluster name [default: {environment}-eks]"
    echo "  -r, --region REGION              AWS region [default: ap-southeast-2]"
    echo "  -t, --validation-type TYPE       Validation type [default: all]"
    echo "  -s, --strict                     Strict mode (fail on warnings)"
    echo "  -f, --format FORMAT              Output format: text, json, yaml [default: text]"
    echo "  -b, --backup-dir DIR             Backup directory for rollback validation"
    echo "  --rollback                       Enable rollback validation"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo "Validation Types:"
    echo "  all          - Complete cluster validation"
    echo "  pre-update   - Pre-update readiness check"
    echo "  post-update  - Post-update validation"
    echo "  health       - Basic health check"
    echo "  rollback     - Rollback readiness and procedures"
    echo ""
    echo "Examples:"
    echo "  $0 --environment dev --validation-type health"
    echo "  $0 --environment production --validation-type pre-update --strict"
    echo "  $0 --environment staging --validation-type post-update"
    echo "  $0 --backup-dir backups/prod-cluster-20241215 --rollback"
    exit 1
}

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    ((VALIDATION_WARNINGS++))
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    ((VALIDATION_FAILED++))
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
    ((VALIDATION_PASSED++))
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
        -t|--validation-type)
            VALIDATION_TYPE="$2"
            shift 2
            ;;
        -s|--strict)
            STRICT_MODE="true"
            shift
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --rollback)
            ROLLBACK_ENABLED="true"
            VALIDATION_TYPE="rollback"
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

# Validate inputs
validate_inputs() {
    log "Validating inputs..."
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
        error "Invalid environment: $ENVIRONMENT. Must be dev, staging, or production"
        exit 1
    fi
    
    # Validate validation type
    if [[ ! "$VALIDATION_TYPE" =~ ^(all|pre-update|post-update|health|rollback)$ ]]; then
        error "Invalid validation type: $VALIDATION_TYPE"
        exit 1
    fi
    
    # Validate output format
    if [[ ! "$OUTPUT_FORMAT" =~ ^(text|json|yaml)$ ]]; then
        error "Invalid output format: $OUTPUT_FORMAT"
        exit 1
    fi
    
    # Validate backup directory for rollback
    if [[ "$VALIDATION_TYPE" == "rollback" && -n "$BACKUP_DIR" && ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    log "Input validation passed!"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        error "Invalid AWS credentials. Please configure AWS CLI"
        return 1
    fi
    
    # Check required tools
    local required_tools=("kubectl" "eksctl" "jq" "yq")
    for tool in "${required_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed"
            return 1
        fi
    done
    
    # Check if cluster exists
    if ! eksctl get cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" > /dev/null 2>&1; then
        error "Cluster $CLUSTER_NAME does not exist in region $AWS_REGION"
        return 1
    fi
    
    # Update kubeconfig
    if ! aws eks update-kubeconfig --name="$CLUSTER_NAME" --region="$AWS_REGION" --alias "$CLUSTER_NAME" > /dev/null 2>&1; then
        error "Failed to update kubeconfig for cluster $CLUSTER_NAME"
        return 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info > /dev/null 2>&1; then
        error "Cannot connect to cluster $CLUSTER_NAME"
        return 1
    fi
    
    success "Prerequisites check passed!"
    return 0
}

# Validate cluster health
validate_cluster_health() {
    log "Validating cluster health..."
    
    # Check cluster status
    local cluster_status=$(aws eks describe-cluster --name="$CLUSTER_NAME" --region="$AWS_REGION" --query 'cluster.status' --output text)
    if [[ "$cluster_status" != "ACTIVE" ]]; then
        error "Cluster is not in ACTIVE state: $cluster_status"
    else
        success "Cluster is in ACTIVE state"
    fi
    
    # Check node groups
    local node_groups=$(eksctl get nodegroup --cluster="$CLUSTER_NAME" --region="$AWS_REGION" -o json)
    if [[ -z "$node_groups" ]]; then
        error "No node groups found"
    else
        local total_node_groups=$(echo "$node_groups" | jq length)
        local active_node_groups=$(echo "$node_groups" | jq '[.[] | select(.Status == "ACTIVE")] | length')
        
        if [[ "$total_node_groups" -eq "$active_node_groups" ]]; then
            success "All $total_node_groups node groups are ACTIVE"
        else
            error "Only $active_node_groups out of $total_node_groups node groups are ACTIVE"
        fi
    fi
    
    # Check node status
    local nodes=$(kubectl get nodes --no-headers)
    local total_nodes=$(echo "$nodes" | wc -l)
    local ready_nodes=$(echo "$nodes" | grep -c "Ready" || echo "0")
    
    if [[ "$total_nodes" -eq "$ready_nodes" ]]; then
        success "All $total_nodes nodes are Ready"
    else
        error "Only $ready_nodes out of $total_nodes nodes are Ready"
        kubectl get nodes | grep -v "Ready" | head -5
    fi
    
    # Check control plane health
    local control_plane_health=$(kubectl get componentstatuses --no-headers 2>/dev/null | grep -c "Healthy" || echo "0")
    local total_components=$(kubectl get componentstatuses --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$total_components" -gt 0 ]]; then
        if [[ "$control_plane_health" -eq "$total_components" ]]; then
            success "Control plane is healthy"
        else
            warn "Control plane components may not be fully healthy"
        fi
    fi
    
    log "Cluster health validation completed"
}

# Validate system pods
validate_system_pods() {
    log "Validating system pods..."
    
    local system_namespaces=("kube-system" "argocd" "monitoring" "ingress-nginx" "cert-manager" "external-dns")
    
    for ns in "${system_namespaces[@]}"; do
        if kubectl get namespace "$ns" > /dev/null 2>&1; then
            log "Checking namespace: $ns"
            
            # Get pod status
            local pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null || echo "")
            if [[ -z "$pods" ]]; then
                info "No pods found in namespace $ns"
                continue
            fi
            
            local total_pods=$(echo "$pods" | wc -l)
            local running_pods=$(echo "$pods" | grep -c "Running\|Completed" || echo "0")
            local failed_pods=$(echo "$pods" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" || echo "")
            
            if [[ "$total_pods" -eq "$running_pods" ]]; then
                success "All $total_pods pods in namespace $ns are running"
            else
                error "Only $running_pods out of $total_pods pods in namespace $ns are running"
                if [[ -n "$failed_pods" ]]; then
                    echo "$failed_pods" | head -3
                fi
            fi
        else
            info "Namespace $ns does not exist"
        fi
    done
    
    log "System pods validation completed"
}

# Validate addons
validate_addons() {
    log "Validating EKS addons..."
    
    local addons=$(aws eks list-addons --cluster-name="$CLUSTER_NAME" --region="$AWS_REGION" --query 'addons' --output json)
    
    if [[ "$addons" == "[]" || "$addons" == "null" ]]; then
        warn "No EKS addons found"
        return 0
    fi
    
    local addon_names=($(echo "$addons" | jq -r '.[]'))
    
    for addon in "${addon_names[@]}"; do
        local addon_status=$(aws eks describe-addon --cluster-name="$CLUSTER_NAME" --addon-name="$addon" --region="$AWS_REGION" --query 'addon.status' --output text)
        local addon_version=$(aws eks describe-addon --cluster-name="$CLUSTER_NAME" --addon-name="$addon" --region="$AWS_REGION" --query 'addon.addonVersion' --output text)
        
        if [[ "$addon_status" == "ACTIVE" ]]; then
            success "Addon $addon is ACTIVE (version: $addon_version)"
        else
            error "Addon $addon is not ACTIVE: $addon_status"
        fi
    done
    
    log "EKS addons validation completed"
}

# Validate networking
validate_networking() {
    log "Validating networking..."
    
    # Check VPC CNI
    local vpc_cni_pods=$(kubectl get pods -n kube-system -l app=aws-node --no-headers 2>/dev/null || echo "")
    if [[ -n "$vpc_cni_pods" ]]; then
        local total_cni_pods=$(echo "$vpc_cni_pods" | wc -l)
        local running_cni_pods=$(echo "$vpc_cni_pods" | grep -c "Running" || echo "0")
        
        if [[ "$total_cni_pods" -eq "$running_cni_pods" ]]; then
            success "VPC CNI is running on all nodes ($total_cni_pods/$running_cni_pods)"
        else
            error "VPC CNI is not running on all nodes ($running_cni_pods/$total_cni_pods)"
        fi
    else
        warn "VPC CNI pods not found"
    fi
    
    # Check CoreDNS
    local coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null || echo "")
    if [[ -n "$coredns_pods" ]]; then
        local total_coredns_pods=$(echo "$coredns_pods" | wc -l)
        local running_coredns_pods=$(echo "$coredns_pods" | grep -c "Running" || echo "0")
        
        if [[ "$total_coredns_pods" -eq "$running_coredns_pods" ]]; then
            success "CoreDNS is running ($total_coredns_pods/$running_coredns_pods pods)"
        else
            error "CoreDNS is not fully running ($running_coredns_pods/$total_coredns_pods pods)"
        fi
    else
        warn "CoreDNS pods not found"
    fi
    
    # Test DNS resolution
    if kubectl run dns-test --image=busybox --restart=Never --rm -it --command -- nslookup kubernetes.default.svc.cluster.local > /dev/null 2>&1; then
        success "DNS resolution is working"
    else
        error "DNS resolution is not working"
    fi
    
    log "Networking validation completed"
}

# Validate storage
validate_storage() {
    log "Validating storage..."
    
    # Check EBS CSI driver
    local ebs_csi_pods=$(kubectl get pods -n kube-system -l app=ebs-csi-controller --no-headers 2>/dev/null || echo "")
    if [[ -n "$ebs_csi_pods" ]]; then
        local total_ebs_pods=$(echo "$ebs_csi_pods" | wc -l)
        local running_ebs_pods=$(echo "$ebs_csi_pods" | grep -c "Running" || echo "0")
        
        if [[ "$total_ebs_pods" -eq "$running_ebs_pods" ]]; then
            success "EBS CSI driver is running ($total_ebs_pods/$running_ebs_pods pods)"
        else
            error "EBS CSI driver is not fully running ($running_ebs_pods/$total_ebs_pods pods)"
        fi
    else
        warn "EBS CSI driver pods not found"
    fi
    
    # Check storage classes
    local storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null || echo "")
    if [[ -n "$storage_classes" ]]; then
        local total_sc=$(echo "$storage_classes" | wc -l)
        success "Found $total_sc storage classes"
    else
        warn "No storage classes found"
    fi
    
    log "Storage validation completed"
}

# Pre-update validation
pre_update_validation() {
    log "Running pre-update validation..."
    
    # All standard checks
    validate_cluster_health
    validate_system_pods
    validate_addons
    validate_networking
    validate_storage
    
    # Additional pre-update checks
    log "Running additional pre-update checks..."
    
    # Check for stuck pods
    local stuck_pods=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null || echo "")
    if [[ -n "$stuck_pods" ]]; then
        warn "Found pods not in Running/Succeeded state:"
        echo "$stuck_pods" | head -5
    else
        success "No stuck pods found"
    fi
    
    # Check for pending PVCs
    local pending_pvcs=$(kubectl get pvc -A --field-selector=status.phase!=Bound 2>/dev/null || echo "")
    if [[ -n "$pending_pvcs" ]]; then
        warn "Found PVCs not in Bound state:"
        echo "$pending_pvcs" | head -5
    else
        success "All PVCs are bound"
    fi
    
    # Check cluster resource usage
    local node_usage=$(kubectl top nodes 2>/dev/null || echo "")
    if [[ -n "$node_usage" ]]; then
        info "Node resource usage:"
        echo "$node_usage"
    fi
    
    log "Pre-update validation completed"
}

# Post-update validation
post_update_validation() {
    log "Running post-update validation..."
    
    # Wait for cluster to stabilize
    log "Waiting for cluster to stabilize..."
    sleep 30
    
    # All standard checks
    validate_cluster_health
    validate_system_pods
    validate_addons
    validate_networking
    validate_storage
    
    # Additional post-update checks
    log "Running additional post-update checks..."
    
    # Test basic functionality
    log "Testing basic cluster functionality..."
    
    # Create and test a pod
    if kubectl run validation-test --image=alpine --restart=Never --rm --timeout=300s --command -- echo "Cluster validation test" > /dev/null 2>&1; then
        success "Basic pod creation and execution works"
    else
        error "Basic pod creation and execution failed"
    fi
    
    # Test service discovery
    if kubectl run service-test --image=busybox --restart=Never --rm --timeout=300s --command -- nslookup kubernetes.default.svc.cluster.local > /dev/null 2>&1; then
        success "Service discovery works"
    else
        error "Service discovery failed"
    fi
    
    log "Post-update validation completed"
}

# Rollback validation and procedures
rollback_validation() {
    log "Running rollback validation..."
    
    if [[ -z "$BACKUP_DIR" ]]; then
        error "Backup directory not specified for rollback validation"
        return 1
    fi
    
    # Validate backup directory
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
        return 1
    fi
    
    # Check backup contents
    local required_files=("cluster-config.yaml" "nodegroups.yaml" "addons.json")
    for file in "${required_files[@]}"; do
        if [[ -f "$BACKUP_DIR/$file" ]]; then
            success "Backup file found: $file"
        else
            error "Backup file missing: $file"
        fi
    done
    
    # Show rollback instructions
    log "Rollback procedures:"
    info "1. Backup current state before rollback"
    info "2. Review changes to be rolled back"
    info "3. Use backup files to restore previous configuration"
    info "4. Validate cluster after rollback"
    
    warn "Rollback procedures are not yet fully automated"
    warn "Manual intervention may be required for complex rollbacks"
    
    log "Rollback validation completed"
}

# Generate validation report
generate_report() {
    log "Generating validation report..."
    
    local report_file="cluster-validation-$(date +%Y%m%d-%H%M%S).${OUTPUT_FORMAT}"
    
    case "$OUTPUT_FORMAT" in
        "json")
            cat > "$report_file" << EOF
{
  "cluster": "$CLUSTER_NAME",
  "environment": "$ENVIRONMENT",
  "region": "$AWS_REGION",
  "validation_type": "$VALIDATION_TYPE",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "results": {
    "passed": $VALIDATION_PASSED,
    "failed": $VALIDATION_FAILED,
    "warnings": $VALIDATION_WARNINGS
  },
  "status": "$(if [[ $VALIDATION_FAILED -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)"
}
EOF
            ;;
        "yaml")
            cat > "$report_file" << EOF
cluster: $CLUSTER_NAME
environment: $ENVIRONMENT
region: $AWS_REGION
validation_type: $VALIDATION_TYPE
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
results:
  passed: $VALIDATION_PASSED
  failed: $VALIDATION_FAILED
  warnings: $VALIDATION_WARNINGS
status: $(if [[ $VALIDATION_FAILED -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)
EOF
            ;;
        *)
            cat > "$report_file" << EOF
Cluster Validation Report
========================

Cluster: $CLUSTER_NAME
Environment: $ENVIRONMENT
Region: $AWS_REGION
Validation Type: $VALIDATION_TYPE
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Results:
  Passed: $VALIDATION_PASSED
  Failed: $VALIDATION_FAILED
  Warnings: $VALIDATION_WARNINGS

Status: $(if [[ $VALIDATION_FAILED -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)
EOF
            ;;
    esac
    
    info "Validation report generated: $report_file"
}

# Main execution
main() {
    log "EKS Cluster Validation Script"
    log "============================="
    log "Cluster: $CLUSTER_NAME"
    log "Environment: $ENVIRONMENT"
    log "Region: $AWS_REGION"
    log "Validation Type: $VALIDATION_TYPE"
    log "Strict Mode: $STRICT_MODE"
    
    # Reset counters
    VALIDATION_PASSED=0
    VALIDATION_FAILED=0
    VALIDATION_WARNINGS=0
    
    # Validate inputs
    validate_inputs
    
    # Check prerequisites
    if ! check_prerequisites; then
        error "Prerequisites check failed"
        exit 1
    fi
    
    # Run validation based on type
    case "$VALIDATION_TYPE" in
        "health")
            validate_cluster_health
            ;;
        "pre-update")
            pre_update_validation
            ;;
        "post-update")
            post_update_validation
            ;;
        "rollback")
            rollback_validation
            ;;
        "all")
            validate_cluster_health
            validate_system_pods
            validate_addons
            validate_networking
            validate_storage
            ;;
    esac
    
    # Generate report
    generate_report
    
    # Show summary
    log "Validation Summary"
    log "=================="
    log "Passed: $VALIDATION_PASSED"
    log "Failed: $VALIDATION_FAILED"
    log "Warnings: $VALIDATION_WARNINGS"
    
    # Determine exit code
    if [[ $VALIDATION_FAILED -gt 0 ]]; then
        error "Validation failed with $VALIDATION_FAILED errors"
        exit 1
    elif [[ $VALIDATION_WARNINGS -gt 0 && "$STRICT_MODE" == "true" ]]; then
        error "Validation failed in strict mode with $VALIDATION_WARNINGS warnings"
        exit 1
    else
        success "Validation completed successfully!"
        exit 0
    fi
}

# Run main function
main "$@" 