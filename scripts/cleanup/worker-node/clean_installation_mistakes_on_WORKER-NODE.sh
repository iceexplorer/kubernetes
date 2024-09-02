#!/bin/bash

# Script to manage Kubernetes components on a worker node, ensuring correct control-plane IP and handling package holds

# Function to check if a package is installed
package_installed() {
    dpkg -s "$1" > /dev/null 2>&1
}

# Function to check if a package is on hold
package_on_hold() {
    if apt-mark showhold | grep -q "$1"; then
        return 0  # Package is on hold
    else
        return 1  # Package is not on hold
    fi
}

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo."
    exit 1
fi

# Update package lists
echo "Updating package lists..."
apt update

# List of control-plane packages to potentially unhold
control_plane_packages=(
    kube-apiserver
    kube-controller-manager
    kube-scheduler
    kubeadm  # Added kubeadm to the list
)

# Unhold control-plane packages if they are on hold
for package in "${control_plane_packages[@]}"; do
    if package_installed "$package" && package_on_hold "$package"; then
        echo "Unholding $package..."
        apt-mark unhold "$package"
    fi
done

# List of packages to remove (kubectl is removed from this list)
packages_to_remove=(
    kubeadm  # Note: We're removing kubeadm but unholding it for control-plane use
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
