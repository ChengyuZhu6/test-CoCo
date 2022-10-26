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
        if ! wait_for_process 600 30 "$cmd"; then
            echo "ERROR: $pod pod is not running"
            return 1
        fi
    done
}
reset_runtime() {
    # kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml

    kubectl delete -f $GOPATH/src/github.com/operator-0.1.0/config/samples/ccruntime.yaml
    # kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/deploy/deploy.yaml

    kubectl delete -f $GOPATH/src/github.com/operator-0.1.0/deploy/deploy.yaml
    kubectl delete -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    kubeadm reset -f
    if [ -f /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf ]; then
        rm /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf
        systemctl daemon-reload
        systemctl restart containerd
    fi
}
install_cc() {
    OPERATOR_VERSION=$(jq -r .file.operator_version test_config.json)

    wget https://github.com/confidential-containers/operator/archive/refs/tags/${OPERATOR_VERSION}.tar.gz
    tar -zxf v0.1.0.tar.gz -C $GOPATH/src/github.com/
    rm v0.1.0.tar.gz
    MASTER_NAME=$(kubectl get nodes | grep "control" | awk '{print $1}')
    kubectl label node $MASTER_NAME node-role.kubernetes.io/worker=
    # kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/deploy/deploy.yaml

    kubectl apply -f $GOPATH/src/github.com/operator-0.1.0/deploy/deploy.yaml

    # kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    test_pod_for_deploy
    if [ $? -eq 1 ]; then
        echo "ERROR: operator deployment failed !"
        return 1
    fi
    sleep 1
    # kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml

    kubectl apply -f $GOPATH/src/github.com/operator-0.1.0/config/samples/ccruntime.yaml
    # kubectl apply -f ./ccruntime.yaml
    test_pod_for_ccruntime
    if [ $? -eq 1 ]; then
        echo "ERROR: confidential container runtime deploy failed !"
        return 1
    fi
    return 0
    # kubectl get runtimeclass
}
install_runtime() {
    kubeadm reset -f
    swapoff -a
    modprobe br_netfilter
    echo 1 >/proc/sys/net/ipv4/ip_forward
    # rm /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf
    systemctl daemon-reload
    systemctl restart containerd
    iptables -P FORWARD ACCEPT
    kubeadm init --cri-socket /run/containerd/containerd.sock --pod-network-cidr=10.244.0.0/16 --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers
    # exit 0
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl taint nodes --all node-role.kubernetes.io/master-
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    install_cc
    if [ $? -eq 1 ]; then
        echo "ERROR: deploy cc runtime falied"
        return 1
    fi
    return 0
}
# main "$@"
# reset_runtime
# reset_runtime
install_runtime