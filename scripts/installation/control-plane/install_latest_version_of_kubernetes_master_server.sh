#!/bin/bash
#WARNING: This is the first version of this script. It has NOT BEEN TESTED, but made from momory and guides alone.
#DO NOT use this script yet!

# Update system and install necessary packages
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl

# Install Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Install containerd
sudo apt install -y containerd.io

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sudo systemctl restart containerd

# Add Kubernetes apt repository
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package list to get the latest versions
sudo apt update

# Install the latest stable versions of kubeadm, kubelet, and kubectl
sudo apt install -y kubeadm kubelet kubectl

# Hold Kubernetes packages to prevent auto-updates
sudo apt-mark hold kubeadm kubelet kubectl

# Disable swap
sudo swapoff -a

# Set up hostname for the control plane
sudo hostnamectl set-hostname k8s-control-plane

# Ensure net.bridge.bridge-nf-call-iptables is set to 1
sudo modprobe br_netfilter
echo '1' | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables > /dev/null

# Configure iptables
sudo iptables -P FORWARD ACCEPT

# Initialize the Kubernetes cluster with the latest version
# Note: The --pod-network-cidr might need adjustment based on your network setup
sudo kubeadm init --apiserver-advertise-address=192.168.1.100 --pod-network-cidr=10.244.0.0/16

# Configure kubectl for the user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install a CNI plugin (e.g., Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Remove the taint on the master node if you want to run pods on it
kubectl taint nodes --all node-role.kubernetes.io/master-

# Output join command for worker nodes
echo "Join command for worker nodes:"
kubeadm token create --print-join-command

echo "Kubernetes control-plane setup with the latest version completed. You can now join worker nodes with the provided command."
