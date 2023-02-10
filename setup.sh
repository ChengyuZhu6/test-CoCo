#!/usr/bin/env bash
OPERATING_SYSTEM_VERSION="Ubuntu"
OPERATOR_PATH="https://github.com/confidential-containers/operator.git"

configure_locally() {
    ## Check OS type
    OPERATING_SYSTEM_VERSION=$(cat /etc/os-release | grep "NAME" | sed -n "1,1p" | cut -d '=' -f2 | cut -d ' ' -f1 | sed 's/\"//g')
    echo "OS: $OPERATING_SYSTEM_VERSION"

    ## Config proxy
    proxy=http://child-prc.intel.com:913
    cat <<EOF | tee -a ~/.bash_profile
proxy=http://child-prc.intel.com:913
export http_proxy=${proxy}
export https_proxy=${proxy}
export no_proxy=127.0.0.0/8,localhost,10.0.0.0/8,192.168.0.0/16,192.168.14.0/24,.intel.com,100.64.0.0/10,172.16.0.0/12
EOF
    source ~/.bash_profile
}
install_dependencies() {
    ## Install the build dependencies
    if [ "$OPERATING_SYSTEM_VERSION" == "Ubuntu" ]; then
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
        if [ $(ls -l /lib/modules | wc -l) -eq 0 ]; then
            CENTOS_KERNEL_VERSION=$(uname -r)
            version=${CENTOS_KERNEL_VERSION%%-*}
            cat <<EOF | tee -a kernel_install.sh
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-${version}-1.el8.elrepo.x86_64.rpm
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-headers-${version}-1.el8.elrepo.x86_64.rpm
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-core-${version}-1.el8.elrepo.x86_64.rpm
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-devel-${version}-1.el8.elrepo.x86_64.rpm 
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-modules-${version}-1.el8.elrepo.x86_64.rpm
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-modules-extra-${version}-1.el8.elrepo.x86_64.rpm
yum localinstall kernel-ml-* --allowerasing -y
rm -f kernel-ml-*
EOF
            chmod +x kernel_install.sh
            ./kernel_install.sh
            rm kernel_install.sh
        fi
        if [ ! -f /etc/fstab]; then
            cat <<EOF | tee -a /etc/fstab
EOF
        fi
        dnf groupinstall -y "Development Tools" jq
        dnf -y install ansible-core
        ansible-galaxy collection install community.docker
    fi

    curl -OL https://go.dev/dl/go1.19.2.linux-amd64.tar.gz
    tar -xzf go1.19.2.linux-amd64.tar.gz -C /usr/local/
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
        git clone $OPERATOR_PATH $GOPATH/src/github.com/operator
    fi
}
# Bootstrap the local machine
bootstrap_local() {
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
Environment="HTTP_PROXY=http://child-prc.intel.com:913"
Environment="HTTPS_PROXY=http://child-prc.intel.com:913"
Environment="NO_PROXY=127.0.0.0/8,localhost,10.0.0.0/8,192.168.0.0/16,192.168.14.0/24,.intel.com,100.64.0.0/10,172.16.0.0/12"
EOF
    done
    systemctl daemon-reload
    clone_operator
    sudo -E PATH="$PATH" bash -c './scripts/operator.sh install'
}

bootstrap_local
