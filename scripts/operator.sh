#!/bin/bash
#
# Copyright Confidential Containers Contributors
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

script_dir="$(dirname "$(readlink -f "$0")")"
project_dir="$(readlink -f ${script_dir}/../..)"
OPERATOR_VERSION=0.3.0
OPERATOR_INSTALL_PATH="$GOPATH/src/github.com/operator/tests/e2e"
source "${OPERATOR_INSTALL_PATH}/lib.sh"

# The operator namespace.
readonly op_ns="confidential-containers-system"

# Install the operator.
#
install_operator() {

	# The node should be 'worker' labeled
	local label="node-role.kubernetes.io/worker"
	if ! kubectl get node "$(hostname | tr A-Z a-z)" -o jsonpath='{.metadata.labels}' |
		grep -q "$label"; then
		kubectl label node "$(hostname | tr A-Z a-z)" "$label="
	fi

	kubectl apply -k github.com/confidential-containers/operator/config/release?ref=v${OPERATOR_VERSION}

	# Wait the operator controller to be running.
	local controller_pod="cc-operator-controller-manager"
	local cmd="kubectl get pods -n "$op_ns" --no-headers |"
	cmd+="egrep -q ${controller_pod}.*'\<Running\>'"
	if ! wait_for_process 120 10 "$cmd"; then
		echo "ERROR: ${controller_pod} pod is not running"

		local pod_id="$(get_pods_regex $controller_pod $op_ns)"
		echo "DEBUG: Pod $pod_id"
		debug_pod "$pod_id" "$op_ns"

		return 1
	fi
}

# Install the CC runtime.
#
install_ccruntime() {
	local runtimeclass="${RUNTIMECLASS:-kata-qemu}"

	kubectl create -k github.com/confidential-containers/operator/config/samples/ccruntime/default?ref=v${OPERATOR_VERSION}

	local pod=""
	local cmd=""
	for pod in cc-operator-daemon-install cc-operator-pre-install-daemon; do
		cmd="kubectl get pods -n "$op_ns" --no-headers |"
		cmd+="egrep -q ${pod}.*'\<Running\>'"
		if ! wait_for_process 600 30 "$cmd"; then
			echo "ERROR: $pod pod is not running"

			local pod_id="$(get_pods_regex $pod $op_ns)"
			echo "DEBUG: Pod $pod_id"
			debug_pod "$pod_id" "$op_ns"

			return 1
		fi
	done

	# Check if the runtime is up.
	# There could be a case where it is not even if the pods above are running.
	cmd="kubectl get runtimeclass | grep -q ${runtimeclass}"
	if ! wait_for_process 300 30 "$cmd"; then
		echo "ERROR: runtimeclass ${runtimeclass} is not up"
		return 1
	fi
}

# Uninstall the operator and ccruntime.
#
uninstall_operator() {
	export KUBECONFIG=/etc/kubernetes/admin.conf

	kubectl delete -k github.com/confidential-containers/operator/config/samples/ccruntime/default?ref=v${OPERATOR_VERSION}
	kubectl delete -k github.com/confidential-containers/operator/config/release?ref=v${OPERATOR_VERSION}
	clean_env
}

usage() {
	cat <<-EOF
		Utility to install/uninstall the operator.

		Use: $0 [-h|--help] [command], where:
		-h | --help : show this usage
		command : optional command (install by default). Can be:
		 "install": install only,
		 "uninstall": uninstall the operator.
	EOF
}
set_env() {
	if ! command -v ansible-playbook >/dev/null; then
		echo "ERROR: ansible-playbook is required to run this script."
		exit 1
	fi

	export "PATH=$PATH:/usr/local/bin"

	pushd "$script_dir" >/dev/null
	echo "INFO: Bootstrap the local machine"
	step_bootstrap_env=1
	# ansible-playbook -i localhost, -c local --tags untagged $OPERATOR_INSTALL_PATH/ansible/main.yml

	echo "INFO: Bring up the test cluster"
	step_start_cluster=1
	sudo -E PATH="$PATH" bash -c "./init_k8s.sh"
	export KUBECONFIG=/etc/kubernetes/admin.conf

}
clean_env() {
	sudo -E PATH="$PATH" bash -c "$OPERATOR_INSTALL_PATH/cluster/down.sh"
}
main() {
	ccruntime_overlay="default"
	if [ "$(uname -m)" = "s390x" ]; then
		ccruntime_overlay="s390x"
	fi

	if [ $# -eq 0 ]; then
		echo "INFO: Install the operator"
		set_env
		install_operator
		install_ccruntime
	else
		case $1 in
		-h | --help) usage && exit 0 ;;
		install)
			echo "INFO: Install the operator"
			set_env
			install_operator
			install_ccruntime
			;;
		uninstall)
			echo "INFO: Uninstall the operator"
			uninstall_operator
			;;
		*)
			echo "Unknown command '$1'"
			usage && exit 1
			;;
		esac
	fi
}

main "$@"
