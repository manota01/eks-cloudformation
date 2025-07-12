# EKS Cluster Management Makefile
# Production-grade EKS cluster using eksctl in Docker

.PHONY: help build shell create-cluster delete-cluster install-addons scale-cluster clean

# Default environment
ENVIRONMENT ?= production
CLUSTER_NAME ?= $(ENVIRONMENT)-eks
AWS_REGION ?= ap-southeast-2

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "EKS Cluster Management Commands"
	@echo "==============================="
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make [target]\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-15s %s\n", $$1, $$2 } /^##@/ { printf "\n%s\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Docker Management
build: ## Build the Docker image
	@echo -e "$(YELLOW)Building Docker image...$(NC)"
	docker build -t eks-cluster-manager .

shell: ## Start interactive shell in container
	@echo -e "$(GREEN)Starting interactive shell...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) bash

##@ Cluster Lifecycle
create-cluster: ## Create EKS cluster
	@echo -e "$(GREEN)Creating $(ENVIRONMENT) EKS cluster...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) create-cluster

delete-cluster: ## Delete EKS cluster
	@echo -e "$(RED)Deleting $(ENVIRONMENT) EKS cluster...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) delete-cluster

validate-cluster: ## Validate cluster configuration
	@echo -e "$(YELLOW)Validating cluster configuration...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"eksctl create cluster --config-file=cluster-config/$(ENVIRONMENT)-cluster.yaml --dry-run"

##@ Cluster Management
install-addons: ## Install essential add-ons
	@echo -e "$(GREEN)Installing add-ons...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) install-addons

scale-cluster: ## Scale cluster nodes
	@echo -e "$(YELLOW)Scaling cluster...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) scale-cluster

status: ## Check cluster status
	@echo -e "$(YELLOW)Checking cluster status...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"eksctl get cluster --name=$(CLUSTER_NAME) --region=$(AWS_REGION)"

nodes: ## List cluster nodes
	@echo -e "$(YELLOW)Listing cluster nodes...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl get nodes -o wide"

pods: ## List all pods
	@echo -e "$(YELLOW)Listing all pods...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl get pods --all-namespaces"

##@ Development
create-dev: ## Create development cluster
	@$(MAKE) create-cluster ENVIRONMENT=dev

delete-dev: ## Delete development cluster
	@$(MAKE) delete-cluster ENVIRONMENT=dev

dev-shell: ## Start shell for development environment
	@$(MAKE) shell ENVIRONMENT=dev

##@ Monitoring
monitoring: ## Access monitoring dashboard
	@echo -e "$(GREEN)Starting port-forward to Grafana...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"

logs: ## View cluster logs
	@echo -e "$(YELLOW)Viewing cluster logs...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl logs -n kube-system -l app=cluster-autoscaler"

##@ Utilities
lint: ## Lint cluster configuration
	@echo -e "$(YELLOW)Linting configuration files...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"find cluster-config -name '*.yaml' -exec yq eval '.' {} \;"

update-kubeconfig: ## Update kubeconfig
	@echo -e "$(YELLOW)Updating kubeconfig...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"aws eks update-kubeconfig --name=$(CLUSTER_NAME) --region=$(AWS_REGION)"

clean: ## Clean up Docker images and containers
	@echo -e "$(YELLOW)Cleaning up Docker resources...$(NC)"
	docker system prune -f
	docker image prune -f

##@ Documentation
docs: ## Generate documentation
	@echo -e "$(GREEN)Generating documentation...$(NC)"
	@echo "Documentation available in README.md"

##@ Examples
example-app: ## Deploy example application
	@echo -e "$(GREEN)Deploying example application...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl apply -f examples/sample-app.yaml"

##@ Environment-specific targets
prod-create: ## Create production cluster
	@$(MAKE) create-cluster ENVIRONMENT=production

prod-delete: ## Delete production cluster
	@$(MAKE) delete-cluster ENVIRONMENT=production

staging-create: ## Create staging cluster
	@$(MAKE) create-cluster ENVIRONMENT=staging

staging-delete: ## Delete staging cluster
	@$(MAKE) delete-cluster ENVIRONMENT=staging 