
apt-get  install -y build-essential ocaml ocamlbuild automake autoconf libtool wget python-is-python3 libssl-dev git cmake perl
apt-get install -y libssl-dev libcurl4-openssl-dev protobuf-compiler libprotobuf-dev debhelper cmake reprepro unzip pkgconf libboost-dev libboost-system-dev protobuf-c-compiler libprotobuf-c-dev lsb-release
git clone https://github.com/intel/linux-sgx.git $GOPATH/src/github.com/linux-sgx
cd $GOPATH/src/github.com/linux-sgx && make preparation
cp external/toolset/ubuntu20.04/*  /usr/local/bin
which ar as ld objcopy objdump ranlib

# make sdk
make sdk_install_pkg



chmod +x ./linux/installer/bin/sgx_linux_x64_sdk_2.18.100.3.bin
./linux/installer/bin/sgx_linux_x64_sdk_2.18.100.3.bin

source /opt/intel/sgxsdk/environment

# make psw
cp /usr/lib/x86_64-linux-gnu/libboost_thread.so.1.71.0 /usr/lib/libboost_thread.so
make deb_psw_pkg

apt-get install -y dpkg-dev
mkdir -p  /var/www/html/repo
find ./linux/installer/deb -iname "*.deb" -exec cp {} /var/www/html/repo \;
cat<<-EOF | tee -a /bin/update-debs
#!/bin/bash
cd /var/www/html/repo
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
EOF
chmod +x /bin/update-debs
/bin/update-debs
cd /var/www/html/repo
apt-ftparchive packages . > Packages
apt-ftparchive release . > Release
gpg --gen-key #gpg --list-keys查看
gpg -a --export C579BF4EAA2568D80FAEF5CCE0642632EF03C674 | apt-key add -  #apt客户端导入公钥
gpg -a --export intel > username.pub  #导出公钥
apt-key add username.pub #导入公钥
gpg -a --export C579BF4EAA2568D80FAEF5CCE0642632EF03C674 | apt-key add -     #其中pub key可用gpg --list-keys查到
gpg --clearsign -o InRelease Release #gpg生成一个明文签名
gpg -abs -o Release.gpg Release #gpg生成一个分离签名

cd /etc/apt/
cp -p sources.list sources.list.bak
cat<< EOF | tee -a sources.list
deb [trusted=yes arch=amd64] file:/var/www/html/repo /
EOF
apt update

apt-get install -y libsgx-launch libsgx-urts libsgx-epid libsgx-quote-ex libsgx-dcap-ql libsgx-enclave-common-dev libsgx-dcap-quote-verify-dev libsgx-dcap-ql-dev libsgx-tdx-logic-dev libtdx-attest-dev 
cp $GOPATH/src/github.com/linux-sgx/external/dcap_source/QuoteGeneration/installer/linux/common/libtdx-attest/output/pkgroot/libtdx-attest/lib/libtdx_attest.so /usr/local/lib
cp $GOPATH/src/github.com/linux-sgx/external/dcap_source/QuoteGeneration/installer/linux/common/libtdx-attest/output/pkgroot/libtdx-attest/lib/libtdx_attest.so /usr/lib

