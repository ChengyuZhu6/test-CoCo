#!/usr/bin/env bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
main() {
    if [ $# -gt 0 ]; then
        export OPERATOR_VERSION=$1
    else
        export OPERATOR_VERSION="0.3.0"
    fi
    sudo -E PATH="$PATH" bash -c './scripts/operator.sh uninstall'
}
main "$@"