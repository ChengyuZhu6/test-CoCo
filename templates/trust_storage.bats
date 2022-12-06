#!/usr/bin/env bats

load ../run/lib.sh

test_tag="[cc][agent][kubernetes][containerd]"

setup() {
	start_date=$(date +"%Y-%m-%d %H:%M:%S")

}

@test "Test install open-local" {
	#skip
	#install_runtime
	# "Prepare containerd for Confidential Container"

	read_config
	echo "Reconfigure Kata Containers"

	##switch_image_service_offload on
	#add_kernel_params "agent.log=debug"
	##add_kernel_params "debug_console_enabled=true"
	#run_registry

	#$TEST_COCO_PATH/../run/losetup-crt.sh $ROOTFS_IMAGE_PATH c
	export KUBECONFIG=/etc/kubernetes/admin.conf
	if [ ! -d $GOPATH/open-local ]; then
		curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
		git clone https://github.com/Zhuchengyu04/open-local.git "$GOPATH/open-local"
		helm install open-local $GOPATH/open-local/helm
		#sleep 10
	fi
	#if ! kubernetes_wait_open_local_be_ready; then
	#	helm delete open-local
	#	rm -r $GOPATH/open-local
	#	return 1
	#fi
}
