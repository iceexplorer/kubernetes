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

# Check if UFW is installed, and install it if missing
if ! command -v ufw &> /dev/null; then
    echo "UFW is not installed. Installing now..."
    apt install -y ufw
fi

# Open required ports first
echo "Configuring UFW rules..."
REQUIRED_PORTS=("22/tcp" "6443/tcp" "10250/tcp" "10251/tcp" "10252/tcp" "10255/tcp" "2379/tcp" "2380/tcp" "30000:32767/tcp")
for port in "${REQUIRED_PORTS[@]}"; do
    ufw allow $port
done

# Enable UFW only after ensuring ports are open
if ! systemctl is-active --quiet ufw; then
    echo "Enabling UFW..."
    ufw --force enable
else
    echo "UFW is already enabled."
fi

# Disable swap
swapoff -a

# Comment out the swap entry in /etc/fstab, but only if it's not already commented
sed -i.bak '/^[^#].*\bswap\b/s/^/#/' /etc/fstab

# Set up hostname for the control-plane
CURRENT_HOSTNAME=$(hostname)

echo "The current hostname of this server is: $CURRENT_HOSTNAME"
echo "Do you want to use this hostname? (y/n)"
read -p "" -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Enter a custom hostname for this control-plane:"
    read -p "Hostname: " MASTER_HOSTNAME
else
    MASTER_HOSTNAME=$CURRENT_HOSTNAME
fi

hostnamectl set-hostname "$MASTER_HOSTNAME"

# Add Docker repository and install Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
# Check if Docker is already installed and the version is compatible
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    REQUIRED_VERSION="5.0"  # Adjust to the desired Docker version
    if [[ $(echo -e "$DOCKER_VERSION\n$REQUIRED_VERSION" | sort -V | head -n 1) == "$REQUIRED_VERSION" ]]; then
        echo "Docker version $DOCKER_VERSION is already installed and compatible. Skipping installation."
    else
        echo "Docker version is outdated or incompatible. Installing the latest version."
        apt install -y docker-ce docker-ce-cli
    fi
else
    echo "Docker not found. Installing the latest version."
    apt install -y docker-ce docker-ce-cli
fi

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
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# Update package list to get the latest versions
apt update

# Install the latest stable versions of kubeadm, kubelet, and kubectl
apt install -y kubeadm kubelet kubectl

# Hold Kubernetes packages to prevent auto-updates
apt-mark hold kubeadm kubelet kubectl

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
# Initialize the Kubernetes cluster with the latest version
SERVER_IP=$(get_server_ip)

# Ask if load balancer will be used
echo "Do you plan to use a load balancer now or in the future? (y/n)"
read -p "" -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Please provide load balancer details or configuration when ready."
else
    # Add commented-out load balancer configuration for future use
    echo "Load balancer configuration will be added but not implemented."
    # Example: kubeadm init --control-plane-endpoint "<load-balancer-ip>:6443" ...
fi

kubeadm init --apiserver-advertise-address=$SERVER_IP --pod-network-cidr=10.244.0.0/16

# Generate admin kubeconfig for kubectl
kubeadm init phase kubeconfig admin

# Ensure /var/lib/kubelet exists
if [ ! -d "/var/lib/kubelet" ]; then
    echo "/var/lib/kubelet directory is missing, creating it..."
    mkdir -p /var/lib/kubelet
    chown -R root:root /var/lib/kubelet
fi

# Ensure time synchronization
if ! systemctl is-active --quiet chrony; then
    echo "Time synchronization is not active. Installing chrony..."
    apt-get install -y chrony
    systemctl enable --now chrony
fi

# Asking for the configuration path.
echo "Enter the path where you want to store Kubernetes configuration (default is /root/.kube):"
read -p "Config path: " CONFIG_PATH
if [ -z "$CONFIG_PATH" ]; then
    CONFIG_PATH="/root/.kube"
fi

# Configure kubectl for the user
mkdir -p "$CONFIG_PATH"
chown $(id -u):$(id -g) "$CONFIG_PATH"
cp -i /etc/kubernetes/admin.conf "$CONFIG_PATH/config"


# Install a CNI plugin (e.g., Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Ask if user wants to use the control plane for pods
echo "Do you want to run pods on the control-plane node? (y/n)"
read -p "" -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl taint nodes --all node-role.kubernetes.io/master-
else
    echo "Control-plane node will not be tainted."
fi

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
