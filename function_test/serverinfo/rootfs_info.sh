#!/usr/bin/env bash

kernel_version="$(/opt/confidential-containers/bin/kata-runtime kata-env --json | jq -r .Kernel.Path | cut -d '/' -f6)"
echo "Kernel: $kernel_version"
runtime_version=$(/opt/confidential-containers/bin/kata-runtime kata-env --json | jq -r .Runtime.Version | grep Semver | cut -d'"' -f4)
echo "Runtime: $runtime_version"
hypervisor_version=$(/opt/confidential-containers/bin/kata-runtime kata-env --json | jq -r .Hypervisor.Version | sed -n "1,1p")
echo "Hypervisor: $hypervisor_version"
