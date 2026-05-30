#!/bin/bash
# Install Cilium CNI on Kind cluster (NetworkPolicy enforcement).
# Run after: kind create cluster --config networking/kind-config-networking.yaml

set -e

echo "Installing Cilium CLI..."
if ! command -v cilium &> /dev/null; then
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    CLI_ARCH=amd64
    if [ "$(uname -m)" = "arm64" ]; then CLI_ARCH=arm64; fi
    OS=darwin
    if [ "$(uname -s)" = "Linux" ]; then OS=linux; fi
    curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-${OS}-${CLI_ARCH}.tar.gz"
    tar xzvfC "cilium-${OS}-${CLI_ARCH}.tar.gz" /usr/local/bin
    rm "cilium-${OS}-${CLI_ARCH}.tar.gz"
fi

echo "Installing Cilium on cluster..."
cilium install --version 1.14.5

echo "Waiting for Cilium to be ready..."
cilium status --wait

echo "Enabling Hubble (optional observability UI)..."
cilium hubble enable --ui 2>/dev/null || echo "Hubble UI already enabled or skipped"

echo "Cilium installed successfully!"
