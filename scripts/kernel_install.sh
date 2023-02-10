#!/usr/bin/env bash

#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

version=$1
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-${version}-1.el8.elrepo.x86_64.rpm
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-headers-${version}-1.el8.elrepo.x86_64.rpm
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-core-${version}-1.el8.elrepo.x86_64.rpm
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-devel-${version}-1.el8.elrepo.x86_64.rpm 
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-modules-${version}-1.el8.elrepo.x86_64.rpm
wget --no-check-certificate https://dl.lamp.sh/kernel/el8/kernel-ml-modules-extra-${version}-1.el8.elrepo.x86_64.rpm
yum localinstall kernel-ml-* --allowerasing -y
rm -f kernel-ml-*