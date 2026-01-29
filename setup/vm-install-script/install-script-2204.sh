#!/bin/bash
set -e

echo "========= SYSTEM PREP ========="

# Prompt
PS1='\[\e[01;36m\]\u@\h:\w\$\[\033[0m\] '
echo "PS1='$PS1'" >> ~/.bashrc
source ~/.bashrc

# Disable swap (MANDATORY for Kubernetes)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Sysctl params
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

echo "========= APT UPDATE ========="

apt-get update -y
apt-get install -y \
  curl \
  ca-certificates \
  gnupg \
  lsb-release \
  jq \
  vim \
  build-essential \
  python3-pip

pip3 install jc

echo "========= CONTAINERD ========="

apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' \
  > /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo "========= KUBERNETES ========="

KUBE_LATEST=$(curl -L -s https://dl.k8s.io/release/stable.txt | awk -F. '{print $1"."$2}')

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBE_LATEST}/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/${KUBE_LATEST}/deb/ /" \
> /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

echo "========= KUBEADM INIT ========="

kubeadm reset -f

kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --service-cidr=10.96.0.0/16 \
  --skip-token-print

mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

export KUBECONFIG=$HOME/.kube/config

echo "========= CALICO CNI ========="

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

kubectl rollout status daemonset calico-node -n kube-system --timeout=120s

echo "========= UNTAINT CONTROL PLANE ========="

kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

kubectl get nodes -o wide

echo "========= DOCKER (FOR JENKINS BUILDS) ========="

apt-get install -y docker.io

cat <<EOF | tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "storage-driver": "overlay2"
}
EOF

systemctl daemon-reload
systemctl restart docker
systemctl enable docker

echo "========= JAVA & MAVEN ========="

apt-get install -y fontconfig openjdk-21-jre maven
java -version
mvn -v

echo "========= JENKINS ========="

wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update
apt-get install -y jenkins

systemctl enable jenkins
systemctl start jenkins

usermod -aG docker jenkins
echo "jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

echo "========= COMPLETED SUCCESSFULLY ========="
