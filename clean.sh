#!/usr/bin/env bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
script_dir="$(dirname "$(readlink -f "$0")")"
source $script_dir/scripts/common.sh
main() {
    sudo -E PATH="$PATH" bash -c './scripts/operator.sh uninstall'
}
main "$@"
