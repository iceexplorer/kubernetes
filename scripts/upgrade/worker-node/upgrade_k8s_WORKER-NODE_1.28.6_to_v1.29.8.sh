#!/bin/bash

# Kubernetes Worker Node Upgrade Script
# From version 1.28.6 to 1.29.8, using the recommended Kubernetes repository

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

# Check if kubelet is installed
if ! package_installed kubelet; then
    echo "kubelet is not installed. Please install Kubernetes before running this script."
    exit 1
fi

# Get current version of kubelet
CURRENT_VERSION=$(kubelet --version | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+')
echo "Current Kubernetes node version: $CURRENT_VERSION"

# Check if we're starting from the correct version
if [[ "$CURRENT_VERSION" != "1.28.6" ]]; then
    echo "This script is designed to upgrade from v1.28.6. Current version is $CURRENT_VERSION."
    exit 1
fi

# Change package repository to the new version's repository
echo "Changing Kubernetes package repository..."
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /
EOF

# Add the GPG key for the new repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Update package lists again after changing repo
apt update

# Unhold kubelet and kubectl to allow version update
echo "Unholding kubelet and kubectl..."
apt-mark unhold kubelet kubectl

# Upgrade kubelet and kubectl to the target version
echo "Upgrading kubelet and kubectl to v1.29.8..."
apt-get update && apt-get install -y kubelet='1.29.8-00' kubectl='1.29.8-00'

# Hold kubelet and kubectl at the new version
echo "Holding kubelet and kubectl at version 1.29.8..."
apt-mark hold kubelet kubectl

# Ensure kubelet restarts with new version
echo "Restarting kubelet..."
systemctl restart kubelet

# Verify the upgrade
echo "Verifying upgrade..."
NEW_VERSION=$(kubelet --version | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+')
if [[ "$NEW_VERSION" == "1.31.0" ]]; then
    echo "Kubernetes node successfully upgraded to v1.29.8"
else
    echo "Upgrade failed or incomplete. Current version is $NEW_VERSION"
fi

# Clean up
echo "Cleaning up..."
apt-get autoremove -y
apt-get clean

echo "Upgrade process completed. Note: This script used the recommended Kubernetes repository for v1.29.8."
