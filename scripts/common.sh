#!/usr/bin/env bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

export PATH=$PATH:/usr/local/bin:/usr/local/sbin
export https_proxy=http://proxy.cd.intel.com:911
export http_proxy=http://proxy.cd.intel.com:911
export no_proxy=127.0.0.0/8,localhost,10.0.0.0/8,192.168.0.0/16,192.168.14.0/24,.intel.com,100.64.0.0/10,172.16.0.0/12
export KUBECONFIG=/etc/kubernetes/admin.conf
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export OPERATOR_VERSION="0.3.0"
