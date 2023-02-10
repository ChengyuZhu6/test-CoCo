#!/usr/bin/env bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

OPERATING_SYSTEM_VERSION="ubuntu"
OPERATOR_PATH="https://github.com/confidential-containers/operator.git"
OPERATOR_VERSION="V0.3.0"
configure_locally() {
    ## Check OS type
    source /etc/os-release
    OPERATING_SYSTEM_VERSION=$ID
    echo "OS: $OPERATING_SYSTEM_VERSION"

    ## Config proxy
    source ~/scripts/private/intel_proxy.conf
}
install_dependencies() {
    ## Install the build dependencies
    if [ "$OPERATING_SYSTEM_VERSION" == "ubuntu" ]; then
        apt-get update -y
        apt-get install -y expect <<ESXU
    6
    70
ESXU
        apt-get install -y systemd sudo
        apt-get install -y build-essential software-properties-common net-tools git curl jq expect wget tar iproute2 locales open-iscsi
        apt-get install --reinstall -y linux-image-$(uname -r)
        if [ ! $(command -v ansible-playbook >/dev/null) ]; then
            /usr/bin/expect <<-EOF
        spawn apt-add-repository ppa:ansible/ansible
        expect "Press [ENTER] to continue or Ctrl-c to cancel."
        send "\n"
        expect eof
EOF
            apt-get install -y ansible
        fi
    else
        dnf update -y
        if [ $(ls -l /lib/modules | wc -l) -le 1 ]; then
            CENTOS_KERNEL_VERSION=$(uname -r)
            version=${CENTOS_KERNEL_VERSION%%-*}
            ./scripts/kernel_install.sh $version
            mv /lib/modules/$version-1.el8.elrepo.x86_64 /lib/modules/$CENTOS_KERNEL_VERSION
        fi
        if [ ! -f /etc/fstab ]; then
            cat <<EOF | tee -a /etc/fstab
EOF
        fi
        dnf groupinstall -y "Development Tools" jq
        dnf -y install ansible-core
        ansible-galaxy collection install community.docker
    fi

    if [ ! -f go1.19.2.linux-amd64.tar.gz ]; then
        curl -OL https://go.dev/dl/go1.19.2.linux-amd64.tar.gz
        tar -xzf go1.19.2.linux-amd64.tar.gz -C /usr/local/
    fi
    GOROOT=/usr/local/go
    cat <<EOF | tee -a ~/.bash_profile
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin
EOF
    source ~/.bash_profile
    go version
    rm go1.19.2.linux-amd64.tar.gz
}
clone_operator() {
    if [ ! -d $GOPATH/src/github.com/operator ]; then
        git clone $OPERATOR_PATH $GOPATH/src/github.com/operator --depth 1 --branch v0.3.0
    fi
}
# Bootstrap the local machine
bootstrap_local() {
    if [ $# -gt 0 ]; then

        OPERATOR_VERSION=$1
    fi

    configure_locally
    install_dependencies
    ## Set service proxy
    services="
kubelet
containerd
docker
"
    for service in ${services}; do

        service_dir="/etc/systemd/system/${service}.service.d/"
        mkdir -p ${service_dir}

        cat <<EOF | tee "${service_dir}/proxy.conf"
[Service]
Environment="HTTP_PROXY=${http_proxy}"
Environment="HTTPS_PROXY=${https_proxy}"
Environment="NO_PROXY=${no_proxy}"
EOF
    done
    systemctl daemon-reload
    clone_operator
    sudo -E PATH="$PATH" bash -c './scripts/operator.sh install'
}

bootstrap_local
