#!/usr/bin/env bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

export PATH=$PATH:/usr/local/bin:/usr/local/sbin
export https_proxy=${https_proxy}
export http_proxy=${http_proxy}
export no_proxy=${no_proxy}
export KUBECONFIG=/etc/kubernetes/admin.conf
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export OPERATOR_VERSION="0.3.0"
