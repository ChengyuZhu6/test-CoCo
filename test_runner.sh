#!/usr/bin/env bash

# set -o errexit
# set -o nounset
# set -o pipefail
SCRIPT_PATH=$(pwd)
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

	while getopts "uestabmiopfchd :" opt; do
		case $opt in

		u)
			run_operator_install
			run_multiple_pod_spec_and_images_config
			run_operator_uninstall
			;;
		e)
			run_operator_install
			run_encrypted_image_config
			run_operator_uninstall
			;;
		s)
			run_operator_install
			run_signed_image_config
			run_operator_uninstall
			;;
		t)
			run_operator_install
			run_trust_storage_config
			run_operator_uninstall
			;;
		n) ;;

		b)
			run_operator_install
			run_measured_boot_image_config
			run_operator_uninstall
			;;

		m) ;;

		i) ;;
		o)
			run_operator_install
			run_operator_uninstall
			;;
		d) ;;

		p) ;;
		f)
			run_operator_install
			run_offline_encrypted_image_config
			run_operator_uninstall
			;;
		c)
			run_operator_install
			run_cosigned_image_config
			run_operator_uninstall
			;;
		d) ;;
		a)
			run_operator_install
			run_multiple_pod_spec_and_images_config
			run_encrypted_image_config
			run_offline_encrypted_image_config
			run_signed_image_config
			run_cosigned_image_config
			run_trust_storage_config
			run_measured_boot_image_config
			run_operator_uninstall
			;;
		h) usage 0 ;;
		*)
			echo "Invalid option: -$OPTARG" >&2
			usage 1
			;;
		esac
	done
	# echo $tests_config
}
generate_tests() {
	local base_config="$TEST_COCO_PATH/../templates/multiple_pod_spec.template"
	local new_config=$(mktemp "$TEST_COCO_PATH/../tests/$(basename ${base_config}).XXX")

	IMAGE="$1" IMAGE_SIZE="$2" RUNTIMECLASSNAME="$3" REGISTRTYIMAGE="$REGISTRY_NAME:$PORT/$1:$VERSION" POD_NUM="$4" POD_CPU_NUM="$5" POD_MEM_SIZE="$6" pod_config="\$pod_config" TEST_COCO_PATH="$TEST_COCO_PATH" COUNTS="\$COUNTS" status="\$status" envsubst <"$base_config" >"$new_config"

	echo "$new_config"
}
run_operator_install() {
	tests_passing="Test install operator"
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../templates/operator_install.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/operator_install.xml
}
run_operator_uninstall() {
	tests_passing="Test uninstall operator"
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../templates/operator_uninstall.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/operator_uninstall.xml
}
run_multiple_pod_spec_and_images_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tests/multiple_pod_spec_and_images.bats"
	local str="Test_multiple_pod_spec_and_images"
	echo -e "load ../run/lib.sh " | tee -a $new_pod_configs >/dev/null
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		for runtimeclass in ${RUNTIMECLASS[@]}; do
			for cpunums in ${CPUCONFIG[@]}; do
				for memsize in ${MEMCONFIG[@]}; do
					for podnum in ${PODNUMCONFIG[@]}; do
						cat "$(generate_tests ci-$image $image_size $runtimeclass $podnum $cpunums $memsize)" | tee -a $new_pod_configs >/dev/null
						tests_passing+="|${str} ci-$image $image_size $runtimeclass $podnum ${cpunums} ${memsize}GB"
					done
				done
			done
		done
	done
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tests/multiple_pod_spec_and_images.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tests/*
	rm -rf $TEST_COCO_PATH/../fixtures/multiple_pod_spec_and_images-config.yaml.in.*
}
run_trust_storage_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local pod_configs="$TEST_COCO_PATH/../templates/trust_storage.bats"
	local new_pod_configs="$TEST_COCO_PATH/../tests/$(basename ${pod_configs})"
	local str="Test_trust_storage"
	tests_passing="Test install open-local"
	cp $pod_configs $new_pod_configs
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		for runtimeclass in ${RUNTIMECLASS[@]}; do
			cat "$(generate_tests_trust_storage "$TEST_COCO_PATH/../templates/trust_storage.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
			tests_passing+="|${str} ci-$image $image_size $runtimeclass "

		done
	done
	cat "$TEST_COCO_PATH/../templates/operator_trust_storage.bats" | tee -a $new_pod_configs >/dev/null
	tests_passing+="|Test uninstall open-local"
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tests/trust_storage.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tests/*
}
run_signed_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tests/signed_image.bats"
	local str="Test_simple_signed_image"
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		for runtimeclass in ${RUNTIMECLASS[@]}; do
			cat "$(generate_tests_signed_image "$TEST_COCO_PATH/../templates/signed_image.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
			tests_passing+="|${str} ci-$image $image_size $runtimeclass"
		done
	done
	echo -e "load ../run/lib.sh \n load ../run/cc_deploy.sh \n read_config" | tee -a $new_pod_configs >/dev/null
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tests/signed_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tests/*
	rm -rf $TEST_COCO_PATH/../fixtures/signed_image-config.yaml.in.*
}
run_cosigned_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tests/cosigned_image.bats"
	local str="Test_cosigned_image"
	echo -e "load ../run/lib.sh \n load ../run/cc_deploy.sh \n read_config" | tee -a $new_pod_configs >/dev/null
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')

		for runtimeclass in ${RUNTIMECLASS[@]}; do
			cat "$(generate_tests_cosign_image "$TEST_COCO_PATH/../templates/cosigned_image.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
			tests_passing+="|${str} ci-$image $image_size $runtimeclass"
		done
	done

	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tests/cosigned_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tests/*
	rm -rf $TEST_COCO_PATH/../fixtures/cosign-config.yaml.in.*
}
run_encrypted_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tests/encrypted_image.bats"
	local str="Test_eaa_kbc_encrypted_image"
	# VERDICTDID=$(ps ux | grep "verdictd" | grep -v "grep" | awk '{print $2}')
	# if [ "$VERDICTDID" == "" ]; then
	# 	verdictd --listen 0.0.0.0:50000  2>&1 &
	# fi
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		for runtimeclass in ${EAATDXRUNTIMECLASS[@]}; do
			echo "runtimeclass = $runtimeclass"
			cat "$(generate_tests_encrypted_image "$TEST_COCO_PATH/../templates/encrypted_image.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
			tests_passing+="|${str} ci-$image $image_size $runtimeclass"
		done
	done
	echo -e "load ../run/lib.sh \n load ../run/cc_deploy.sh \n read_config" | tee -a $new_pod_configs >/dev/null

	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tests/encrypted_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	# VERDICTDID=$(ps ux | grep "verdictd " | grep -v "grep" | awk '{print $2}')
	# echo $VERDICTDID
	# kill -9 $VERDICTDID
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tests/*
	rm -rf $TEST_COCO_PATH/../fixtures/encrypted_image-config.yaml.in.*
}
run_offline_encrypted_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tests/offline_encrypted_image.bats"
	local str="Test_offline_encrypted_image"
	echo -e "load ../run/lib.sh \n load ../run/cc_deploy.sh \n read_config" | tee -a $new_pod_configs >/dev/null
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		for runtimeclass in ${RUNTIMECLASS[@]}; do
			echo "runtimeclass = $runtimeclass"
			cat "$(generate_tests_offline_encrypted_image "$TEST_COCO_PATH/../templates/offline_encrypted_image.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
			tests_passing+="|${str} ci-$image $image_size $runtimeclass"
		done
	done

	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tests/offline_encrypted_image.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tests/*
	rm -rf $TEST_COCO_PATH/../fixtures/offline-encrypted-config.yaml.in.*
}
run_measured_boot_image_config() {
	test_pod_for_ccruntime
	if [ $? -eq 1 ]; then
		echo "ERROR: cc runtimes are not deployed"
		return 1
	fi
	local new_pod_configs="$TEST_COCO_PATH/../tests/measured_boot.bats"
	local str="Test_measured_boot"
	echo -e "load ../run/lib.sh \n load ../run/cc_deploy.sh \n read_config" | tee -a $new_pod_configs >/dev/null
	for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
		docker pull $image
		image_size=$(docker image ls | grep ci-$image | head -1 | awk '{print $7}')
		for runtimeclass in ${RUNTIMECLASS[@]}; do
			cat "$(generate_tests_offline_encrypted_image "$TEST_COCO_PATH/../templates/measured_boot.template" ci-$image $image_size $runtimeclass)" | tee -a $new_pod_configs >/dev/null
			tests_passing+="|${str} ci-$image $image_size $runtimeclass"
		done
	done
	echo "$(bats -f "$tests_passing" \
		"$TEST_COCO_PATH/../tests/measured_boot.bats" --report-formatter junit --output $TEST_COCO_PATH/../report/)"
	mv $TEST_COCO_PATH/../report/report.xml $TEST_COCO_PATH/../report/$(basename ${new_pod_configs}).xml
	rm -rf $TEST_COCO_PATH/../tests/*
	rm -rf $TEST_COCO_PATH/../fixtures/measured-boot-config.yaml.in.*
}
print_image() {
	IMAGES=($1)
	for IMAGE in "${IMAGES[@]}"; do
		echo "    $IMAGE $(docker image ls | grep $IMAGE | head -1 | awk '{print $7}')"
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
	# git clone -b 2022-12-24 https://github.com/ChengyuZhu6/tests.git $GOPATH/src/github.com/kata-containers/tests
	# bash $GOPATH/src/github.com/kata-containers/tests/.ci/setup.sh

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
	# clean_up
	# cleanup_network_interface
	# gen_clean_arch
	# exit 0
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
		mkdir -p $SCRIPT_PATH/report/view
	fi
	parse_args $@
	# echo $(gen_clean_arch)
	# rm -r $GOPATH/src/github.com/operator
	# clean_up
	cleanup_network_interface
	echo "tests are finished"
	# return 0
}

main "$@"
