#!/bin/bash

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with 'su -' to become root."
    exit 1
fi

# WARNING: This script has not been tested and is for TESTING PURPOSES ONLY!
# Running this script could potentially modify your system configuration or install software.
# Use at your own risk. Always review scripts before execution, especially in production environments.

# Continue with setup only if the user agrees
echo "WARNING: This script has not been tested and is for TESTING PURPOSES ONLY!"
echo "Running this script at this point WILL modify your system configuration, install a lot of software, and potentially fuck up your system."
echo "Do you wish to continue? (y/n)"
read -p "" -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Script execution cancelled."
    exit 1
fi

# Update system and install necessary packages
apt update
apt install -y apt-transport-https ca-certificates curl

# Check if ufw is installed, if not, install it
if ! command -v ufw &> /dev/null; then
    echo "UFW is not installed. Installing now..."
    apt install -y ufw
fi

# Open necessary ports
ufw allow 22/tcp
ufw allow 6443/tcp
ufw allow 10250/tcp
ufw allow 10251/tcp
ufw allow 10252/tcp
ufw allow 30000:32767/tcp

# Ensure UFW is running and enable it
ufw --force enable

# Disable swap
swapoff -a

# Add Docker repository and install Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io

# Start Docker service
systemctl start docker
systemctl enable docker

# Prepare for containerd installation
# Load necessary kernel modules
cat <<EOF | tee /etc/modules-load.d/containerd.conf 
overlay 
br_netfilter
EOF

modprobe overlay && modprobe br_netfilter

# Set system parameters
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1 
net.bridge.bridge-nf-call-ip6tables = 1 
EOF

sysctl --system

# Install containerd
apt install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Restart containerd service
systemctl restart containerd

# Add Kubernetes apt repository
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

# Update package list to get the latest versions
apt update

# Install the latest stable versions of kubeadm, kubelet, and kubectl
apt install -y kubeadm kubelet kubectl

# Hold Kubernetes packages to prevent auto-updates
apt-mark hold kubeadm kubelet kubectl

# Set up hostname for the control plane
hostnamectl set-hostname k8s-control-plane

# Ensure net.bridge.bridge-nf-call-iptables is set to 1
modprobe br_netfilter
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

# Configure iptables
iptables -P FORWARD ACCEPT

# Function to get the server's IP address
get_server_ip() {
    # This function tries to get the non-loopback IP address of the server
    # Adjust based on your network setup if needed
    local ip=$(ip route get 1 | awk '{print $NF; exit}')
    
    # If the above fails, fallback to other methods
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    # If still no IP, prompt user for input
    if [ -z "$ip" ]; then
        echo "Could not determine server IP automatically. Please enter the server's IP address:"
        read -p "Server IP: " ip
        if [ -z "$ip" ]; then
            echo "No IP provided. Exiting."
            exit 1
        fi
    fi
    
    echo "$ip"
}

# Initialize the Kubernetes cluster with the latest version
# Note: The --pod-network-cidr might need adjustment based on your network setup
SERVER_IP=$(get_server_ip)
kubeadm init --apiserver-advertise-address=$SERVER_IP --pod-network-cidr=10.244.0.0/16

# Asking for the configuration path. My wife told me to be polite, and she is pretty with great boobs. That's the only reason why I am asking your opinion ;)
echo "Enter the path where you want to store Kubernetes configuration (default is /root/.kube):"
read -p "Config path: " CONFIG_PATH
if [ -z "$CONFIG_PATH" ]; then
    CONFIG_PATH="/root/.kube"
fi

# Configure kubectl for the user
mkdir -p "$CONFIG_PATH"
cp -i /etc/kubernetes/admin.conf "$CONFIG_PATH/config"

# Install a CNI plugin (e.g., Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Remove the taint on the master node if you want to run pods on it
kubectl taint nodes --all node-role.kubernetes.io/master-

# Output join command for worker nodes
JOIN_COMMAND=$(kubeadm token create --print-join-command)

echo "Join command for worker nodes:"
echo "$JOIN_COMMAND"

# Ask if user wants to save the join command and token to a file
echo "WARNING: Saving the join token is not very safe. It's better to use it immediately and then discard it."
echo "Do you want to save the join command and token to a file? (y/n)"
read -p "" -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Ask for file location
    echo "Enter the path where you want to save the join command (default is /root/join_command.sh):"
    read -p "Save path: " SAVE_PATH
    if [ -z "$SAVE_PATH" ]; then
        SAVE_PATH="/root/join_command.sh"
    fi

    # Save join command to file
    echo "$JOIN_COMMAND" > "$SAVE_PATH"
    echo "Join command and token have been saved to $SAVE_PATH"
else
    echo "Join command and token were not saved to a file for security reasons."
fi
