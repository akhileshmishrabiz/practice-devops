#!/bin/bash
# Install Cilium CNI on Kind cluster
# Run this after creating cluster with kind-config-cilium.yaml

set -e

echo "Installing Cilium CLI..."
if ! command -v cilium &> /dev/null; then
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    CLI_ARCH=amd64
    if [ "$(uname -m)" = "arm64" ]; then CLI_ARCH=arm64; fi
    curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-darwin-${CLI_ARCH}.tar.gz
    sudo tar xzvfC cilium-darwin-${CLI_ARCH}.tar.gz /usr/local/bin
    rm cilium-darwin-${CLI_ARCH}.tar.gz
fi

echo "Installing Cilium on cluster..."
cilium install --version 1.14.5

echo "Waiting for Cilium to be ready..."
cilium status --wait

echo "Enabling Hubble (observability)..."
cilium hubble enable --ui

echo "Cilium installed successfully!"
echo ""
echo "Useful commands:"
echo "  cilium status"
echo "  cilium connectivity test"
echo "  cilium hubble ui"
