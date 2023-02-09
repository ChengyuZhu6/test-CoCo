#!/usr/bin/env bash
# Bootstrap the local machine
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
## Install the build dependencies
if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
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
    dnf groupinstall -y "Development Tools"
    dnf -y install git curl jq
    dnf -y install ansible-core
fi

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

curl -OL https://go.dev/dl/go1.19.2.linux-amd64.tar.gz
tar -xzf go1.19.2.linux-amd64.tar.gz -C /usr/local/
GOROOT=/usr/local/go
cat<< EOF |tee -a ~/.bash_profile
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin
EOF
source ~/.bash_profile
go version

git clone -b v0.3.0 https://github.com/ChengyuZhu6/test-CoCo.git $GOPATH/src/github.com/test-CoCo
cd $GOPATH/src/github.com/test-CoCo/Install
./run-local.sh kata-qemu
