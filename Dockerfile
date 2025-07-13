FROM alpine:3.18

# Install base packages
RUN apk add --no-cache \
    bash \
    curl \
    git \
    jq \
    yq \
    tar \
    gzip \
    ca-certificates \
    python3 \
    py3-pip \
    openssl

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install eksctl
RUN curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && \
    mv /tmp/eksctl /usr/local/bin

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install additional tools
RUN pip3 install --no-cache-dir \
    boto3 \
    awscli-local \
    kubernetes

# Create working directory
WORKDIR /eks-cluster

# Copy cluster configuration files
COPY cluster-config/ ./cluster-config/
COPY scripts/ ./scripts/
COPY gitops/ ./gitops/

# Make scripts executable
RUN chmod +x scripts/*.sh gitops/bootstrap.sh

# Create kustomize symlinks for easier access
RUN ln -sf /usr/local/bin/kustomize /usr/local/bin/kustomize

# Set default shell
SHELL ["/bin/bash", "-c"]

# Default command
CMD ["/bin/bash"] 