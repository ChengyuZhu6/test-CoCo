#!/usr/bin/env bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

export PATH=$PATH:/usr/local/bin:/usr/local/sbin
export KUBECONFIG=/etc/kubernetes/admin.conf
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export OPERATOR_VERSION="0.3.0"

clone_operator() {
    if [ ! -d $GOPATH/src/github.com/operator ]; then
        git clone $OPERATOR_PATH $GOPATH/src/github.com/operator --depth 1 --branch v$OPERATOR_VERSION
    fi
}
