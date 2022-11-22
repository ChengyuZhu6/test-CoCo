source ./run/lib.sh
source ./run/cc_deploy.sh

test_tag="[cc][agent][kubernetes][containerd]"

setup() {
	start_date=$(date +"%Y-%m-%d %H:%M:%S")

}
new_pod_config() {
	local base_config="$1"
	local image="$2"
	local runtimeclass="$3"
	local registryimage="$4"

	local new_config=$(mktemp "$TEST_COCO_PATH/../fixtures/$(basename ${base_config}).XXX")
	IMAGE="$image" RUNTIMECLASS="$runtimeclass" REGISTRTYIMAGE="$registryimage" envsubst <"$base_config" >"$new_config"
	echo "$new_config"
}
Test_install_operator() {
	install_runtime
	echo "Prepare containerd for Confidential Container"

	read_config
	echo "Reconfigure Kata Containers"

	switch_image_service_offload on
	add_kernel_params "agent.log=debug"
	add_kernel_params "debug_console_enabled=true"
	# run_registry

	# $TEST_COCO_PATH/../run/losetup-crt.sh $ROOTFS_IMAGE_PATH c
}
Test_unencrypted_unsigned_image() {

	for IMAGE in ${EXAMPLE_IMAGE_LISTS[@]}; do
		pod_config="$(new_pod_config $TEST_COCO_PATH/../fixtures/unsigned-unprotected-pod-config.yaml.in "$IMAGE" "$RUNTIMECLASS" "$REGISTRY_NAME/$IMAGE:$VERSION")"

		unencrypted_signed_image_from_unprotected_registry $pod_config
		rm $pod_config
	done
}
Test_trust_storage() {
	if [ ! -d $GOPATH/open-local ]; then
		curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
		git clone https://github.com/Zhuchengyu04/open-local.git "$GOPATH/open-local"
		helm install open-local $GOPATH/open-local/helm
		sleep 5
	fi
	if ! kubernetes_wait_open_local_be_ready; then
		helm delete open-local
		rm -r $GOPATH/open-local
		return 1
	fi
	pod_config="$(new_pod_config_normal $TEST_COCO_PATH/../fixtures/sts-lvm.yaml.in "ubuntu" "kata-qemu" "zcy-Z390-AORUS-MASTER.sh.intel.com/ubuntu:latest")"

	create_test_pod $pod_config
	POD_NAME=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
	if ! kubernetes_wait_cc_pod_be_running "${POD_NAME}"; then
		kubectl delete -f $pod_config
		kubectl delete pvc "html-${POD_NAME}"
		rm $pod_config
		helm delete open-local
		rm -r $GOPATH/open-local
		return 1
	fi
	checkout_snapshot_yaml $TEST_COCO_PATH/../fixtures/snapshot.yaml ubuntu
	kubectl apply -f $TEST_COCO_PATH/../fixtures/snapshot.yaml

	if ! kubernetes_wait_cc_snapshot_be_ready; then
		kubectl delete -f $TEST_COCO_PATH/../fixtures/snapshot.yaml
		kubectl delete -f $pod_config
		kubectl delete pvc "html-${POD_NAME}"
		rm $pod_config
		helm delete open-local
		rm -r $GOPATH/open-local
		return 1
	fi
	pod_config_snap="$(new_pod_config_normal $TEST_COCO_PATH/../fixtures/sts-lvm-snap.yaml.in "ubuntu" "kata-qemu" "zcy-Z390-AORUS-MASTER.sh.intel.com/ubuntu:latest")"

	kubectl apply -f $pod_config_snap
	eval $(parse_yaml $pod_config_snap "snap_")
	SNAP_POD_NAME=$snap_metadata_name

	if ! kubernetes_wait_cc_pod_be_running "${SNAP_POD_NAME}-0"; then
		# kubernetes_delete_cc_pod_if_exists "${SNAP_POD_NAME}-0" || true
		kubectl delete -f $pod_config_snap
		kubectl delete pvc "html-${SNAP_POD_NAME}-0"
		rm $pod_config
		kubectl delete -f $TEST_COCO_PATH/../fixtures/snapshot.yaml
		kubectl delete -f $pod_config
		kubectl delete pvc "html-${POD_NAME}"
		rm $pod_config_snap
		helm delete open-local
		rm -r $GOPATH/open-local
		return 1
	fi
	# kubernetes_delete_cc_pod_if_exists "${SNAP_POD_NAME}-0" || true
	kubectl delete -f $pod_config_snap
	rm $pod_config_snap
	kubectl delete pvc "html-${SNAP_POD_NAME}-0"
	kubectl delete -f $TEST_COCO_PATH/../fixtures/snapshot.yaml
	kubectl delete -f $pod_config
	kubectl delete pvc "html-${POD_NAME}"

	rm $pod_config

	helm delete open-local
	rm -r $GOPATH/open-local
}
Test_signed_image() {
	for IMAGE in ${EXAMPLE_IMAGE_LISTS[@]}; do
		skopeo --insecure-policy copy --sign-passphrase-file $TEST_COCO_PATH/../signed/passwd.txt --sign-by $GPG_EMAIL docker://$REGISTRY_NAME/$IMAGE:latest docker://$REGISTRY_NAME/$IMAGE:signed
		# tar -cf ${TEST_COCO_PATH}/../signed/signatures.tar.gz /var/lib/containers/sigstore/$IMAGE*
		setup_skopeo_signature_files_in_guest $IMAGE
		pod_config="$(new_pod_config $TEST_COCO_PATH/../fixtures/pod-config.yaml.in "$IMAGE" "$RUNTIMECLASS" "$REGISTRY_NAME/$IMAGE:signed")"
		create_test_pod $pod_config
		kubectl get pods
		pod_id=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
		kubernetes_delete_cc_pod_if_exists $pod_id || true
		rm $pod_config
	done
}
Test_encrypted_image() {

	# generate_encrypted_image
	# VERDICTDID=$(ps ux | grep "verdictd" | grep -v "grep" | awk '{print $2}')
	# if [ "$VERDICTDID" == "" ]; then
	# 	verdictd --listen 0.0.0.0:50000 --mutual >/dev/null 2>&1 &
	# fi
	# sleep 1
	setup_eaa_decryption_files_in_guest
	# $TEST_COCO_PATH/../run/losetup-crt.sh $ROOTFS_IMAGE_PATH c
	# for IMAGE in ${EXAMPLE_IMAGE_LISTS[@]}; do
	pod_config=$TEST_COCO_PATH/../fixtures/encrypted_image-config.yaml

	pull_encrypted_image_inside_guest_with_decryption_key $pod_config
	# rm $pod_config
	# done
	# VERDICTDID=$(ps ux | grep "verdictd " | grep -v "grep" | awk '{print $2}')
	# echo $VERDICTDID
	# kill -9 $VERDICTDID
}

Test_uninstall_operator() {
	reset_runtime
}
Test_cosign_image() {
	local IMAGE="nginx"
	local RUNTIMECLASSNAME="kata-qemu"
	local REGISTRTYIMAGE="zcy-Z390-AORUS-MASTER.sh.intel.com/nginx:latest"
	generate_cosign_image $(echo $REGISTRTYIMAGE | cut -d ":" -f1)
	local offline_base_config="$TEST_COCO_PATH/../config/aa-offline_fs_kbc-resources.json.in"
	local offline_new_config="$TEST_COCO_PATH/../tests/aa-offline_fs_kbc-resources.json"
	local p_b="$(cat $TEST_COCO_PATH/../config/policy.json | base64)"
	local policy_base64=$(echo $p_b | tr -d '\n' | tr -d ' ')
	local c_k_b="$(cat $TEST_COCO_PATH/../certs/cosign.pub | base64)"
	local cosign_key_base64=$(echo $c_k_b | tr -d '\n' | tr -d ' ')
	POLICY_BASE64="$policy_base64" COSIGN_KEY_BASE64="$cosign_key_base64" envsubst <"$offline_base_config" >"$offline_new_config"

	pod_config="$(new_pod_config_normal ${TEST_COCO_PATH}/../fixtures/cosign-config.yaml.in "$IMAGE" "$RUNTIMECLASSNAME" "$(echo $REGISTRTYIMAGE | cut -d "/" -f1)/cosigned/$IMAGE:cosigned")"
	remove_kernel_param "agent.enable_signature_verification"
	add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"
	add_kernel_params "agent.config_file=/etc/offline-agent-config.toml"
	cp_to_guest_img "etc" "$TEST_COCO_PATH/../config/offline-agent-config.toml"
	cp_to_guest_img "etc" "$TEST_COCO_PATH/../tests/aa-offline_fs_kbc-resources.json"
	create_test_pod $pod_config
	kubectl get pods
	pod_id=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
	kubernetes_delete_cc_pod_if_exists $pod_id || true
	# rm $pod_config
	# dpkg -r cosign
}
Test_encrypted_image_offline() {
	generate_offline_encrypted_image nginx
	setup_offline_decryption_files_in_guest
	pod_config="$(new_pod_config_normal $TEST_COCO_PATH/../fixtures/offline-encrypted-config.yaml.in "nginx" "kata-qemu" "zcy-Z390-AORUS-MASTER.sh.intel.com/nginx:offline-encrypted")"
	# OCICRYPT_KEYPROVIDER_CONFIG=ocicrypt.conf skopeo --insecure-policy copy --encryption-key provider:attestation-agent:/etc/aa-offline_fs_kbc-keys.json:key_id docker://zcy-Z390-AORUS-MASTER.sh.intel.com/ubuntu:latest docker://zcy-Z390-AORUS-MASTER.sh.intel.com/ubuntu:offline-encrypted
	pull_encrypted_image_inside_guest_with_decryption_key $pod_config
	# kubernetes_create_ssh_demo_pod "$TEST_COCO_PATH/../fixtures/offline-encrypted-config.yaml"
}
Test_measured_boot_image() {
	switch_measured_rootfs_verity_scheme dm-verity
	cp_to_guest_img "etc" "$TEST_COCO_PATH/../config/offline-agent-config.toml"
	unencrypted_signed_image_from_unprotected_registry $TEST_COCO_PATH/../fixtures/unsigned-unprotected-pod-config.yaml
}

teardown() {

	restore
	#reset_runtime
	# gpg --delete-keys $GPG_EMAIL
	# gpg --delete-secret-keys $GPG_EMAIL
	REGISTRY_CONTAINER=$(docker ps -a | grep "registry" | awk '{print $1}')
	if [ -n "$REGISTRY_CONTAINER" ]; then
		docker stop $REGISTRY_CONTAINER
		docker rm $REGISTRY_CONTAINER
	fi

}
tests() {
	export GOPATH=/root/go
	export VERSION=latest
	export TYPE_NAME="DNS"
	export REGISTRY_NAME=$(jq -r '.certificates.registry' $TEST_COCO_PATH/../config/test_config.json)
	export PORT=443
	export EXAMPLE_IMAGE_LISTS=(busybox)
	# run_registry
	# pull_image
	# curl https://zcy-Z390-AORUS-MASTER.sh.intel.com:443/v2/_catalog
	# skopeo list-tags docker://zcy-Z390-AORUS-MASTER.sh.intel.com/nginx
	# cosign sign --key cosign.key zcy-Z390-AORUS-MASTER.sh.intel.com/redis:latest
	# cosign verify --key cosign.pub $IMAGE_URI
	skopeo --insecure-policy copy --sign-passphrase-file ./signed/passwd.txt --sign-by intel@intel.com docker://docker.io/nginx:latest docker://zcy-Z390-AORUS-MASTER.sh.intel.com/nginx:signed
}
main() {
	setup
	read_config
	# run_registry
	# remove_kernel_param "agent.enable_signature_verification"
	# $TEST_COCO_PATH/../run/losetup-crt.sh $ROOTFS_IMAGE_PATH c
	Test_install_operator
	# start_local_registry
	# install_runtime
	# read_config
	# switch_measured_rootfs_verity_scheme none
	# Test_measured_boot_image
	# Test_cosign_image
	# pull_image
	Test_encrypted_image
	Test_uninstall_operator
	# teardown
}
main "$@"
