

@test "Test_measured_boot $IMAGE $IMAGE_SIZE $RUNTIMECLASSNAME" {
		set_runtimeclass_config $RUNTIMECLASSNAME
		switch_measured_rootfs_verity_scheme dm-verity
		add_kernel_params "agent.https_proxy=$HTTPS_PROXY"
		add_kernel_params "agent.no_proxy=$NO_PROXY"
		pod_config="$(new_pod_config_normal $TEST_COCO_PATH/../fixtures/measured-boot-config.yaml.in "busybox" "$RUNTIMECLASSNAME" "quay.io/prometheus/busybox:latest" )"
		kubernetes_create_cc_pod_tests $pod_config
		pod_name=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
		kubernetes_delete_cc_pod "${pod_name}"
		rm $pod_config
		switch_measured_rootfs_verity_scheme none
}

@test "Test_auth_registry $IMAGE $IMAGE_SIZE $RUNTIMECLASSNAME" {
		set_runtimeclass_config $RUNTIMECLASSNAME
		remove_kernel_param "agent.aa_kbc_params"
		add_kernel_params "agent.aa_kbc_params=eaa_kbc::$(hostname -I | awk '{print $1}'):50000"
		pod_config="$(new_pod_config_normal $TEST_COCO_PATH/../fixtures/auth_registry-config.yaml.in "confidential-containers-auth" "$RUNTIMECLASSNAME" "quay.io/kata-containers/confidential-containers-auth:test" )"
		kubernetes_create_cc_pod_tests $pod_config
		pod_name=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
		kubernetes_delete_cc_pod "$pod_name"
		rm $pod_config
}

@test "Test_multiple_pod_spec_and_images $IMAGE $IMAGE_SIZE $RUNTIMECLASSNAME ${POD_CPU_NUM}CPUs ${POD_MEM_SIZE}GB" {
		set_runtimeclass_config $RUNTIMECLASSNAME
		switch_measured_rootfs_verity_scheme none
		add_kernel_params "agent.https_proxy=http://child-prc.intel.com:913"
		add_kernel_params "agent.no_proxy=*.sh.intel.com,10.*"
		pod_config="$(new_pod_config $TEST_COCO_PATH/../fixtures/multiple_pod_spec-config.yaml.in "$IMAGE" "$RUNTIMECLASSNAME" "$REGISTRTYIMAGE" "1" "$POD_CPU_NUM" "$POD_MEM_SIZE")"
		unencrypted_unsigned_image_from_unprotected_registry $pod_config
		multiple_pods_delete
		rm $TEST_COCO_PATH/../fixtures/multiple_pod_spec-config.yaml.in.*	
}
@test "Test_eaa_kbc_encrypted_image $IMAGE $IMAGE_SIZE $RUNTIMECLASSNAME" {
	set_runtimeclass_config $RUNTIMECLASSNAME
	remove_kernel_param "agent.aa_kbc_params"
	switch_image_service_offload on
	$TEST_COCO_PATH/../run/losetup-crt.sh /opt/confidential-containers/share/kata-containers/kata-ubuntu-latest-tdx.image c
	switch_measured_rootfs_verity_scheme none
	generate_encrypted_image $IMAGE	
	setup_eaa_decryption_files_in_guest
	pod_config="$(new_pod_config_normal $TEST_COCO_PATH/../fixtures/encrypted_image-config.yaml.in "$IMAGE" "$RUNTIMECLASSNAME" "$REGISTRY_NAME/$IMAGE:encrypted")"
	pull_encrypted_image_inside_guest_with_decryption_key $pod_config
	rm $pod_config
}
@test "Test_offline_encrypted_image $IMAGE $IMAGE_SIZE $RUNTIMECLASSNAME" {
	set_runtimeclass_config $RUNTIMECLASSNAME
	remove_kernel_param "agent.aa_kbc_params"
	if [ "${RUNTIMECLASSNAME##*-}" == "tdx" ]; then
		skip
	fi
	switch_image_service_offload on
	$TEST_COCO_PATH/../run/losetup-crt.sh $ROOTFS_IMAGE_PATH c
	switch_measured_rootfs_verity_scheme none
	#generate_offline_encrypted_image $IMAGE
	setup_offline_decryption_files_in_guest
	pod_config="$(new_pod_config_normal $test_coco_path/../fixtures/offline-encrypted-config.yaml.in "$IMAGE" "$RUNTIMECLASSNAME" "$REGISTRTYIMAGE:offline-encrypted")"
	pull_encrypted_image_inside_guest_with_decryption_key $pod_config
	rm $pod_config
}
@test "Test_simple_signed_image $IMAGE $IMAGE_SIZE $RUNTIMECLASSNAME" {
	set_runtimeclass_config $RUNTIMECLASSNAME
	switch_measured_rootfs_verity_scheme none
	remove_kernel_param "agent.enable_signature_verification"
	remove_kernel_param "agent.aa_kbc_params"
	if [ -f ${test_coco_path}/../signed/pubkey.gpg ]; then
		rm ${test_coco_path}/../signed/pubkey.gpg
	fi
	gpg --no-tty --batch -a -o ${test_coco_path}/../signed/pubkey.gpg --export $GPG_EMAIL
	skopeo --insecure-policy copy --sign-passphrase-file ${test_coco_path}/../signed/passwd.txt --sign-by $GPG_EMAIL docker://$REGISTRTYIMAGE:latest  docker://$(echo $REGISTRTYIMAGE | cut -d "/" -f1)/signed/$IMAGE:signed
	setup_skopeo_signature_files_in_guest $IMAGE
	rtcs=$RUNTIMECLASSNAME
	if [ "${rtcs##*-}" == "tdx" ]; then 
		add_kernel_params "agent.aa_kbc_params=eaa_kbc::$(hostname -I | awk '{print $1}'):50000"
	else
		setup_offline_signed_files_in_guest
	fi
	pod_config="$(new_pod_config_normal ${test_coco_path}/../fixtures/signed_image-config.yaml.in "$IMAGE" "$RUNTIMECLASSNAME" "$(echo $REGISTRTYIMAGE | cut -d "/" -f1)/signed/$IMAGE:signed")"
	kubernetes_create_cc_pod_tests $pod_config
	kubectl get pods
	pod_id=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
	kubernetes_delete_cc_pod $pod_id 
	rm $pod_config
	rm ${test_coco_path}/../signed/pubkey.gpg
}
@test "Test_cosigned_image $IMAGE $IMAGE_SIZE $RUNTIMECLASSNAME" {
	set_runtimeclass_config $RUNTIMECLASSNAME
	switch_measured_rootfs_verity_scheme none
	#generate_cosign_image $(echo $REGISTRTYIMAGE | cut -d ":" -f1)
	
	pod_config="$(new_pod_config_normal ${test_coco_path}/../fixtures/cosign-config.yaml.in "$IMAGE" "$RUNTIMECLASSNAME" "$(echo $REGISTRTYIMAGE | cut -d "/" -f1)/cosigned/$IMAGE:cosigned")"
	remove_kernel_param "agent.enable_signature_verification"
	remove_kernel_param "agent.aa_kbc_params"
	rtcs=$RUNTIMECLASSNAME
	if [ "${rtcs##*-}" == "tdx" ]; then 
		add_kernel_params "agent.aa_kbc_params=eaa_kbc::$(hostname -I | awk '{print $1}'):50000"
	else
		add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"
		#add_kernel_params "agent.config_file=/etc/offline-agent-config.toml"
		#cp_to_guest_img "etc" "${test_coco_path}/../config/offline-agent-config.toml"
		cp_to_guest_img "etc" "${test_coco_path}/../tmp/aa-offline_fs_kbc-resources.json"
	fi

	kubernetes_create_cc_pod_tests $pod_config
	pod_name=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
	kubernetes_delete_cc_pod "$pod_name"
	rm $pod_config
}
