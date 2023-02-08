#!/usr/bin/env bash
# Bootstrap the local machine
## Check OS type
OPERATING_SYSTEM_VERSION=$(sudo cat /etc/os-release | grep "NAME" | sed -n "1,1p" | cut -d '=' -f2 | cut -d ' ' -f1 | sed 's/\"//g')
echo "OS: $OPERATING_SYSTEM_VERSION"

## Config proxy
cat <<EOF | tee -a ~/.bash_profile
proxy=http://child-prc.intel.com:913
export http_proxy=$proxy 
export https_proxy=$proxy
export no_proxy=127.0.0.0/8,localhost,10.0.0.0/8,192.168.0.0/16,192.168.14.0/24,.intel.com,100.64.0.0/10,172.16.0.0/12
EOF
source ~/.bash_profile

## Set service proxy

services="
kubelet
containerd
docker
"

for service in ${services}; do

    service_dir="/etc/systemd/system/${service}.service.d/"
    sudo mkdir -p ${service_dir}

  sudo cat << EOF | sudo tee "${service_dir}/proxy.conf"
[Service]
Environment="HTTP_PROXY=http://child-prc.intel.com:913"
Environment="HTTPS_PROXY=http://child-prc.intel.com:913"
Environment="NO_PROXY=127.0.0.0/8,localhost,10.0.0.0/8,192.168.0.0/16,192.168.14.0/24,.intel.com,100.64.0.0/10,172.16.0.0/12"
EOF
done
systemctl daemon-reload


## Install the build dependencies
if [[ "$OPERATING_SYSTEM_VERSION"=="Ubuntu" ]]; then
    sudo apt-get install -y build-essential software-properties-common net-tools git curl jq
    sudo apt-add-repository ppa:ansible/ansible
    sudo apt-get install -y ansible
else
    sudo dnf update -y
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf -y install git curl jq
    sudo dnf -y install ansible-core
fi
./run-local.sh kata-qemu

