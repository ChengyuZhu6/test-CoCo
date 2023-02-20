#!/usr/bin/env bash

# set -o errexit
# set -o nounset
# set -o pipefail
SUB_DIR="function_test"
SCRIPT_PATH=$(pwd)/$SUB_DIR
script_name=$(basename "$0")
tests_passing=""
tests_config=""
tests_flag=""
source $SCRIPT_PATH/run/lib.sh
#source $SCRIPT_PATH/run/cc_deploy.sh
source $SCRIPT_PATH/setup/install_encrypt_tools.sh

usage() {
	exit_code="$1"
	cat <<EOF
Overview:
    Tests for confidential containers
    ${script_name} <command>
Commands:
	-u:	Multiple pod spec and container image tests
	-e:	Encrypted image tests
	-s:	Signed image tests
	-t:	Trusted storage for container image tests
	-n:	Attestation tests
	-b:	Measured boot tests
	-m:	Multiple registries tests
	-i:	Image sharing tests
	-d:	OnDemand image pulling tests
	-p:	TD preserving tests
	-c:	Common Cloud Native projects tests
	-a:	All tests
	-h:	help
EOF
}
parse_args() {
	read_config
	while getopts "u:e:s:t:a:b:m:i:o:p:f:c:h:d: " opt; do
		case $opt in
		u)
			echo "-u runtime: $OPTARG "
			set_runtimeclass_config $OPTARG

			;;
		e)
			echo "-e runtime: $OPTARG "
			set_runtimeclass_config $OPTARG

			;;
		s)
			echo "-s runtime: $OPTARG "
			set_runtimeclass_config $OPTARG

			;;
		t)
			echo "-t runtime: $OPTARG "
			set_runtimeclass_config $OPTARG
			;;
		n) ;;

		b)
			echo "-b runtime: $OPTARG "
			set_runtimeclass_config $OPTARG
			;;
		m)
			echo "-m runtime: $OPTARG "
			set_runtimeclass_config $OPTARG

			;;

		i)
			echo "-i runtime: $OPTARG "
			set_runtimeclass_config $OPTARG
			move_certs_to_rootfs
			run_unencrypted_unsigned_image_config
			run_encrypted_image_config
			run_offline_encrypted_image_config
			run_signed_image_config
			run_cosigned_image_config
			;;
		o)
			echo "-o runtime: $OPTARG "
			set_runtimeclass_config $OPTARG
			;;
		d)
			echo "-d runtime: $OPTARG "
			set_runtimeclass_config $OPTARG

			;;
		p)
			echo "-p runtime: $OPTARG "
			set_runtimeclass_config $OPTARG
			move_certs_to_rootfs
			run_un_pod_spec_tests_config
			run_cosign_pod_spec_tests_config
			run_eaa_kbc_pod_spec_tests_config
			;;
		f)
			echo "-f runtime: $OPTARG "
			set_runtimeclass_config $OPTARG
			run_function_tests_config
			;;
		c)
			echo "-c runtime: $OPTARG "
			set_runtimeclass_config $OPTARG
			move_certs_to_rootfs
			export IMAGE_LISTS=$(jq -r .file.commentsImageLists[] $TEST_COCO_PATH/../config/test_config.json)
			run_concurrency_unencrypted_unsigned_image_config
			run_concurrency_encrypted_image_config
			run_concurrency_offline_encrypted_image_config
			run_concurrency_signed_image_config
			run_concurrency_cosigned_image_config
			;;
		a)
			echo "-a runtime: $OPTARG "
			;;
		h) usage 0 ;;
		*)
			echo "Invalid option: -$OPTARG" >&2
			usage 1
			;;
		esac
	done
	return 0
}
move_certs_to_rootfs() {
	if [ $TDX_STATUS -ge 1 ]; then
		set_runtimeclass_config kata-qemu-tdx
	else
		set_runtimeclass_config kata-qemu
	fi
	echo $ROOTFS_IMAGE_PATH
	get_certs_from_remote
	$TEST_COCO_PATH/../run/losetup-crt.sh "/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest.image" c
	$TEST_COCO_PATH/../run/losetup-crt.sh "/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest-tdx.image" c
}

run_operator_install() {
	tests_passing="Test install operator"
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../templates/operator_install.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/operator_install.xml
}
run_operator_install_measured_boot() {
	tests_passing="Test install operator"
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../templates/operator_install_measure_boot.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/operator_install.xml
}
run_operator_uninstall() {
	tests_passing="Test uninstall operator"
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../templates/operator_uninstall.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/operator_uninstall.xml
}
run_un_pod_spec_tests_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/un_pod_spec.bats"
	local str="Test_pod_spec_for_unencrypted_unsigned_image"
	echo -e "load ../run/lib.sh " | tee -a $new_pod_configs >/dev/null

	local image="example1g"
	image_size=$(docker image ls | grep $(echo ci-$image | tr A-Z a-z) | head -1 | awk '{print $7}')
	runtimeclass=$Current_RuntimeClass
	for cpunums in ${CPUCONFIG[@]}; do
		for memsize in ${MEMCONFIG[@]}; do
			cat "$(generate_pod_spec_un_tests ci-$image $image_size $runtimeclass 1 $cpunums $memsize)" | tee -a $new_pod_configs >/dev/null
		done
	done
	if [ ! -d $TEST_COCO_PATH/../report/pod_spec ]; then
		mkdir -p $TEST_COCO_PATH/../report/pod_spec
	fi
	echo "$(bats "$TEST_COCO_PATH/../tmp/un_pod_spec.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/pod_spec/)"
	mv $TEST_COCO_PATH/../report/pod_spec/report.xml $TEST_COCO_PATH/../report/pod_spec/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}
run_cosign_pod_spec_tests_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local pod_configs="$TEST_COCO_PATH/../tests/pod_spec/cosigned_pod_spec.template"
	local new_pod_configs="$TEST_COCO_PATH/../tmp/cosigned_pod_spec.bats"
	local str="Test_pod_spec_for_cosigned_image"
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null

	local image="example1g"
	image_size=$(docker image ls | grep $(echo ci-$image | tr A-Z a-z) | head -1 | awk '{print $7}')
	runtimeclass=$Current_RuntimeClass
	for cpunums in ${CPUCONFIG[@]}; do
		for memsize in ${MEMCONFIG[@]}; do
			cat "$(generate_pod_spec_cosign_tests $pod_configs ci-$image $image_size $runtimeclass 1 $cpunums $memsize)" | tee -a $new_pod_configs >/dev/null
		done
	done
	if [ ! -d $TEST_COCO_PATH/../report/pod_spec ]; then
		mkdir -p $TEST_COCO_PATH/../report/pod_spec
	fi
	echo "$(bats "$TEST_COCO_PATH/../tmp/cosigned_pod_spec.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/pod_spec/)"
	mv $TEST_COCO_PATH/../report/pod_spec/report.xml $TEST_COCO_PATH/../report/pod_spec/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}
run_eaa_kbc_pod_spec_tests_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/eaa_kbc_pod_spec.bats"
	local str="Test_pod_spoc_for_eaa_kbc_image"
	local image="example1g"
	image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
	runtimeclass=$Current_RuntimeClass
	for cpunums in ${CPUCONFIG[@]}; do
		for memsize in ${MEMCONFIG[@]}; do
			cat "$(generate_pod_spec_eaa_kbc_tests "$TEST_COCO_PATH/../tests/pod_spec/eaa_kbc_pod_spec.template" ci-$image $image_size $runtimeclass 1 $cpunums $memsize)" | tee -a $new_pod_configs >/dev/null
			tests_passing+="|${str} ci-$image $image_size $runtimeclass"
		done
	done
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null

	if [ ! -d $TEST_COCO_PATH/../report/pod_spec ]; then
		mkdir -p $TEST_COCO_PATH/../report/pod_spec
	fi
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tmp/eaa_kbc_pod_spec.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/pod_spec/)"
	mv $TEST_COCO_PATH/../report/pod_spec/report.xml $TEST_COCO_PATH/../report/pod_spec/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}
run_function_tests_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local pod_configs="$TEST_COCO_PATH/../tests/function_test/function_test.bats"
	local new_pod_configs="$TEST_COCO_PATH/../tmp/function_test.bats"
	local image="nginx"
	image_size=$(docker image ls | grep $(echo ci-$image | tr A-Z a-z) | head -1 | awk '{print $7}')
	runtimeclass=$Current_RuntimeClass

	cat "$(insert_params_into_function_tests "$pod_configs" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
	if [ ! -d $TEST_COCO_PATH/../report/function ]; then
		mkdir -p $TEST_COCO_PATH/../report/function
	fi
	echo "$(bats "$new_pod_configs" --report-formatter junit --output $TEST_COCO_PATH/../report/function/)"
	mv $TEST_COCO_PATH/../report/function/report.xml $TEST_COCO_PATH/../report/function/$(basename ${new_pod_configs}).xml
	rm -f $TEST_COCO_PATH/../tmp/*
	rm -f $TEST_COCO_PATH/../fixtures/*.in.*
}
run_unencrypted_unsigned_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/unencrypted_unsigned_image.bats"
	local str="Test_unencrypted_unsigned_image"
	echo -e "load ../run/lib.sh " | tee -a $new_pod_configs >/dev/null
	for image in ${IMAGE_LISTS[@]}; do
		# docker pull $image
		# echo $image
		image=$(echo $image | tr A-Z a-z)
		image_size=$(docker image ls | grep $(echo ci-$image | tr A-Z a-z) | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		cat "$(generate_image_size_un_tests ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
		tests_passing+="|${str} ci-$image $image_size $runtimeclass "
	done
	if [ ! -d $TEST_COCO_PATH/../report/image ]; then
		mkdir -p $TEST_COCO_PATH/../report/image
	fi
	echo "$(bats  "$TEST_COCO_PATH/../tmp/unencrypted_unsigned_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/image/)"
	mv $TEST_COCO_PATH/../report/image/report.xml $TEST_COCO_PATH/../report/image/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}
run_trust_storage_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local pod_configs="$TEST_COCO_PATH/../templates/trust_storage.bats"
	local new_pod_configs="$TEST_COCO_PATH/../tmp/$(basename ${pod_configs})"
	local str="Test_trust_storage"
	tests_passing="Test install open-local"
	cp $pod_configs $new_pod_configs
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		# for runtimeclass in ${RUNTIMECLASS[@]}; do
		cat "$(generate_tests_trust_storage "$TEST_COCO_PATH/../templates/trust_storage.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
		tests_passing+="|${str} ci-$image $image_size $runtimeclass "

		# done
	done
	cat "$TEST_COCO_PATH/../templates/operator_trust_storage.bats" | tee -a $new_pod_configs >/dev/null
	tests_passing+="|Test uninstall open-local"
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tmp/trust_storage.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}
run_signed_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/signed_image.bats"
	local str="Test_simple_signed_image"
	for image in ${IMAGE_LISTS[@]}; do
		image=$(echo $image | tr A-Z a-z)
		# docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		cat "$(generate_tests_signed_image "$TEST_COCO_PATH/../tests/image/signed_image.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
		tests_passing+="|${str} ci-$image $image_size $runtimeclass "
	done
	echo -e "load ../run/lib.sh \n  \n read_config" | tee -a $new_pod_configs >/dev/null
	if [ ! -d $TEST_COCO_PATH/../report/image ]; then
		mkdir -p $TEST_COCO_PATH/../report/image
	fi
	echo "$(bats  "$TEST_COCO_PATH/../tmp/signed_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/image/)"
	mv $TEST_COCO_PATH/../report/image/report.xml $TEST_COCO_PATH/../report/image/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
	rm -rf $TEST_COCO_PATH/../fixtures/signed_image-config.yaml.in.*
}
run_cosigned_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/cosigned_image.bats"
	local str="Test_cosigned_image"
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null
	for image in ${IMAGE_LISTS[@]}; do
		image=$(echo $image | tr A-Z a-z)
		# docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		cat "$(generate_tests_cosign_image "$TEST_COCO_PATH/../tests/image/cosigned_image.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
		tests_passing+="|${str} ci-$image $image_size $runtimeclass "
	done
	if [ ! -d $TEST_COCO_PATH/../report/image ]; then
		mkdir -p $TEST_COCO_PATH/../report/image
	fi
	echo "$(bats  "$TEST_COCO_PATH/../tmp/cosigned_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/image/)"
	mv $TEST_COCO_PATH/../report/image/report.xml $TEST_COCO_PATH/../report/image/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
	rm -rf $TEST_COCO_PATH/../fixtures/cosign-config.yaml.in.*
}
run_encrypted_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/encrypted_image.bats"
	local str="Test_eaa_kbc_encrypted_image"
	# VERDICTDID=$(ps ux | grep "verdictd" | grep -v "grep" | awk '{print $2}')
	# if [ "$VERDICTDID" == "" ]; then
	# 	verdictd --listen 0.0.0.0:50000  2>&1 &
	# fi
	for image in ${IMAGE_LISTS[@]}; do
		image=$(echo $image | tr A-Z a-z)
		#docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		cat "$(generate_tests_encrypted_image "$TEST_COCO_PATH/../tests/image/encrypted_image.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
		tests_passing+="|${str} ci-$image $image_size $runtimeclass "
	done
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null
	if [ ! -d $TEST_COCO_PATH/../report/image ]; then
		mkdir -p $TEST_COCO_PATH/../report/image
	fi
	echo "$(bats  "$TEST_COCO_PATH/../tmp/encrypted_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/image/)"
	mv $TEST_COCO_PATH/../report/image/report.xml $TEST_COCO_PATH/../report/image/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
	rm -rf $TEST_COCO_PATH/../fixtures/encrypted_image-config.yaml.in.*
}
run_offline_encrypted_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/offline_encrypted_image.bats"
	local str="Test_offline_encrypted_image"
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null
	for image in ${IMAGE_LISTS[@]}; do
		image=$(echo $image | tr A-Z a-z)
		#docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		cat "$(generate_tests_offline_encrypted_image "$TEST_COCO_PATH/../tests/image/offline_encrypted_image.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
		tests_passing+="|${str} ci-$image $image_size $runtimeclass "
	done
	if [ ! -d $TEST_COCO_PATH/../report/image ]; then
		mkdir -p $TEST_COCO_PATH/../report/image
	fi
	echo "$(bats  "$TEST_COCO_PATH/../tmp/offline_encrypted_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/image/)"
	mv $TEST_COCO_PATH/../report/image/report.xml $TEST_COCO_PATH/../report/image/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
	rm -rf $TEST_COCO_PATH/../fixtures/offline-encrypted-config.yaml.in.*
}

run_concurrency_unencrypted_unsigned_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/unencrypted_unsigned_image.bats"
	local str="Test_concurrency_unencrypted_unsigned_image"
	echo -e "load ../run/lib.sh " | tee -a $new_pod_configs >/dev/null
	for image in ${IMAGE_LISTS[@]}; do
		# #docker pull $image
		# echo $image
		image=$(echo $image | tr A-Z a-z)
		for podnum in ${PODNUMCONFIG[@]}; do
			image_size=$(docker image ls | grep $(echo ci-$image | tr A-Z a-z) | head -1 | awk '{print $7}')
			runtimeclass=$Current_RuntimeClass
			cat "$(generate_concurrency_un_tests ci-$image $image_size $runtimeclass $podnum)" | tee -a $new_pod_configs >/dev/null
		done
	done
	if [ ! -d $TEST_COCO_PATH/../report/concurrency ]; then
		mkdir -p $TEST_COCO_PATH/../report/concurrency
	fi
	echo "$(bats "$TEST_COCO_PATH/../tmp/unencrypted_unsigned_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/concurrency/)"
	mv $TEST_COCO_PATH/../report/concurrency/report.xml $TEST_COCO_PATH/../report/concurrency/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}

run_concurrency_signed_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/signed_image.bats"
	local str="Test_concurrency_simple_signed_image"
	for image in ${IMAGE_LISTS[@]}; do
		image=$(echo $image | tr A-Z a-z)
		#docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		for podnum in ${PODNUMCONFIG[@]}; do
			cat "$(generate_concurrency_signed_tests "$TEST_COCO_PATH/../tests/concurrency/signed_image.template" ci-$image $image_size $runtimeclass $podnum)" | tee -a $new_pod_configs >/dev/null
		done
	done
	echo -e "load ../run/lib.sh \n  \n read_config" | tee -a $new_pod_configs >/dev/null
	if [ ! -d $TEST_COCO_PATH/../report/concurrency ]; then
		mkdir -p $TEST_COCO_PATH/../report/concurrency
	fi
	echo "$(bats "$TEST_COCO_PATH/../tmp/signed_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/concurrency/)"
	mv $TEST_COCO_PATH/../report/concurrency/report.xml $TEST_COCO_PATH/../report/concurrency/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}
run_concurrency_cosigned_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/cosigned_image.bats"
	local str="Test_concurrency_cosigned_image"
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null
	for image in ${IMAGE_LISTS[@]}; do
		image=$(echo $image | tr A-Z a-z)
		#docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		for podnum in ${PODNUMCONFIG[@]}; do
			cat "$(generate_pod_spec_cosign_tests "$TEST_COCO_PATH/../tests/concurrency/cosigned_image.template" ci-$image $image_size $runtimeclass $podnum)" | tee -a $new_pod_configs >/dev/null
		done
	done
	if [ ! -d $TEST_COCO_PATH/../report/concurrency ]; then
		mkdir -p $TEST_COCO_PATH/../report/concurrency
	fi
	echo "$(bats "$TEST_COCO_PATH/../tmp/cosigned_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/concurrency/)"
	mv $TEST_COCO_PATH/../report/concurrency/report.xml $TEST_COCO_PATH/../report/concurrency/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}
run_concurrency_encrypted_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/encrypted_image.bats"
	local str="Test_concurrency_eaa_kbc_encrypted_image"

	for image in ${IMAGE_LISTS[@]}; do
		image=$(echo $image | tr A-Z a-z)
		# #docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		for podnum in ${PODNUMCONFIG[@]}; do
			cat "$(generate_concurrency_eaa_kbc_tests "$TEST_COCO_PATH/../tests/concurrency/encrypted_image.template" ci-$image $image_size $runtimeclass $podnum)" | tee -a $new_pod_configs >/dev/null
		done
	done
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null
	if [ ! -d $TEST_COCO_PATH/../report/concurrency ]; then
		mkdir -p $TEST_COCO_PATH/../report/concurrency
	fi
	echo "$(bats "$TEST_COCO_PATH/../tmp/encrypted_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/concurrency/)"
	mv $TEST_COCO_PATH/../report/concurrency/report.xml $TEST_COCO_PATH/../report/concurrency/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}
run_concurrency_offline_encrypted_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/offline_encrypted_image.bats"
	local str="Test_concurrency_offline_encrypted_image"
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null
	for image in ${IMAGE_LISTS[@]}; do
		image=$(echo $image | tr A-Z a-z)
		# #docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		for podnum in ${PODNUMCONFIG[@]}; do
			cat "$(generate_concurrency_offline_encrypted_image "$TEST_COCO_PATH/../tests/concurrency/offline_encrypted_image.template" ci-$image $image_size $runtimeclass $podnum)" | tee -a $new_pod_configs >/dev/null
		done
	done
	if [ ! -d $TEST_COCO_PATH/../report/concurrency ]; then
		mkdir -p $TEST_COCO_PATH/../report/concurrency
	fi
	echo "$(bats "$TEST_COCO_PATH/../tmp/offline_encrypted_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/concurrency/)"
	mv $TEST_COCO_PATH/../report/concurrency/report.xml $TEST_COCO_PATH/../report/concurrency/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
}

run_measured_boot_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/measured_boot.bats"
	local str="Test_measured_boot"
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null
	#docker pull busybox
	image_size=$(docker image ls | grep "busybox" | head -1 | awk '{print $7}')
	# for runtimeclass in ${RUNTIMECLASS[@]}; do
	runtimeclass=$Current_RuntimeClass
	cat "$(generate_tests_measured_boot_image "$TEST_COCO_PATH/../templates/measured_boot.template" busybox $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
	tests_passing+="|${str} busybox $image_size $runtimeclass"
	tests_passing+="|${str}_failed busybox $image_size $runtimeclass"
	# done
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tmp/measured_boot.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
	rm -rf $TEST_COCO_PATH/../fixtures/measured-boot-config.yaml.in.*
}
run_auth_registry_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tmp/auth_registry.bats"
	local str="Test_auth_registry"
	echo -e "load ../run/lib.sh \n  read_config" | tee -a $new_pod_configs >/dev/null
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		#docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		runtimeclass=$Current_RuntimeClass
		# for runtimeclass in ${RUNTIMECLASS[@]}; do
		if [ "runtimeclass" == "kata-clh-tdx" ]; then
			continue
		fi
		cat "$(generate_tests_offline_encrypted_image "$TEST_COCO_PATH/../templates/auth_registry.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
		tests_passing+="|${str} ci-$image $image_size $runtimeclass"
		# done
	done
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tmp/auth_registry.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tmp/*
	rm -rf $TEST_COCO_PATH/../fixtures/auth_registry-config.yaml.in.*
}
print_image() {
	IMAGES=($1)
	for IMAGE in "${IMAGES[@]}"; do
		echo "    $IMAGE $(docker image ls | grep $IMAGE | grep -v $IMAGE- | head -1 | awk '{print $7}')"
	done
}
setup_env() {
	echo "install go"
	# $SCRIPT_PATH/setup/install_go.sh
	echo "install rust"
	# $SCRIPT_PATH/setup/install_rust.sh
	# source "$HOME/.cargo/env"
	echo "install Kubernetes"
	# if [ -d $GOPATH/src/github.com/kata-containers/tests ]; then
	# 	rm -r $GOPATH/src/github.com/kata-containers/tests
	# fi
	local operator_repo=$GOPATH/src/github.com/operator
	if [ -d $operator_repo ]; then
		rm -r $operator_repo
	fi
	git clone https://github.com/ChengyuZhu6/operator.git $operator_repo
	export KUBECONFIG=/etc/kubernetes/admin.conf
	bash $operator_repo/tests/e2e/run-local.sh -r kata-qemu

	echo "install bats"
	# $SCRIPT_PATH/setup/install_bats.sh
	echo "install skopeo"
	# install_skopeo
	echo "install attestation-agent"
	# install_attestation_agent
	echo "install verdictd"
	# install_verdictd
	echo "install cosign"
	# install_cosign
}

main() {
	read_config
	$SCRIPT_PATH/serverinfo/serverinfo-stdout.sh
	echo -e "\n\n"

	echo -e "\n--------Functions to be tested with CoCo workloads--------"

	EXAMPLE_IMAGE_LISTS=$(jq -r .file.commentsImageLists[] $SCRIPT_PATH/config/test_config.json)
	echo -e "multiple pod spec and images: "
	print_image "${EXAMPLE_IMAGE_LISTS[@]}"
	echo -e "trust storage images: "
	print_image "${EXAMPLE_IMAGE_LISTS[@]}"
	echo -e "signed images: "
	print_image "${EXAMPLE_IMAGE_LISTS[@]}"
	echo -e "encrypted images: "
	print_image "${EXAMPLE_IMAGE_LISTS[@]}"
	echo -e "offline-encrypted images: "
	print_image "${EXAMPLE_IMAGE_LISTS[@]}"
	echo -e "cosigned images: "
	print_image "${EXAMPLE_IMAGE_LISTS[@]}"
	echo -e "Attestation: TODO"
	echo -e "Measured boot: TODO"
	echo -e "Multiple registries: TODO"
	echo -e "Image sharing: TODO"
	echo -e "OnDemand image pulling: TODO"
	echo -e "TD Preserving: TODO"
	echo -e "Common Cloud Native projects: TODO"
	echo -e "\n"
	echo -e "-------Install Depedencies:-------\n"
	setup_env
	echo "--------Operator Version--------"
	OPERATOR_VERSION=$(jq -r .file.operatorVersion $SCRIPT_PATH/config/test_config.json)
	echo "Operator Version: $OPERATOR_VERSION"
	# install_runtime  >/dev/null 2>&1
	# local kernel_version="$(/opt/confidential-containers/bin/kata-runtime kata-env --json | jq -r .Kernel.Path| cut -d '/' -f6)"
	# echo "Kernel: $kernel_version"
	# local runtime_version=$(/opt/confidential-containers/bin/kata-runtime kata-env --json | jq -r .Runtime.Version | grep Semver | cut -d'"' -f4)
	# echo "Runtime: $runtime_version"
	# local hypervisor_version=$(/opt/confidential-containers/bin/kata-runtime kata-env --json | jq -r .Hypervisor.Version| sed -n "1,1p")
	# echo "Hypervisor: $hypervisor_version"
	# reset_runtime  >/dev/null 2>&1
	echo -e "\n-------Test Result:-------"

	if [ -f /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf ]; then
		rm /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf
	fi

	if [ ! -d $SCRIPT_PATH/report/view ]; then
		sudo mkdir -p $SCRIPT_PATH/report/view
	fi
	if [ ! -d $SCRIPT_PATH/tmp ]; then
		sudo mkdir -p $SCRIPT_PATH/tmp
	fi
	parse_args $@
	# cleanup_network_interface
	echo "tests are finished"
	return 0
}

main "$@"
