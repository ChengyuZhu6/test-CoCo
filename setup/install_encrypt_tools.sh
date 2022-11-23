#!/usr/bin/env bash

install_skopeo() {
    git clone https://github.com/containers/skopeo $GOPATH/src/github.com/containers/skopeo
    cd $GOPATH/src/github.com/containers/skopeo && make bin/skopeo
    apt-get install go-md2man
    make install
}
install_attestation-agent() {
    git clone https://github.com/containers/attestation-agent $GOPATH/src/github.com/attestation-agent
    cd $GOPATH/src/github.com/attestation-agent
    make KBC=eaa_kbc && make install
}
install_verdictd() {
    git clone -b 2022-poc https://github.com/jialez0/verdictd $GOPATH/src/github.com/verdictd
    cd $GOPATH/src/github.com/verdictd
    make
    make install
}
install_cosign() {
    wget "https://github.com/sigstore/cosign/releases/download/v1.6.0/cosign-linux-amd64"
    mv cosign-linux-amd64 /usr/local/bin/cosign
    chmod +x /usr/local/bin/cosign
}
