#!/usr/bin/env bats

load ../run/lib.sh

test_tag="[cc][agent][kubernetes][containerd]"

setup() {
	start_date=$(date +"%Y-%m-%d %H:%M:%S")

}


@test "Test install operator" {
	init_kubeadm
	echo "Prepare containerd for Confidential Container"

	read_config
	echo "Reconfigure Kata Containers"
	#clear_kernel_params
	switch_image_service_offload on
	add_kernel_params "agent.log=debug"
	add_kernel_params "debug_console_enabled=true"
	#run_registry
	get_certs_from_remote
	$TEST_COCO_PATH/../run/losetup-crt.sh $ROOTFS_IMAGE_PATH c
	#$TEST_COCO_PATH/../run/losetup-crt.sh "/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest.image" c
	#$TEST_COCO_PATH/../run/losetup-crt.sh "/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest-tdx.image" c
}



