# EKS Cluster Management Makefile
# Production-grade EKS cluster using eksctl in Docker

.PHONY: help build shell create-cluster delete-cluster scale-cluster clean

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

##@ Cluster Updates
update-cluster: ## Update cluster (all components)
	@echo -e "$(YELLOW)Updating cluster $(CLUSTER_NAME)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) update-cluster

update-cluster-dry-run: ## Dry run cluster update (show what would be updated)
	@echo -e "$(YELLOW)Dry run cluster update for $(CLUSTER_NAME)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) update-cluster --dry-run

update-k8s-version: ## Update Kubernetes version
	@echo -e "$(YELLOW)Updating Kubernetes version for $(CLUSTER_NAME)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		update-cluster --update-type k8s-version $(if $(VERSION),--target-version $(VERSION))

update-nodegroups: ## Update node groups (AMI, configurations)
	@echo -e "$(YELLOW)Updating node groups for $(CLUSTER_NAME)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		update-cluster --update-type nodegroups

update-addons: ## Update EKS addons
	@echo -e "$(YELLOW)Updating EKS addons for $(CLUSTER_NAME)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		update-cluster --update-type addons

update-cluster-config: ## Update cluster configuration from file
	@echo -e "$(YELLOW)Updating cluster configuration for $(CLUSTER_NAME)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		update-cluster --update-type config

validate-cluster: ## Validate cluster health and readiness
	@echo -e "$(YELLOW)Validating cluster $(CLUSTER_NAME)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) validate-cluster

validate-pre-update: ## Validate cluster readiness for updates
	@echo -e "$(YELLOW)Validating cluster $(CLUSTER_NAME) for updates...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		validate-cluster --validation-type pre-update

validate-post-update: ## Validate cluster after updates
	@echo -e "$(YELLOW)Validating cluster $(CLUSTER_NAME) after updates...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		validate-cluster --validation-type post-update

validate-health: ## Basic cluster health check
	@echo -e "$(YELLOW)Checking cluster $(CLUSTER_NAME) health...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		validate-cluster --validation-type health

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

##@ GitOps with ArgoCD
gitops-bootstrap: ## Bootstrap ArgoCD and deploy applications for current environment
	@echo -e "$(GREEN)Bootstrapping ArgoCD and applications for $(ENVIRONMENT)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"cd gitops && ./bootstrap.sh --environment $(ENVIRONMENT)"

gitops-bootstrap-ui: ## Bootstrap ArgoCD with UI port-forward for current environment
	@echo -e "$(GREEN)Bootstrapping ArgoCD with UI access for $(ENVIRONMENT)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"cd gitops && ./bootstrap.sh --environment $(ENVIRONMENT) --port-forward"

gitops-update-configs: ## Update GitOps application configurations for current environment
	@echo -e "$(YELLOW)Updating GitOps configurations for $(ENVIRONMENT)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"cd gitops && ./bootstrap.sh --environment $(ENVIRONMENT) --update-configs"

##@ Multi-Environment GitOps
gitops-bootstrap-dev: ## Bootstrap ArgoCD and applications for dev environment
	@$(MAKE) gitops-bootstrap ENVIRONMENT=dev

gitops-bootstrap-staging: ## Bootstrap ArgoCD and applications for staging environment
	@$(MAKE) gitops-bootstrap ENVIRONMENT=staging

gitops-bootstrap-prod: ## Bootstrap ArgoCD and applications for production environment
	@$(MAKE) gitops-bootstrap ENVIRONMENT=production

gitops-status-dev: ## Check GitOps applications status for dev environment
	@$(MAKE) gitops-status ENVIRONMENT=dev

gitops-status-staging: ## Check GitOps applications status for staging environment
	@$(MAKE) gitops-status ENVIRONMENT=staging

gitops-status-prod: ## Check GitOps applications status for production environment
	@$(MAKE) gitops-status ENVIRONMENT=production

##@ ArgoCD Management
argocd-ui: ## Access ArgoCD UI (port-forward)
	@echo -e "$(GREEN)Starting ArgoCD UI port-forward...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl port-forward svc/argocd-server -n argocd 8080:443"

argocd-password: ## Get ArgoCD admin password
	@echo -e "$(YELLOW)Getting ArgoCD admin password...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"

argocd-apps: ## List ArgoCD applications
	@echo -e "$(YELLOW)Listing ArgoCD applications...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl get applications -n argocd"

argocd-sync: ## Sync all ArgoCD applications
	@echo -e "$(GREEN)Syncing all ArgoCD applications...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl patch applications -n argocd --type merge -p '{\"spec\":{\"syncPolicy\":{\"automated\":{\"prune\":true,\"selfHeal\":true}}}}' --all"

argocd-logs: ## View ArgoCD application controller logs
	@echo -e "$(YELLOW)Viewing ArgoCD logs...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl logs -n argocd deployment/argocd-application-controller -f"

gitops-status: ## Check GitOps applications status
	@echo -e "$(YELLOW)Checking GitOps applications status for $(ENVIRONMENT)...$(NC)"
	bash scripts/run-docker.sh --environment $(ENVIRONMENT) \
		"kubectl get applications -n argocd && echo '---' && kubectl get pods -A | grep -E '(argocd|kube-system|monitoring|ingress-nginx|external-dns|cert-manager)'"

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