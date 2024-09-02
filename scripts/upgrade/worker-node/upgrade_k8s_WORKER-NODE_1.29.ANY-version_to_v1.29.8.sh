#!/bin/bash

# Kubernetes Worker Node Update Script to version 1.29.8

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a package is installed
package_installed() {
    dpkg -s "$1" > /dev/null 2>&1
}

# Function to get current repository URL
get_repo_url() {
    grep -oP 'deb \K.*' /etc/apt/sources.list.d/kubernetes.list 2>/dev/null | head -n 1
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

# Target version
TARGET_VERSION="1.29.8"

# Extract minor version (e.g., 1.29 from 1.29.1)
MINOR_VERSION=$(echo $CURRENT_VERSION | cut -d. -f1-2)

# Determine the repository URL based on the minor version
REPO_URL="https://pkgs.k8s.io/core:/stable:/${MINOR_VERSION}/deb/"

# Check if the repository needs to be updated
CURRENT_REPO_URL=$(get_repo_url)
if [ "$CURRENT_REPO_URL" != "$REPO_URL" ]; then
    echo "Updating Kubernetes package repository for version ${MINOR_VERSION}..."
    cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${REPO_URL} /
EOF

    # Add the GPG key for the repository if not already present
    if ! [ -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
        curl -fsSL "${REPO_URL}/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    fi
fi

# Upgrade to the target version
echo "Upgrading to version $TARGET_VERSION..."
apt-get update && apt-get install -y kubelet="$TARGET_VERSION" kubectl="$TARGET_VERSION" && apt-mark hold kubelet kubectl

# Restart kubelet
systemctl restart kubelet

echo "Upgrade to $TARGET_VERSION completed."

# Clean up
echo "Cleaning up..."
apt-get autoremove -y
apt-get clean

echo "Upgrade process completed. Note: This script used the recommended Kubernetes repository for ${MINOR_VERSION}."
