#!/bin/bash

# Kubernetes Control-Plane Upgrade Script
# From version 1.30.4 to 1.31.0, using the recommended Kubernetes repository

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a package is installed
package_installed() {
    dpkg -s "$1" > /dev/null 2>&1
}

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo."
    exit 1
fi

# Update package lists
echo "Updating package lists..."
apt update

# Check if kubeadm is installed
if ! package_installed kubeadm; then
    echo "kubeadm is not installed. Please install Kubernetes before running this script."
    exit 1
fi

# Get current version
CURRENT_VERSION=$(kubeadm version -o short | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+')
echo "Current Kubernetes version: $CURRENT_VERSION"

# Check if we're starting from the correct version
if [[ "$CURRENT_VERSION" != "1.30.4" ]]; then
    echo "This script is designed to upgrade from v1.30.4. Current version is $CURRENT_VERSION."
    exit 1
fi

# Change package repository to the recommended Kubernetes repository for v1.31
echo "Changing Kubernetes package repository..."
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /
EOF

# Add the GPG key for the new repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Update package lists again after changing repo
apt update

# Unhold kubeadm to allow version update
echo "Unholding kubeadm..."
apt-mark unhold kubeadm

# Upgrade kubeadm to the target version
echo "Upgrading kubeadm to v1.31.0..."
apt-get update && apt-get install -y kubeadm='1.31.0-*'

# Hold kubeadm at the new version
echo "Holding kubeadm at version 1.31.0..."
apt-mark hold kubeadm

# Upgrade the control plane
echo "Upgrading the control plane..."
kubeadm upgrade apply v1.31.0

# Update kubectl and kubelet
echo "Updating kubectl and kubelet..."
apt-get install -y kubectl=1.31.0-* kubelet=1.31.0-*

# Ensure kubelet restarts with new version
systemctl restart kubelet

# Verify the upgrade
echo "Verifying upgrade..."
NEW_VERSION=$(kubeadm version -o short | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+')
if [[ "$NEW_VERSION" == "v1.31.0" ]]; then
    echo "Kubernetes control-plane successfully upgraded to v1.31.0"
else
    echo "Upgrade failed or incomplete. Current version is $NEW_VERSION"
fi

# Clean up
echo "Cleaning up..."
apt-get autoremove -y
apt-get clean

echo "Upgrade process completed. Note: This script used the recommended Kubernetes repository for version 1.31."
