#!/bin/bash

# Kubernetes Control-Plane Update Script
# Options to update to the latest patch version or step-by-step within the same minor version

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

# Function to perform a single step upgrade
step_upgrade() {
    # Find the next version
    NEXT_VERSION=$(apt list --upgradable 2>/dev/null | grep kubeadm | awk -F'/' '{print $2}' | awk -F'-' '{print $1}' | sort -V | tail -n 1)
    
    if [ -z "$NEXT_VERSION" ]; then
        echo "No further updates available."
        return 1
    fi

    echo "Upgrading to version $NEXT_VERSION..."
    apt-get update && apt-get install -y kubeadm="$NEXT_VERSION-*" && apt-mark hold kubeadm
    
    # Upgrade the control plane
    kubeadm upgrade apply $NEXT_VERSION
    
    # Update kubectl and kubelet
    apt-get install -y kubectl="$NEXT_VERSION-00" kubelet="$NEXT_VERSION-00"
    
    # Restart kubelet
    systemctl restart kubelet
    
    echo "Upgrade to $NEXT_VERSION completed."
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
        curl -fsSL "${REPO_URL}Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    fi

    # Update package lists after changing repo
    apt update
fi

# Prompt user for upgrade type
echo "Choose upgrade type:"
echo "1. Upgrade to the latest patch version within $MINOR_VERSION"
echo "2. Upgrade step-by-step"
read -p "Enter your choice (1 or 2): " CHOICE

case $CHOICE in
    1)
        # Upgrade to the latest version
        echo "Upgrading to the latest version within ${MINOR_VERSION}..."
        
        # Unhold kubeadm to allow version update
        apt-mark unhold kubeadm

        # Find the latest version available in the repository
        LATEST_VERSION=$(apt list --upgradable 2>/dev/null | grep kubeadm | awk -F'/' '{print $2}' | awk -F'-' '{print $1}' | sort -V | tail -n 1)

        # Check if there's an update available
        if [ -z "$LATEST_VERSION" ]; then
            echo "No updates available for kubeadm within version ${MINOR_VERSION}."
            exit 0
        fi

        echo "Upgrading to the latest version within ${MINOR_VERSION}: $LATEST_VERSION"

        # Upgrade kubeadm to the latest version
        apt-get update && apt-get install -y kubeadm="$LATEST_VERSION-*" && apt-mark hold kubeadm
        
        # Upgrade the control plane
        kubeadm upgrade apply $LATEST_VERSION
        
        # Update kubectl and kubelet to match the new kubeadm version
        apt-get install -y kubectl="$LATEST_VERSION-00" kubelet="$LATEST_VERSION-00"
        
        # Restart kubelet
        systemctl restart kubelet
        
        echo "Upgrade to $LATEST_VERSION completed."
        ;;
    
    2)
        # Step-by-step upgrade
        echo "Starting step-by-step upgrade process. Run this script again for each step."
        step_upgrade
        ;;
    
    *)
        echo "Invalid option. Please choose 1 or 2."
        exit 1
        ;;
esac
