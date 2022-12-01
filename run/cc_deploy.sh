#!/usr/bin/env bash

readonly op_ns="confidential-containers-system"
source $(pwd)/run/common.bash
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
        if ! wait_for_process 300 30 "$cmd"; then
            echo "ERROR: $pod pod is not running"
            return 1
        fi
    done
}
remove_cni() {
	local dev="cni0"

	rm -rf /etc/cni/net.d
	ip link set dev "$dev" down || true
	ip link del "$dev" || true
}

remove_flannel() {
	local dev="flannel.1"

	ip link set dev "$dev" down || true
	ip link del "$dev" || true
}
reset_runtime() {
    OPERATOR_VERSION=$(jq -r .file.operatorVersion $TEST_COCO_PATH/../config/test_config.json)
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl delete -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml
    # kubectl delete -f $GOPATH/src/github.com/operator-${OPERATOR_VERSION}/config/samples/ccruntime.yaml
    # kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/deploy/deploy.yaml

    # kubectl delete -f $GOPATH/src/github.com/operator-${OPERATOR_VERSION}/deploy/deploy.yaml
    kubectl delete -k github.com/confidential-containers/operator/config/release?ref=v${OPERATOR_VERSION}

    kubectl delete -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    kubeadm reset -f
    if [ -f /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf ]; then
        rm /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf
        systemctl daemon-reload
        systemctl restart containerd
    fi
    # rm -r $GOPATH/src/github.com/operator-${OPERATOR_VERSION}
    # REGISTRY_CONTAINER=$(docker ps -a | grep "registry" | awk '{print $1}')
    # if [ -n "$REGISTRY_CONTAINER" ]; then
    #     docker stop $REGISTRY_CONTAINER
    #     docker rm $REGISTRY_CONTAINER
    # fi
    # rm -rf ~/.kube/ || true
    # remove_cni

    # remove_flannel
    return 0
}
install_cc() {
    OPERATOR_VERSION=$(jq -r .file.operatorVersion $TEST_COCO_PATH/../config/test_config.json)

    # wget https://github.com/confidential-containers/operator/archive/refs/tags/v${OPERATOR_VERSION}.tar.gz
    # tar -zxf v${OPERATOR_VERSION}.tar.gz -C $GOPATH/src/github.com/
    # rm v${OPERATOR_VERSION}.tar.gz
    MASTER_NAME=$(kubectl get nodes | grep "control" | awk '{print $1}')
    kubectl label node $MASTER_NAME node-role.kubernetes.io/worker=

    # sed -i 's/latest/v0.1.0/g' $GOPATH/src/github.com/operator-0.1.0/deploy/deploy.yaml
    # kubectl apply -f $GOPATH/src/github.com/operator-${OPERATOR_VERSION}/deploy/deploy.yaml
    kubectl apply -k github.com/confidential-containers/operator/config/release?ref=v${OPERATOR_VERSION}
    # kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    test_pod_for_deploy
    if [ $? -eq 1 ]; then
        echo "ERROR: operator deployment failed !"
        return 1
    fi
    # sleep 1
    kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml
    # kubectl apply -f $GOPATH/src/github.com/operator-${OPERATOR_VERSION}/config/samples/ccruntime.yaml
    test_pod_for_ccruntime
    if [ $? -eq 1 ]; then
        echo "ERROR: confidential container runtime deploy failed !"
        return 1
    fi
    return 0
    # kubectl get runtimeclass
}
install_runtime() {
    # kubeadm reset -f
    # swapoff -a
    # modprobe br_netfilter
    # echo 1 >/proc/sys/net/ipv4/ip_forward
    # rm /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf
    # systemctl daemon-reload
    # systemctl restart containerd
    # iptables -P FORWARD ACCEPT
    kubeadm init --cri-socket /run/containerd/containerd.sock --pod-network-cidr=10.244.0.0/16 --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers
    export KUBECONFIG=/etc/kubernetes/admin.conf
    # kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl taint nodes --all node-role.kubernetes.io/master-
    # exit 0
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    install_cc
    if [ $? -eq 1 ]; then
        echo "ERROR: deploy cc runtime falied"
        return 1
    fi
    return 0
}

init_kubeadm() {
    echo "PATH=$PATH"
    local kubeadm_config_file="/etc/kubeadm/kubeadm.conf"
    # Bootstrap the control-plane node.
    kubeadm init --config "${kubeadm_config_file}"

    export KUBECONFIG=/etc/kubernetes/admin.conf

    # TODO: if we want to run as a regular user.
    #mkdir -p $HOME/.kube
    #sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    #sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # TODO: wait node to show up
    #kubectl get nodes
    kubectl apply -f /opt/flannel/kube-flannel.yml
    kubectl taint nodes --all node-role.kubernetes.io/master-
    install_cc
    if [ $? -eq 1 ]; then
        echo "ERROR: deploy cc runtime falied"
        return 1
    fi
}
# init_kubeadm
# main "$@"
# reset_runtime
# install_runtime
