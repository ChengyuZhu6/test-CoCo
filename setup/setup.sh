#!/bin/bash

## Check OS type

OPERATING_SYSTEM_VERSION=$(sudo cat /etc/os-release | grep "NAME" | sed -n "1,1p" | cut -d '=' -f2 | cut -d ' ' -f1 | sed 's/\"//g')

## Install tar

if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
    sudo apt-get install -y tar
else
    sudo yum install -y tar
fi
TAR_RESULT=$(tar --version)
if [[ -z "$TAR_RESULT" ]]; then
    echo "tar install failed. The setup process will be exited."
    if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
        sudo apt-get --purge remove -y tar
    else
        sudo yum remove -y tar
    fi
    exit 1
fi

## Install curl

if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
    sudo apt-get install -y curl
else
    sudo yum install -y curl
fi
CURL_RESULT=$(curl --version)
if [[ -z "$CURL_RESULT" ]]; then
    echo "curl install failed. The setup process will be exited."
    if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
        sudo apt-get --purge remove -y curl
    else
        sudo yum remove -y curl
    fi
    exit 1
fi

## Install jq

if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
    sudo apt-get install -y jq
else
    sudo yum install -y jq
fi
JQ_RESULT=$(jq --version)
if [[ -z "$JQ_RESULT" ]]; then
    echo "jq install failed. The setup process will be exited."
    if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
        sudo apt-get --purge remove -y jq
    else
        sudo yum remove -y jq
    fi
    exit 1
fi

## Download and extract Go
echo "Download and extract Go"
GO_VERSION=$(jq -r '.go_version' setup_env.json)
GO_DESTINATION_DIR="/usr/local"
if [ ! -z $(command -v go) ]; then
    if [[ "$(go version)"==*"go${GO_VERSION}"* ]]; then
        echo "Go ${GO_VERSION} already installed"
    else
        echo "Removing $(go version)"
        sudo rm -rf "${GO_DESTINATION_DIR}/go"
    fi
fi
echo "Install GO ${GO_VERSION}"
GO_DOWNLOAD_URL="https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
curl -OL $GO_DOWNLOAD_URL
if [ ! -d ${GO_DESTINATION_DIR} ]; then
    mkdir -p "${GO_DESTINATION_DIR}"
fi
sudo tar -C "${GO_DESTINATION_DIR}" -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
rm -rf go${GO_VERSION}.linux-amd64.tar.gz
echo "Create link to go binary"
ln -s /usr/local/go/bin/go /usr/local/bin/go

## Install the operator-sdk
echo "Install the operator-sdk"
OPERATOR_SDK_VERSION=$(jq -r '.operator_sdk_version' setup_env.json)
OPERATOR_SDK_URL="https://github.com/operator-framework/operator-sdk/releases/download/${OPERATOR_SDK_VERSION}/operator-sdk_linux_amd64"
OPERATOR_DESTINATION_DIR="/usr/local/bin/"
curl -OL $OPERATOR_SDK_URL
mv operator-sdk_linux_amd64 $OPERATOR_DESTINATION_DIR

## Install Docker
echo "Install Docker"

echo "Check whether docker is installed"
if [ ! -z $(command -v docker ) ]; then
    echo "docker is installed"
fi
### Install docker dependencies
echo "- Install docker dependencies"
if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    echo "Add docker repo GPG key"
    curl -fsSLo /etc/apt/trusted.gpg.d/docker.gpg https://download.docker.com/linux/ubuntu/gpg
    echo "Add docker repo"
    CODENAME=$(lsb_release -cs)
    echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" | sudo tee -a /etc/apt/sources.list
    sudo apt-get update
    echo "- Install docker"
    sudo apt-get install -y containerd.io docker-ce docker-ce-cli
    # sudo groupadd docker
    # sudo usermod -aG docker $(whoami)
    # sudo newgrp docker
else
    sudo yum install -y yum-utils
    echo "Add docker yum repo"
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    echo "- Install docker"
    sudo yum install -y containerd.io docker-ce docker-ce-cli
    sudo systemctl start docker
fi

echo "Install and configure containerd"
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
echo "Check whether containerd is installed"
CONTAINERD_RES=$(systemctl list-unit-files | grep containerd)
if [ -z "$CONTAINERD_RES" ]; then
    echo "containerd is not installed"
    exit 1
fi
containerd config default >/etc/containerd/config.toml
systemctl restart containerd

echo "Install kubeadm"
 cni_home="/opt/cni"
 cni_version="v1.1.1"
 flannel_home="/opt/flannel"
 flannel_version="v0.19.1"
 kubeadm_cri_runtime_socket="/run/containerd/containerd.sock"
 kubeadm_conf_dir="/etc/kubeadm"
 kubelet_bin="/usr/local/bin/kubelet"
 kubelet_service_dir="/etc/systemd/system/kubelet.service.d"
 kubelet_service_file="/etc/systemd/system/kubelet.service"
 kubelet_cgroup_driver="cgroupfs"

echo "- Install kubeadm required packages"
if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
    sudo apt-get install -y conntrack socat
else
    sudo yum install -y conntrack socat
fi

echo "- Create CNI home directory"

if [ ! -d $cni_home ]; then
    mkdir -p $cni_home/bin
fi

echo "- Install CNI plugins"
curl -OL "https://github.com/containernetworking/plugins/releases/download/$cni_version/cni-plugins-linux-amd64-$cni_version.tgz"
sudo tar -C "$cni_home/bin" -zxf cni-plugins-linux-amd64-$cni_version.tgz

echo "- Install crictl"
K8S_VERSION=$(jq -r '.k8s_version' setup_env.json)

curl -OL "https://github.com/kubernetes-sigs/cri-tools/releases/download/$K8S_VERSION/crictl-$K8S_VERSION-linux-amd64.tar.gz"
sudo tar -C /usr/local/bin/ -zxf crictl-$K8S_VERSION-linux-amd64.tar.gz

echo "- Install kube binaries"

curl -OL "https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/kubeadm"
curl -OL "https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/kubelet"
curl -OL "https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/kubectl"
sudo chmod +x kubeadm
sudo cp kubeadm /usr/local/bin/
sudo chmod +x kubelet
sudo cp kubelet /usr/local/bin/
sudo chmod +x kubectl
sudo cp kubectl /usr/local/bin/

echo "- Disable swap"
if [ ! -z "$(swapon --show)" ]; then
    swapoff --all
fi
echo "- Disable swap in fstab"
sudo sed -i '/ swap / s/^/#/' /etc/fstab
echo "- Create kubelet service"
cat <<-EOF >$kubelet_service_file
# Copied from https://raw.githubusercontent.com/kubernetes/release/v0.4.0/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service
#
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
echo "- Create kubelet.service.d directory"
if [ ! -d $kubelet_service_dir ]; then
    mkdir -p $kubelet_service_dir
fi
echo "- Create kubeadm service config"
cat <<-EOF >$kubelet_service_dir/10-kubeadm.conf
# Copied and modified from https://raw.githubusercontent.com/kubernetes/release/v0.4.0/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
echo "- Create kubeadm configuration directory"

if [ ! -d $kubeadm_conf_dir ]; then
    sudo mkdir -p $kubeadm_conf_dir
fi

echo "- Create kubeadm configuration file"
cat <<-EOF >$kubeadm_conf_dir/kubeadm.conf
# Copied and modified from https://github.com/kata-containers/tests/blob/main/integration/kubernetes/kubeadm/config.yaml
#
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix://$kubeadm_cri_runtime_socket
  imagePullPolicy: IfNotPresent
  kubeletExtraArgs:
    allowed-unsafe-sysctls: kernel.msg*,kernel.shm.*,net.*
    v: "4"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: $K8S_VERSION
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
apiServer:
  extraArgs:
    feature-gates: PodOverhead=true
  timeoutForControlPlane: 4m0s
imageRepository: k8s.gcr.io
scheduler:
  extraArgs:
    feature-gates: PodOverhead=true
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: $kubelet_cgroup_driver
featureGates:
  PodOverhead: true
systemReserved:
  cpu: 500m
  memory: 256Mi
kubeReserved:
  cpu: 500m
  memory: 256Mi
EOF

echo "- Reload systemd configuration"
sudo systemctl daemon-reload
echo "- Start kubelet service"
sudo systemctl enable kubelet.service
sudo systemctl start kubelet.service

echo "- Create flannel home directory"

if [ ! -d $flannel_home ]; then
    sudo mkdir -p $flannel_home
fi

echo "- Create flannel deployment file"

cat <<-EOF >$flannel_home/kube-flannel.yml
# Copied and modified from https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
---
kind: Namespace
apiVersion: v1
metadata:
  name: kube-flannel
  labels:
    pod-security.kubernetes.io/enforce: privileged
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: flannel
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-flannel
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-flannel
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-cfg
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-flannel-ds
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
spec:
  selector:
    matchLabels:
      app: flannel
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
      hostNetwork: true
      priorityClassName: system-node-critical
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni-plugin
       #image: flannelcni/flannel-cni-plugin:v1.1.0 for ppc64le and mips64le (dockerhub limitations may apply)
        image: docker.io/rancher/mirrored-flannelcni-flannel-cni-plugin:v1.1.0
        command:
        - cp
        args:
        - -f
        - /flannel
        - /opt/cni/bin/flannel
        volumeMounts:
        - name: cni-plugin
          mountPath: /opt/cni/bin
      - name: install-cni
       #image: flannelcni/flannel:v0.19.1 for ppc64le and mips64le (dockerhub limitations may apply)
        image: docker.io/rancher/mirrored-flannelcni-flannel:v0.19.1
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
       #image: flannelcni/flannel:v0.19.1 for ppc64le and mips64le (dockerhub limitations may apply)
        image: docker.io/rancher/mirrored-flannelcni-flannel:v0.19.1
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: EVENT_QUEUE_DEPTH
          value: "5000"
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
        - name: xtables-lock
          mountPath: /run/xtables.lock
      volumes:
      - name: run
        hostPath:
          path: /run/flannel
      - name: cni-plugin
        hostPath:
          path: /opt/cni/bin
      - name: cni
        hostPath:
          path: /etc/cni/net.d
      - name: flannel-cfg
        configMap:
          name: kube-flannel-cfg
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
EOF

echo "Start a local docker registry"
 local_registry_port=5000
 local_registry_name=local-registry

if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
    sudo apt-get install -y python3-pip
fi
sudo docker run -d -p $local_registry_port:$local_registry_port --restart=always --name $local_registry_name registry
REGISTRY_CONTAINER=$(docker ps -a | grep "$local_registry_name" | awk '{print $1}')
if [ -n "$REGISTRY_CONTAINER" ]; then
    docker stop $REGISTRY_CONTAINER
    docker rm $REGISTRY_CONTAINER
fi

echo "Install bats from sources"
which bats 
BATS_REPO="github.com/bats-core/bats-core"
GO111MODULE="auto" go get -d "${BATS_REPO}" || true
pushd "${GOPATH}/src/${BATS_REPO}"
sudo -E PATH=$PATH sh -c "./install.sh /usr"
popd

#### Internal
echo "Configure proxy"

services="
kubelet
containerd
docker
"

for service in ${services}; do

    service_dir="/etc/systemd/system/${service}.service.d/"
    if [ ! -d ${service_dir} ]; then
        sudo mkdir -p ${service_dir}
    fi
    cat <<EOF | sudo tee "${service_dir}/proxy.conf"
[Service]
Environment="HTTP_PROXY=http://child-prc.intel.com:913"
Environment="HTTPS_PROXY=http://child-prc.intel.com:913"
Environment="NO_PROXY=127.0.0.0/8,localhost,10.0.0.0/8,192.168.0.0/16,192.168.14.0/24,.intel.com,100.64.0.0/10,172.16.0.0/12"
EOF
done
sudo systemctl daemon-reload

### Install Operator
echo "Install Operator"

readonly op_ns="confidential-containers-system"
wait_for_process() {
    wait_time="$1"
    sleep_time="$2"
    cmd="$3"
    while [ "$wait_time" -gt 0 ]; do
        if eval "$cmd"; then
            return 0
        else
            sleep "$sleep_time"
            wait_time=$((wait_time - sleep_time))
        fi
    done
    return 1
}
test_pod_for_deploy() {
    local cmd="kubectl get pods -n "$op_ns" --no-headers |"
    cmd+="egrep -q cc-operator-controller-manager.*'\<Running\>'"
    if ! wait_for_process 120 10 "$cmd"; then
        echo "ERROR: operator-controller-manager pod is not running"
        return 1
    fi
}
test_pod_for_ccruntime() {
    local pod=""
    local cmd=""
    for pod in cc-operator-daemon-install cc-operator-pre-install-daemon; do
        cmd="kubectl get pods -n "$op_ns" --no-headers |"
        cmd+="egrep -q ${pod}.*'\<Running\>'"
        if ! wait_for_process 180 30 "$cmd"; then
            echo "ERROR: $pod pod is not running"
            return 1
        fi
    done
}
reset_runtime() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl delete -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml
    kubectl delete -k github.com/confidential-containers/operator/config/release?ref=v0.2.0

    kubectl delete -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    kubeadm reset -f
    return 0
}
install_cc() {
    MASTER_NAME=$(kubectl get nodes | grep "control" | awk '{print $1}')
    kubectl label node $MASTER_NAME node-role.kubernetes.io/worker=

    kubectl apply -k github.com/confidential-containers/operator/config/release?ref=v0.2.0
    # kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    test_pod_for_deploy
    if [ $? -eq 1 ]; then
        echo "ERROR: operator deployment failed !"
        return 1
    fi
    kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml
    test_pod_for_ccruntime
    if [ $? -eq 1 ]; then
        echo "ERROR: confidential container runtime deploy failed !"
        return 1
    fi
    kubectl get runtimeclass
}

init_kubeadm() {
    local kubeadm_config_file="/etc/kubeadm/kubeadm.conf"
    # Bootstrap the control-plane node.
    kubeadm init --config "${kubeadm_config_file}"

    export KUBECONFIG=/etc/kubernetes/admin.conf

    # TODO: if we want to run as a regular user.
    # mkdir -p $HOME/.kube
    # sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    # sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # TODO: wait node to show up
    kubectl get nodes
    kubectl apply -f /opt/flannel/kube-flannel.yml
    kubectl taint nodes --all node-role.kubernetes.io/master-
    local label="node-role.kubernetes.io/control-plane"
    if [ ! $(kubectl get node "$(hostname| tr A-Z a-z)" -o=json|jq -r ".metadata.labels" |
        grep -q "$label") ]; then
        # kubectl label node "$(hostname| tr A-Z a-z)" "$label="
        kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    fi
    install_cc
    if [ $? -eq 1 ]; then
        echo "ERROR: deploy cc runtime falied"
        return 1
    fi
}

init_kubeadm
