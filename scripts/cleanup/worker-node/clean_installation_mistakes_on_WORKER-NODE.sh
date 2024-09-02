#!/bin/bash

# Script to remove unnecessary Kubernetes components from a worker node and ensure correct control-plane IP
# This script is made to ensure that no mistakes has been done when experimenting with the setup og worker-nodes. Some manuals out there ask you to install a lot of control-plane functionality on a worker node

# Function to check if a package is installed
package_installed() {
    dpkg -s "$1" > /dev/null 2>&1
}

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo."
    exit 1
fi

# List of packages to remove (kubectl is removed from this list)
packages_to_remove=(
    kubeadm
    kubernetes-cni
    kube-apiserver
    kube-controller-manager
    kube-scheduler
    etcd
)

# Remove each package if installed
for package in "${packages_to_remove[@]}"; do
    if package_installed "$package"; then
        echo "Removing $package..."
        apt-get remove -y "$package"
    else
        echo "$package is not installed."
    fi
done

# Autoremove any dependencies that are no longer needed
echo "Removing unused dependencies..."
apt-get autoremove -y

# Clean up package cache
echo "Cleaning up package cache..."
apt-get clean

# Section to ensure correct IP for control-plane and fix config
echo "Ensuring correct IP for control-plane and fixing config..."

# Ask user for the control-plane IP
read -p "Please enter the IP address of the control-plane: " CONTROL_PLANE_IP

echo "You entered: $CONTROL_PLANE_IP. Proceeding with this IP..."

# Edit /etc/kubernetes/admin.conf and /etc/kubernetes/controller-manager.conf
for file in /etc/kubernetes/admin.conf /etc/kubernetes/controller-manager.conf; do
    if [ -f "$file" ]; then
        sed -i "s/server: https:\/\/127.0.0.1:6443/server: https:\/\/$CONTROL_PLANE_IP:6443/" "$file"
        echo "Updated $file with new control-plane IP"
    else
        echo "File $file not found. Skipping."
    fi
done

# Edit /etc/kubernetes/scheduler.conf if it exists
if [ -f "/etc/kubernetes/scheduler.conf" ]; then
    sed -i "s/server: https:\/\/127.0.0.1:6443/server: https:\/\/$CONTROL_PLANE_IP:6443/" "/etc/kubernetes/scheduler.conf"
    echo "Updated /etc/kubernetes/scheduler.conf with new control-plane IP"
else
    echo "/etc/kubernetes/scheduler.conf not found. Skipping."
fi

# Restart kubelet to pick up new configuration
echo "Restarting kubelet to apply new configuration..."
systemctl restart kubelet

# Check if kubelet restarted successfully
if systemctl is-active --quiet kubelet; then
    echo "kubelet restarted successfully."
else
    echo "Warning: kubelet failed to restart. Check logs for more information."
fi

echo "Cleanup of unnecessary Kubernetes components completed, control-plane IP configuration updated, and kubelet restarted."
