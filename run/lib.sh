#!/usr/bin/env bash

set -e
source $(pwd)/run/common.bash
parse_yaml() {
    local prefix=$2
    local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @ | tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $1 |
        awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

# Add parameters to the 'kernel_params' property on kata's configuration.toml
#
# Parameters:
#	$1..$N - list of parameters
#
# Environment variables:
#	CURRENT_CONFIG_FILES - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
add_kernel_params() {
    local params="$@"

    sudo sed -i -e 's#^\(kernel_params\) = "\(.*\)"#\1 = "\2 '"$params"'"#g' \
        "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"
}
remove_kernel_param() {
    local param_name="${1}"

    sudo sed -i "/kernel_params = /s/$param_name=[^[:space:]\"]*//g" \
        "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"
}
# Get the 'kernel_params' property on kata's configuration.toml
#
# Environment variables:
#	CURRENT_CONFIG_FILES - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
get_kernel_params() {
    local kernel_params=$(sed -n -e 's#^kernel_params = "\(.*\)"#\1#gp' \
        "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}")
}
# Configure containerd for confidential containers. Among other things, it ensures
# the CRI handler is configured to deal with confidential container.
#
# Parameters:
#	$1 - (Optional) file path to where save the current containerd's config.toml
#
configure_cc_containerd() {
    local saved_containerd_conf_file="${1:-}"
    local containerd_conf_file="/etc/containerd/config.toml"

    # Even if we are not saving the original file it is a good idea to
    # restart containerd because it might be in an inconsistent state here.
    systemctl stop containerd
    sleep 5
    [ -n "$saved_containerd_conf_file" ] &&
        cp -f "$containerd_conf_file" "$saved_containerd_conf_file"
    systemctl start containerd

    # waitForProcess 30 5 " crictl info >/dev/null"
    sleep 5
    # Ensure the cc CRI handler is set.
    # local cri_handler=$(crictl info |
    # 	jq '.config.containerd.runtimes.kata.cri_handler')
    # if [[ ! "$cri_handler" =~ cc ]]; then
    # 	sed -i 's/\([[:blank:]]*\)\(runtime_type = "io.containerd.kata.v2"\)/\1\2\n\1cri_handler = "cc"/' \
    # 		"$containerd_conf_file"
    # fi

    if [ "$(crictl info | jq -r '.config.cni.confDir')" = "null" ]; then
        echo "    [plugins.cri.cni]
		  # conf_dir is the directory in which the admin places a CNI conf.
		  conf_dir = \"/etc/cni/net.d\"" |
            tee -a "$containerd_conf_file"
    fi

    systemctl restart containerd
    sleep 5

    # if ! waitForProcess 30 5 " crictl info >/dev/null"; then
    # 	die "containerd seems not operational after reconfigured"
    # fi
    iptables -P FORWARD ACCEPT
}
waitForProcess() {
    wait_time="$1"
    sleep_time="$2"
    cmd="$3"
    while [ "$wait_time" -gt 0 ]; do
        if eval "$cmd"; then
            return 0
        else
            sleep "$sleep_time"
            wait_time=$((wait_time - sleep_time))
        fi
    done
    return 1
}
switch_image_service_offload() {
    # Load the CURRENT_CONFIG_FILES variable.

    case "$1" in
    "on")
        sudo sed -i -e 's/^\(service_offload\).*=.*$/\1 = true/g' \
            "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"
        ;;
    "off")
        sudo sed -i -e 's/^\(service_offload\).*=.*$/\1 = false/g' \
            "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"

        ;;
    *)
        die "Unknown option '$1'"
        ;;
    esac
}
# Clear the 'kernel_params' property on kata's configuration.toml
#
# Environment variables:
#	CURRENT_CONFIG_FILES - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
clear_kernel_params() {

    sed -i -e 's#^\(kernel_params\) = "\(.*\)"#\1 = ""#g' \
        "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"
}
# Wait until the pod is not 'Ready'. Fail if it hits the timeout.
#
# Parameters:
#	$1 - the sandbox ID
#	$2 - wait time in seconds. Defaults to 60. (optional)
#
kubernetes_wait_cc_pod_be_ready() {
    local pod_name="$1"
    local wait_time="${2:-60}"

    kubectl wait --timeout=${wait_time}s --for=condition=ready pods/$pod_name
}
kubernetes_wait_cc_pod_be_running() {
    local pod_name="$1"
    local wait_time="${2:-30}"

    kubectl wait --timeout=${wait_time}s --for=jsonpath='{.status.phase}'=Running pods/$pod_name
}
kubernetes_wait_open_local_be_ready() {
    local wait_time="${1:-300}"
    kubectl wait --timeout=${wait_time}s --for=jsonpath='{.status.filteredStorageInfo.volumeGroups[0]}'="open-local-pool-0" nodelocalstorage/$NODE_NAME
}

kubernetes_wait_cc_snapshot_be_ready() {
    local pod_name="$1"
    local wait_time="${2:-120}"

    kubectl wait --timeout=${wait_time}s --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/new-snapshot-test
}
# Create a pod and wait it be ready, otherwise fail.
#
# Parameters:
#	$1 - the pod configuration file.
#
kubernetes_create_cc_pod() {
    local config_file="$1"
    local pod_name=""

    if [ ! -f "${config_file}" ]; then
        echo "Pod config file '${config_file}' does not exist"
        return 1
    fi

    kubectl apply -f ${config_file}
    # if ! pod_name=$(kubectl get pods -o jsonpath='{.items..metadata.name}'); then
    #     echo "Failed to create the pod"
    #     return 1
    # fi

    # if ! kubernetes_wait_cc_pod_be_ready "$pod_name"; then
    #     # TODO: run this command for debugging. Maybe it should be
    #     #       guarded by DEBUG=true?
    #     kubectl get pods "$pod_name"
    #     return 1
    # fi
}
kubernetes_create_cc_pod_tests() {
    local config_file="$1"
    local pod_name=""

    if [ ! -f "${config_file}" ]; then
        echo "Pod config file '${config_file}' does not exist"
        return 1
    fi

    kubectl apply -f ${config_file}
    if ! pod_name=$(kubectl get pods -o jsonpath='{.items..metadata.name}'); then
        echo "Failed to create the pod"
        return 1
    fi

    if ! kubernetes_wait_cc_pod_be_running "$pod_name"; then
        # TODO: run this command for debugging. Maybe it should be
        #       guarded by DEBUG=true?
        kubectl get pods "$pod_name"
        return 1
    fi
    
}
enable_agent_console() {

    sudo sed -i -e 's/^# *\(debug_console_enabled\).*=.*$/\1 = true/g' \
        "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"
}

enable_full_debug() {
    # Load the RUNTIME_CONFIG_PATH variable.

    # Toggle all the debug flags on in kata's configuration.toml to enable full logging.
    sed -i -e 's/^# *\(enable_debug\).*=.*$/\1 = true/g' "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"

    # Also pass the initcall debug flags via Kernel parameters.
    # add_kernel_params "agent.log=debug" "initcall_debug"
}

# Toggle between different measured rootfs verity schemes during tests.
#
# Parameters:
#	$1: "none" to disable or "dm-verity" to enable measured boot.
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
switch_measured_rootfs_verity_scheme() {
    echo "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"
    case "$1" in
    "dm-verity" | "none")
        sudo sed -i -e 's/scheme=.* cc_rootfs/scheme='"$1"' cc_rootfs/g' \
            "$RUNTIME_CONFIG_PATH/${CURRENT_CONFIG_FILE}"
        ;;
    *)
        die "Unknown option '$1'"
        ;;
    esac
}

# Create the test pod.
#
# Note: the global $sandbox_name, $pod_config should be set
# 	already. It also relies on $CI and $DEBUG exported by CI scripts or
# 	the developer, to decide how to set debug flags.
#
create_test_pod() {
    # On CI mode we only want to enable the agent debug for the case of
    # the test failure to obtain logs.
    if [ "${CI:-}" == "true" ]; then
        enable_full_debug
    elif [ "${DEBUG:-}" == "true" ]; then
        enable_full_debug
        enable_agent_console
    fi

    echo "Create the test sandbox"
    echo "Pod config is: "$1
    kubernetes_create_cc_pod $1
}
# Delete the containers alongside the Pod.
#
# Parameters:
#	$1 - the sandbox name
#
kubernetes_delete_cc_pod() {
    local sandbox_name="$1"
    local pod_id=${sandbox_name}
    if [ -n "${pod_id}" ]; then

        kubectl delete pod "${pod_id}"
    fi
}

# Delete the pod if it exists, otherwise just return.
#
# Parameters:
#	$1 - the sandbox name
#
kubernetes_delete_cc_pod_if_exists() {
    local sandbox_name="$1"
    [ -z "$(kubectl get pods ${sandbox_name})" ] ||
        kubernetes_delete_cc_pod "${sandbox_name}"
}
# Check the logged messages on host have a given message.
# Parameters:
#      $1 - the message
#
# Note: get the logs since the global $start_date.
#
assert_logs_contain() {
    local message="$1"
    journalctl -x -t kata --since "$start_date" | grep "$message"
}
assert_pod_fail() {
    local container_config="$1"
    echo "In assert_pod_fail: "$container_config

    echo "Attempt to create the container but it should fail"
    ! kubernetes_create_cc_pod_tests "$container_config" || /bin/false
}
checkout_pod_yaml() {
    pod_config=$1
    current_image_name=$2
    eval $(parse_yaml $pod_config "_")
    image_name=$(echo $_metadata_name | cut -d '-' -f 1)
    echo "--------------"
    echo ${image_name,,}
    echo ${current_image_name,,}
    echo "--------------"
    # sed -i "s/${image_name,,}/${current_image_name,,}/g" $pod_config
    # yq w  -i $pod_config 'spec.containers[0].image' ${REGISTRY_NAME}/${current_image_name}:$VERSION
    # sed -r "s/(\s\+runtimeClassName:')[^']*/\1 ${RUNTIMECLASS}/" $pod_config
    # sed -i "s/\(^\s\+runtimeClassName:\).*/\t${RUNTIMECLASS}/" $pod_config
    # sed -i -e "s/\s\+runtimeClassName:\s\.*/${RUNTIMECLASS}/" $pod_config
    # exit 0
}
checkout_snapshot_yaml() {
    local pod_config=$1
    local current_image_name=$2
    eval $(parse_yaml $pod_config "snapshot_")
    image_name=$(echo $snapshot_spec_source_persistentVolumeClaimName | cut -d '-' -f 2)
    echo ${image_name}
    # sed -i "s/${image_name,,}/${current_image_name,,}/g" $pod_config

}
# Copy local files to the guest image.
#
# Parameters:
#	$1      - destination directory in the image. It is created if not exist.
#	$2..*   - list of local files.
#
cp_to_guest_img() {
    local dest_dir="$1"
    # local image_path="$2"
    shift # remaining arguments are the list of files.
    local src_files=($@)
    local rootfs_dir=""

    if [ "${#src_files[@]}" -eq 0 ]; then
        echo "Expected a list of files"
        return 1
    fi

    rootfs_dir="$(mktemp -d)"
    local image_path=$ROOTFS_IMAGE_PATH

    # Open the original initrd/image, inject the agent file
    # local image_path="$(sudo -E PATH=$PATH kata-runtime kata-env --json | jq -r .Image.Path)"

    if [ -f "$image_path" ]; then
        if ! mount -o loop,offset=$((512 * 6144)) "$image_path" \
            "$rootfs_dir"; then
            echo "Failed to mount the image file: $image_path"
            rm -rf "$rootfs_dir"
            return 1
        fi
    else
        local initrd_path="$(sudo -E PATH=$PATH kata-runtime kata-env --json |
            jq -r .Initrd.Path)"
        if [ ! -f "$initrd_path" ]; then
            echo "Guest initrd and image not found"
            rm -rf "$rootfs_dir"
            return 1
        fi

        if ! cat "${initrd_path}" | cpio --extract --preserve-modification-time \
            --make-directories --directory="${rootfs_dir}"; then
            echo "Failed to uncompress the image file: $initrd_path"
            rm -rf "$rootfs_dir"
            return 1
        fi
    fi
    mkdir -p "${rootfs_dir}/${dest_dir}"

    for file in ${src_files[@]}; do
        if [ ! -f "$file" ] && [ ! -d "$file" ]; then
            echo "File not found, not copying: $file"
            continue
        fi

        if [ -f "$file" ]; then
            cp -af "${file}" "${rootfs_dir}/${dest_dir}"
        else
            cp -ad "${file}" "${rootfs_dir}/${dest_dir}"
        fi
    done
    # umount "$rootfs_dir"
    # rm -rf "$rootfs_dir"
    if [ -f "$image_path" ]; then
        if ! umount "$rootfs_dir"; then
            echo "Failed to umount the directory: $rootfs_dir"
            rm -rf "$rootfs_dir"
            return 1
        fi
    else
        if ! bash -c "cd "${rootfs_dir}" && find . | \
			cpio -H newc -o | gzip -9 > ${initrd_path}"; then
            echo "Failed to compress the image file"
            rm -rf "$rootfs_dir"
            return 1
        fi
    fi

    rm -rf "$rootfs_dir"
}
# In case the tests run behind a firewall where images needed to be fetched
# through a proxy.
# Note: With measured rootfs enabled, we can not set proxy through
# agent config file.
setup_http_proxy() {
    local https_proxy="${HTTPS_PROXY:-${https_proxy:-}}"
    if [ -n "$https_proxy" ]; then
        echo "Enable agent https proxy"
        add_kernel_params "agent.https_proxy=$https_proxy"
    fi
}

generate_encrypted_image() {
    local IMAGE="$1"
    # Generate the key provider configuration file
    if [ ! -d /etc/containerd/ocicrypt/ ]; then
        mkdir -p /etc/containerd/ocicrypt/
    fi
    cat <<-EOF >/etc/containerd/ocicrypt/ocicrypt_keyprovider.conf
{
        "key-providers": {
                "attestation-agent": {
                    "grpc": "127.0.0.1:50001"

                }
        }
}
EOF

    # Generate a encryption key
    if [ ! -d /opt/verdictd/keys/ ]; then
        mkdir -p /opt/verdictd/keys/
    fi
    cat <<-EOF >/opt/verdictd/keys/84688df7-2c0c-40fa-956b-29d8e74d16c0
1234567890123456789012345678901
EOF

    VERDICTDID=$(ps ux | grep "verdictd --client-api" | grep -v "grep" | awk '{print $2}')
    if [ "$VERDICTDID" == "" ]; then
        # verdictd --client-api 127.0.0.1:50001 >/dev/null 2>&1 &
        verdictd --client-api 127.0.0.1:50001 2>&1 &
    fi
    sleep 1
    # Launch Verdictd in another terminal

    # skopeo --insecure-policy copy docker://ngcn-registry.sh.intel.com/ci-ubuntu:encrypted oci:ubuntu
    # skopeo copy --insecure-policy --encryption-key provider:attestation-agent:84688df7-2c0c-40fa-956b-29d8e74d16c0 docker://ngcn-registry.sh.intel.com/ci-ubuntu:latest oci:ubuntu-encrypted

    export OCICRYPT_KEYPROVIDER_CONFIG=/etc/containerd/ocicrypt/ocicrypt_keyprovider.conf

    skopeo copy --insecure-policy --remove-signatures --encryption-key provider:attestation-agent:84688df7-2c0c-40fa-956b-29d8e74d16c0 docker://${REGISTRY_NAME}/${IMAGE}:latest docker://${REGISTRY_NAME}/${IMAGE}:encrypted

    # generate encrypted image

    # VERDICTDID=$(ps ux | grep "verdictd --client-api" | grep -v "grep" | awk '{print $2}')
    # echo $VERDICTDID
    # sudo kill -9 $VERDICTDID
}
generate_offline_encrypted_image() {
    local img="$1"
    if [ ! -f $TEST_COCO_PATH/../config/ocicrypt.conf ]; then
        cat <<-EOF >$TEST_COCO_PATH/../config/ocicrypt.conf
{
        "key-providers": {
                "attestation-agent": {
                    "grpc": "127.0.0.1:50001"

                }
        }
}
EOF
    fi
    if [ ! -d $GOPATH/src/github.com/attestation-agent ]; then
        git clone https://github.com/confidential-containers/attestation-agent.git $GOPATH/src/github.com/attestation-agent

    fi
    offline_kbs_id=$(ps ux | grep "sample_keyprovider" | grep -v "grep" | awk '{print $2}')

    cd $GOPATH/src/github.com/attestation-agent/sample_keyprovider/src/enc_mods/offline_fs_kbs
    if [ "$offline_kbs_id" == "" ]; then
        cargo run --release --features offline_fs_kbs -- --keyprovider_sock 127.0.0.1:50001 2>&1 &
    fi

    cp ${TEST_COCO_PATH}/../config/aa-offline_fs_kbc-keys.json /etc/
    OCICRYPT_KEYPROVIDER_CONFIG=$TEST_COCO_PATH/../config/ocicrypt.conf skopeo copy --remove-signatures --encryption-key provider:attestation-agent:/etc/aa-offline_fs_kbc-keys.json:key_id docker://${REGISTRY_NAME}/${img}:latest docker://${REGISTRY_NAME}/${img}:offline-encrypted
    offline_kbs_id=$(ps ux | grep "sample_keyprovider" | grep -v "grep" | awk '{print $2}')
    echo $offline_kbs_id
    kill -9 $offline_kbs_id
}

setup_eaa_kbc_agent_config_in_guest() {
    local rootfs_agent_config="/etc/agent-config.toml"

    # clone_katacontainers_repo
    sudo -E AA_KBC_PARAMS="$1" envsubst <$TEST_COCO_PATH/../config/confidential-agent-config.toml.in | sudo tee ${rootfs_agent_config}

    # sudo -E AA_KBC_PARAMS="eaa_kbc::10.112.240.208:50000" envsubst < $TEST_COCO_PATH/../config/confidential-agent-config.toml.in | sudo tee ${rootfs_agent_config}
    # sudo -E AA_KBC_PARAMS='offline_fs_kbc::null' envsubst < $TEST_COCO_PATH/../config/confidential-agent-config.toml.in | sudo tee ${rootfs_agent_config}

    # TODO #5173 - remove this once the kernel_params aren't ignored by the agent config
    # Enable debug log_level and debug_console access based on env vars
    echo "log_level = \"debug\"" | sudo tee -a "${rootfs_agent_config}"
    echo -e "debug_console = true\ndebug_console_vport = 1026" | sudo tee -a "${rootfs_agent_config}"
    echo -e "dev_mode = false\nserver_addr = \"vsock://-1:4096\"\nlog_vport = 0\ncontainer_pipe_size = 0\nunified_cgroup_hierarchy = false\ntracing = false" | sudo tee -a "${rootfs_agent_config}"
    # Uncomment the 'ExecProcessRequest' endpoint as our test currently uses exec to check the container
    sudo sed -i 's/#\("ExecProcessRequest"\)/\1/g' "${rootfs_agent_config}"
    cp_to_guest_img "/tests/fixtures" "${rootfs_agent_config}"
    add_kernel_params "agent.config_file=/tests/fixtures/$(basename ${rootfs_agent_config})"
    # add_kernel_params "agent.config_file=${rootfs_agent_config}"
    # cat "${rootfs_agent_config}"
}
setup_eaa_decryption_files_in_guest() {
    add_kernel_params "agent.aa_kbc_params=eaa_kbc::10.112.240.208:50000"
    cat <<-EOF >/opt/verdictd/keys/84688df7-2c0c-40fa-956b-29d8e74d16c0
1234567890123456789012345678901
EOF
    export OCICRYPT_KEYPROVIDER_CONFIG=/etc/containerd/ocicrypt/ocicrypt_keyprovider.conf
    # setup_eaa_kbc_agent_config_in_guest "eaa_kbc::10.239.159.53:50000"
    # setup_eaa_kbc_agent_config_in_guest "eaa_kbc::10.112.240.208:50000"
}
setup_credentials_files() {
    add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"
    # setup_eaa_kbc_agent_config_in_guest "offline_fs_kbc::null"
    # REGISTRY_CREDENTIAL_ENCODED="a2F0YS1jb250YWluZXJzK2NjX2F1dGg6VjFBRkU5UkM0TVQyQTZNR0pCVTIxUFJON1VETkFHMVNMTDJNOVNMUVlLOEE5VExLR09WN04wUlNYNUw0RTgxVA=="
    local offline_base_config="$TEST_COCO_PATH/../config/aa-offline_fs_kbc-resources_test.json.in"
    local offline_new_config="$TEST_COCO_PATH/../tests/aa-offline_fs_kbc-resources.json"
    # auth_json=$(REGISTRY=$1 CREDENTIALS="${REGISTRY_CREDENTIAL_ENCODED}" envsubst <"$TEST_COCO_PATH/../config/auth.json.in" | base64 -w 0)
    auth_json=$(base64 -w 0 $TEST_COCO_PATH/../config/auth.json)
    echo "$auth_json"
    CREDENTIAL="${auth_json}" envsubst <"$offline_base_config" >"${offline_new_config}"
    cp_to_guest_img "etc" "${offline_new_config}"
}
setup_offline_decryption_files_in_guest() {
    add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"
    # add_kernel_params "agent.config_file=/etc/offline-agent-config.toml"
    cp_to_guest_img "etc" "$TEST_COCO_PATH/../config/offline-agent-config.toml"
    cp_to_guest_img "etc" "$TEST_COCO_PATH/../config/aa-offline_fs_kbc-keys.json"
    local offline_base_config="$TEST_COCO_PATH/../config/aa-offline_fs_kbc-resources.json.in"
    local offline_new_config="$TEST_COCO_PATH/../tests/aa-offline_fs_kbc-resources.json"
    local p_b="$(cat $TEST_COCO_PATH/../config/policy.json | base64)"
    local policy_base64=$(echo $p_b | tr -d '\n' | tr -d ' ')
    local c_k_b="$(cat $TEST_COCO_PATH/../certs/cosign.pub | base64)"
    local cosign_key_base64=$(echo $c_k_b | tr -d '\n' | tr -d ' ')
    POLICY_BASE64="$policy_base64" COSIGN_KEY_BASE64="$cosign_key_base64" envsubst <"$offline_base_config" >"$offline_new_config"
    cp_to_guest_img "etc" "$offline_new_config"
}
kubernetes_create_ssh_demo_pod() {
    kubectl apply -f "$1" && pod=$(kubectl get pods -o jsonpath='{.items..metadata.name}') && kubectl wait --timeout=120s --for=condition=ready pods/$pod

    kubectl get pod $pod
}
kubernetes_delete_ssh_demo_pod_if_exists() {
    local sandbox_name="$1"
    if [ -n "$(kubectl get pods $sandbox_name)" ]; then
        kubernetes_delete_ssh_demo_pod ${sandbox_name}
    fi
}

kubernetes_delete_ssh_demo_pod() {
    kubectl delete pod $1

    kubectl wait pod/$1 --for=delete --timeout=-30s
}
generate_gpg_key() {
    gpg --expert --full-gen-key <<ESXU
1
4096
4096
0
y
$GPG_EMAIL
$GPG_EMAIL
$GPG_EMAIL
o
$GPG_EMAIL
$GPG_EMAIL

ESXU
}
setup_skopeo_signature_files_in_guest() {
    rootfs_directory="etc/containers/"
    target_image="$1"
    setup_common_signature_files_in_guest $target_image
    cp_to_guest_img "${rootfs_directory}" "/etc/containers/registries.d"
}

setup_common_signature_files_in_guest() {
    rootfs_sig_directory="var/lib/containers/sigstore/"
    target_image_dir=$(ls /var/lib/containers/sigstore/ | grep "$1@sha256=*")
    cp_to_guest_img "${rootfs_sig_directory}" "/$rootfs_sig_directory/$target_image_dir"

}
generate_tests_trust_storage() {
    local base_config=$1
    local new_config=$(mktemp "$TEST_COCO_PATH/../tests/$(basename ${base_config}).XXX")

    IMAGE="$2" IMAGE_SIZE="$3" RUNTIMECLASSNAME="$4" REGISTRTYIMAGE="$REGISTRY_NAME/$2:$VERSION" pod_config="\$pod_config" go_path="\$GOPATH" test_coco_path="\$TEST_COCO_PATH" POD_NAME="\${POD_NAME}" pod_config_snap="\$pod_config_snap" snap_metadata_name="\$snap_metadata_name" SNAP_POD_NAME="\${SNAP_POD_NAME}" envsubst <"$base_config" >"$new_config"

    echo "$new_config"
}
generate_tests_signed_image() {
    local base_config=$1
    local new_config=$(mktemp "$TEST_COCO_PATH/../tests/$(basename ${base_config}).XXX")

    IMAGE="$2" IMAGE_SIZE="$3" RUNTIMECLASSNAME="$4" REGISTRTYIMAGE="$REGISTRY_NAME/$2" pod_config="\$pod_config" test_coco_path="\${TEST_COCO_PATH}" pod_id="\$pod_id" envsubst <"$base_config" >"$new_config"

    echo "$new_config"
}
generate_tests_encrypted_image() {
    local base_config=$1
    local new_config=$(mktemp "$TEST_COCO_PATH/../tests/$(basename ${base_config}).XXX")

    IMAGE="$2" IMAGE_SIZE="$3" RUNTIMECLASSNAME="$4" REGISTRTYIMAGE="$REGISTRY_NAME/$2" pod_config="\$pod_config" test_coco_path="\${TEST_COCO_PATH}" VERDICTDID="\$VERDICTDID" envsubst <"$base_config" >"$new_config"

    echo "$new_config"
}
generate_tests_measured_boot_image() {
    local base_config=$1
    local new_config=$(mktemp "$TEST_COCO_PATH/../tests/$(basename ${base_config}).XXX")

    IMAGE="$2" IMAGE_SIZE="$3" RUNTIMECLASSNAME="$4" HTTPS_PROXY="$https_proxy" NO_PROXY="$no_proxy" pod_config="\$pod_config" test_coco_path="\${TEST_COCO_PATH}" envsubst <"$base_config" >"$new_config"

    echo "$new_config"
}
generate_tests_offline_encrypted_image() {
    local base_config=$1
    local new_config=$(mktemp "$TEST_COCO_PATH/../tests/$(basename ${base_config}).XXX")

    IMAGE="$2" IMAGE_SIZE="$3" RUNTIMECLASSNAME="$4" REGISTRTYIMAGE="$REGISTRY_NAME/$2" pod_config="\$pod_config" test_coco_path="\${TEST_COCO_PATH}" envsubst <"$base_config" >"$new_config"

    echo "$new_config"
}
generate_cosign_image() {
    local img=$1
    # IMAGE=zcy-Z390-AORUS-MASTER.sh.intel.com/nginx:cosigned
    local registrys=$(echo $img | cut -d "/" -f1)
    local img_name=$(echo $img | cut -d "/" -f2)
    docker tag $img $registrys/cosigned/$img_name:cosigned
    docker push $registrys/cosigned/$img_name:cosigned
    IMG_DIGEST=$registrys/cosigned/$img_name:cosigned@$(docker images --digests | grep "${img}" | grep cosigned | awk '{print $3}' | sed -n "1,1p")
    /usr/bin/expect <<-EOF
	spawn cosign sign --key $TEST_COCO_PATH/../config/cosign.key $IMG_DIGEST
    expect "Enter password for private key:"
    send "intel\r"
    expect eof
EOF
    cp /usr/local/bin/cosign-linux-amd64 /usr/local/bin/cosign

}
generate_tests_cosign_image() {
    local base_config=$1
    local new_config=$(mktemp "$TEST_COCO_PATH/../tests/$(basename ${base_config}).XXX")
    local offline_base_config="$TEST_COCO_PATH/../config/aa-offline_fs_kbc-resources.json.in"
    local offline_new_config="$TEST_COCO_PATH/../tests/aa-offline_fs_kbc-resources.json"
    local p_b="$(cat $TEST_COCO_PATH/../config/policy.json | base64)"
    local policy_base64=$(echo $p_b | tr -d '\n' | tr -d ' ')
    local c_k_b="$(cat $TEST_COCO_PATH/../certs/cosign.pub | base64)"
    local cosign_key_base64=$(echo $c_k_b | tr -d '\n' | tr -d ' ')
    POLICY_BASE64="$policy_base64" COSIGN_KEY_BASE64="$cosign_key_base64" envsubst <"$offline_base_config" >"$offline_new_config"
    IMAGE="$2" IMAGE_SIZE="$3" RUNTIMECLASSNAME="$4" REGISTRTYIMAGE="$REGISTRY_NAME/$2" pod_config="\$pod_config" test_coco_path="\${TEST_COCO_PATH}" pod_id="\$pod_id" envsubst <"$base_config" >"$new_config"

    echo "$new_config"
}
#"$test_tag Test can pull an unencrypted unsigned image from an unprotected registry"
unencrypted_unsigned_image_from_unprotected_registry() {
    pod_config="$1"
    # eval $(parse_yaml $pod_config "_")
    # echo $_metadata_name
    create_test_pod $pod_config
    # if ! kubernetes_wait_cc_pod_be_running "$_metadata_name"; then
    #     # TODO: run this command for debugging. Maybe it should be
    #     #       guarded by DEBUG=true?
    #     kubectl get pods "$_metadata_name"
    #     # return 1
    # fi
    # kubectl get pods
    # kubernetes_delete_cc_pod_if_exists $_metadata_name || true

}
multiple_pods_delete() {
    local runnin_pod_config=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
    for one in ${runnin_pod_config[@]}; do
        if ! kubernetes_wait_cc_pod_be_running "$one"; then
            # TODO: run this command for debugging. Maybe it should be
            #       guarded by DEBUG=true?
            kubectl get pods "$one"
            echo "pod $one is not running"
            # return 1
        fi
    done
    for one in ${runnin_pod_config[@]}; do
        kubernetes_delete_cc_pod_if_exists $one || true
    done
}
# @test "$test_tag Test can pull an encrypted image inside the guest with decryption key"
pull_encrypted_image_inside_guest_with_decryption_key() {

    kubernetes_create_ssh_demo_pod "$1"

    pod_id=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
    kubernetes_delete_ssh_demo_pod_if_exists "$pod_id" || true
}
create_file_for_size() {
    local file_size=$1
    local file_unit=$2
    if [ ! -d "${STORAGE_FILE_D}" ]; then
        sudo mkdir "${STORAGE_FILE_D}"
    fi

    head -c $file_size${file_unit}B /dev/zero >${STORAGE_FILE_D}/file-$file_size$file_unit.txt

    docker run -dt alpine:latest
    DOCKERID=$(docker ps | grep alpine | awk '{print $1}')
    echo $DOCKERID
    docker cp ${STORAGE_FILE_D}/file-$file_size$file_unit.txt $DOCKERID:/tmp/
    docker commit $DOCKERID ci-example$file_size${file_unit,,}
    docker stop $DOCKERID && docker rm $DOCKERID
    docker tag ci-example$file_size${file_unit,,} $REGISTRY_NAME/ci-example$file_size${file_unit,,}:$VERSION
    docker push $REGISTRY_NAME/ci-example$file_size${file_unit,,}:$VERSION
}
create_image_size() {
    for IMAGE in ${IMAGE_LISTS[@]}; do
        UNIT=$(echo $IMAGE | sed 's/[^A-Z]//g')
        SIZES=$(echo $IMAGE | sed 's/[^0-9 ]//g')
        echo $UNIT
        echo $SIZES
        create_file_for_size $SIZES $UNIT
    done

}
#generate .crt and .key
generate_crt() {
    local LOCAL_REGISTRY_NAME="zcy-Z390-AORUS-MASTER.sh.intel.com"
    openssl req -newkey rsa:4096 -nodes -sha256 -keyout $TEST_COCO_PATH/../certs/domain.key -addext "subjectAltName = ${TYPE_NAME}:${LOCAL_REGISTRY_NAME}" -x509 -days 365 -out $TEST_COCO_PATH/../certs/domain.crt <<ESXU
12

12

12

12

12
ESXU
}
set_docker_certs() {
    if [ ! -d /etc/docker/certs.d/$REGISTRY_NAME:$PORT ]; then
        mkdir -p /etc/docker/certs.d/$REGISTRY_NAME:$PORT
    fi

    cp $TEST_COCO_PATH/../certs/domain.crt /etc/docker/certs.d/$REGISTRY_NAME:$PORT/ca.crt
    systemctl restart docker
}
get_certs_from_remote() {
    scp chengyu@$REGISTRY_NAME:/certs/domain.* $TEST_COCO_PATH/../certs/
    if [ "$OPERATING_SYSTEM_VERSION" == "Ubuntu" ]; then
        cp $TEST_COCO_PATH/../certs/domain.crt /usr/local/share/ca-certificates/${REGISTRY_NAME}.crt
        update-ca-certificates
    elif [ "$OPERATING_SYSTEM_VERSION" == "CentOS" ]; then
        cat $TEST_COCO_PATH/../certs/domain.crt >>/etc/pki/ca-trust/source/anchors/${REGISTRY_NAME}.crt
        update-ca-trust
    fi
    set_docker_certs
    pull_image
    # create_image_size
}
run_registry() {
    local LOCAL_REGISTRY_NAME="zcy-Z390-AORUS-MASTER.sh.intel.com"
    # delete all docker containers and images
    REGISTRY_CONTAINER=$(docker ps -a | grep "registry" | awk '{print $1}')
    if [ -n "$REGISTRY_CONTAINER" ]; then
        docker stop $REGISTRY_CONTAINER
        docker rm $REGISTRY_CONTAINER
    fi
    generate_crt
    if [ "$OPERATING_SYSTEM_VERSION" == "Ubuntu" ]; then
        cp $TEST_COCO_PATH/../certs/domain.crt /usr/local/share/ca-certificates/${LOCAL_REGISTRY_NAME}.crt
        update-ca-certificates
    elif [ "$OPERATING_SYSTEM_VERSION" == "CentOS" ]; then
        cat $TEST_COCO_PATH/../certs/domain.crt >>/etc/pki/ca-trust/source/anchors/${LOCAL_REGISTRY_NAME}.crt
        update-ca-trust
    fi
    # Deploy docker registry
    docker run -d --restart=always --name $LOCAL_REGISTRY_NAME -v $TEST_COCO_PATH/../certs:/certs \
        -e REGISTRY_HTTP_ADDR=0.0.0.0:$PORT -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
        -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key -e REGISTRY_BASIC_AUTH="emN5MTIzNDp6Y3lzdXJwYXNzMjAyMAo=" -p $PORT:$PORT registry:2
    systemctl restart docker
    # docker tag
    # pull_image
    # create_image_size
}

pull_image() {
    VERSION=latest
    for IMAGE in ${EXAMPLE_IMAGE_LISTS[@]}; do
        docker pull $IMAGE:$VERSION
        docker tag $IMAGE:$VERSION $REGISTRY_NAME/ci-$IMAGE:$VERSION
        docker push $REGISTRY_NAME/ci-$IMAGE:$VERSION
    done
}

# Create a pod configuration out of a template file.
#
# Parameters:
#	$1 - the container image.
# Return:
# 	the path to the configuration file. The caller should not care about
# 	its removal afterwards as it is created under the bats temporary
# 	directory.
#
# Environment variables:
#	RUNTIMECLASS: set the runtimeClassName value from $RUNTIMECLASS.
#
new_pod_config() {

    local base_config="$1"
    local image="$2"
    local runtimeclass="$3"
    local registryimage="$4"
    local pod_num="$5"
    local cpu_num="$6"
    local mem_size="$7"
    local new_config=$(mktemp "$TEST_COCO_PATH/../fixtures/$(basename ${base_config}).XXX")
    IMAGE="$image" RUNTIMECLASSNAME="$runtimeclass" REGISTRTYIMAGE="$registryimage" NUM="$pod_num" LIMITCPU="$cpu_num" REQUESTCPU="$cpu_num" LIMITMEM="$mem_size" REQUESTMEM="$mem_size" envsubst <"$base_config" >"$new_config"
    echo "$new_config"
}
new_pod_config_normal() {
    local base_config="$1"
    local image="$2"
    local runtimeclass="$3"
    local registryimage="$4"

    local new_config=$(mktemp "$TEST_COCO_PATH/../fixtures/$(basename ${base_config}).XXX")
    IMAGE="$image" RUNTIMECLASSNAME="$runtimeclass" REGISTRTYIMAGE="$registryimage" envsubst <"$base_config" >"$new_config"
    echo "$new_config"
}
set_runtimeclass_config() {
    local runtime_class=$1
    case $runtime_class in
    "kata-qemu")
        export CURRENT_CONFIG_FILE="configuration-qemu.toml"
        export ROOTFS_IMAGE_PATH="/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest.image"

        ;;
    "kata-clh")
        export CURRENT_CONFIG_FILE="configuration-clh.toml"
        export ROOTFS_IMAGE_PATH="/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest.image"

        ;;
    "kata-qemu-tdx")
        export CURRENT_CONFIG_FILE="configuration-qemu-tdx.toml"
        export ROOTFS_IMAGE_PATH="/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest-tdx.image"

        ;;
    "kata-clh-tdx")
        export CURRENT_CONFIG_FILE="configuration-clh-tdx.toml"
        export ROOTFS_IMAGE_PATH="/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest-tdx.image"

        ;;
    "kata-clh-tdx-eaa-kbc")
        export CURRENT_CONFIG_FILE="configuration-clh-tdx-eaa-kbc.toml"
        export ROOTFS_IMAGE_PATH="/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest-tdx.image"

        ;;
    "kata-qemu-tdx-eaa-kbc")
        export CURRENT_CONFIG_FILE="configuration-qemu-tdx-eaa-kbc.toml"
        export ROOTFS_IMAGE_PATH="/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest-tdx.image"
        ;;
    "kata")
        export CURRENT_CONFIG_FILE="configuration.toml"
        export ROOTFS_IMAGE_PATH="/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest.image"
        ;;
    esac

}
read_config() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    export GOPATH=/root/go
    export TEST_DIR="$GOPATH/src/github.com/tests"
    export RUNTIME_CONFIG_PATH="/opt/confidential-containers/share/defaults/kata-containers"
    export FIXTURES_DIR=$(jq -r '.config.podConfigPath' $TEST_COCO_PATH/../config/test_config.json)
    # export CONFIG_FILES=($(ls -l ${RUNTIME_CONFIG_PATH} | awk '{print $9}'))
    export CURRENT_CONFIG_FILE="configuration-qemu.toml"
    # TDX_STATUS=$(grep -o tdx /proc/cpuinfo)
    # if [ -z "$TDX_STATUS" ]; then
    #     export RUNTIMECLASS=$(jq -r '.config.runtimeClass[]' $TEST_COCO_PATH/../config/test_config.json)
    #     set_runtimeclass_config kata-qemu
    # else
        export RUNTIMECLASS=$(jq -r '.config.TDXRuntimeClass[]' $TEST_COCO_PATH/../config/test_config.json)
        set_runtimeclass_config kata-qemu-tdx
    # fi
    echo "$RUNTIMECLASS"
    export EAATDXRUNTIMECLASS=$(jq -r '.config.eaaTDXRuntimeClass[]' $TEST_COCO_PATH/../config/test_config.json)
    export CPUCONFIG=$(jq -r '.config.cpuNum[]' $TEST_COCO_PATH/../config/test_config.json)
    export MEMCONFIG=$(jq -r '.config.memSize[]' $TEST_COCO_PATH/../config/test_config.json)
    export PODNUMCONFIG=$(jq -r '.config.podNum[]' $TEST_COCO_PATH/../config/test_config.json)
    export katacontainers_repo_dir=$GOPATH/src/github.com/kata-containers/kata-containers
    export kata_test_repo_dir=$GOPATH/src/github.com/kata-containers/tests
    # export ROOTFS_IMAGE_PATH="/opt/confidential-containers/share/kata-containers/kata-ubuntu-latest.image"
    export CONTAINERD_CONF_FILE="/etc/containerd/config.toml"
    export OPERATOR_VERSION=$(jq -r '.file.operatorVersion' $TEST_COCO_PATH/../config/test_config.json)

    export IMAGE_LISTS=$(jq -r .file.imageLists[] $TEST_COCO_PATH/../config/test_config.json)
    export EXAMPLE_IMAGE_LISTS=$(jq -r .file.commentsImageLists[] $TEST_COCO_PATH/../config/test_config.json)
    export VERSION=latest
    export TYPE_NAME=$(jq -r '.certificates.type' $TEST_COCO_PATH/../config/test_config.json)
    export STORAGE_FILE_D=$(jq -r '.certificates.imagePath' $TEST_COCO_PATH/../config/test_config.json)

    export REPORT_FILE_PATH="$TEST_COCO_PATH/../report/"
    export OPERATING_SYSTEM_VERSION=$(cat /etc/os-release | grep "NAME" | sed -n "1,1p" | cut -d '=' -f2 | cut -d ' ' -f1 | sed 's/\"//g')
    if [ ! -d $katacontainers_repo_dir ]; then
        git clone -b CCv0 https://github.com/kata-containers/kata-containers $katacontainers_repo_dir
    fi
    if [ ! -d $kata_test_repo_dir ]; then
        git clone -b CCv0 https://github.com/kata-containers/tests $kata_test_repo_dir
    fi
}
restore() {
    # cp -r $BACKUP_PATH$RUNTIME_CONFIG_PATH ${RUNTIME_CONFIG_PATH}
    # cp -r $BACKUP_PATH$FIXTURES_DIR ${FIXTURES_DIR}
    # cp $BACKUP_PATH$ROOTFS_IMAGE_PATH ${ROOTFS_IMAGE_PATH}
    # cp $BACKUP_PATH$CONTAINERD_CONF_FILE ${CONTAINERD_CONF_FILE}
    rm -r $katacontainers_repo_dir
    # rm -r $GOPATH
}

clean_up() {
    sh -c 'rm -rf /opt/cni/bin/*'
    sh -c 'rm -rf /etc/cni /etc/kubernetes/'
    sh -c 'rm -rf /var/lib/cni /var/lib/etcd /var/lib/kubelet'
    sh -c 'rm -rf /run/flannel'
}
extract_kata_env() {
    RUNTIME_CONFIG_PATH=$(kata-runtime kata-env --json | jq -r .Runtime.Config.Path)
    RUNTIME_VERSION=$(kata-runtime kata-env --json | jq -r .Runtime.Version | grep Semver | cut -d'"' -f4)
    RUNTIME_COMMIT=$(kata-runtime kata-env --json | jq -r .Runtime.Version | grep Commit | cut -d'"' -f4)
    RUNTIME_PATH=$(kata-runtime kata-env --json | jq -r .Runtime.Path)

    # Shimv2 path is being affected by https://github.com/kata-containers/kata-containers/issues/1151
    SHIM_PATH=$(command -v containerd-shim-kata-v2)
    SHIM_VERSION=${RUNTIME_VERSION}

    HYPERVISOR_PATH=$(kata-runtime kata-env --json | jq -r .Hypervisor.Path)
    # TODO: there is no kata-runtime of rust version currently
    if [ "${KATA_HYPERVISOR}" != "dragonball" ]; then
        HYPERVISOR_VERSION=$(${HYPERVISOR_PATH} --version | head -n1)
    fi
    VIRTIOFSD_PATH=$(kata-runtime kata-env --json | jq -r .Hypervisor.VirtioFSDaemon)

    INITRD_PATH=$(kata-runtime kata-env --json | jq -r .Initrd.Path)
}
kill_stale_process() {
    # clean_env_ctr
    SHIM_PATH=$(command -v containerd-shim-kata-v2)
    HYPERVISOR_PATH=$(/opt/confidential-containers/bin/kata-runtime kata-env --json | jq -r .Hypervisor.Path)
    stale_process_union=("${stale_process_union[@]}" "${HYPERVISOR_PATH}" "${SHIM_PATH}")
    echo ${stale_process_union[@]}
    for stale_process in "${stale_process_union[@]}"; do
        [ -z "${stale_process}" ] && continue
        local pids=$(pgrep -d ' ' -f "${stale_process}")
        if [ -n "$pids" ]; then
            sudo kill -9 ${pids} || true
        fi
    done
}
delete_stale_docker_resource() {
    systemctl stop docker.service docker.socket

    # before removing stale docker dir, you should umount related resource
    for stale_docker_mount_point in "${stale_docker_mount_point_union[@]}"; do
        local mount_point_union=$(mount | grep "${stale_docker_mount_point}" | awk '{print $3}')
        if [ -n "${mount_point_union}" ]; then
            while IFS='$\n' read mount_point; do
                [ -n "$(grep "${mount_point}" "/proc/mounts")" ] && sudo umount -R "${mount_point}"
            done <<<"${mount_point_union}"
        fi
    done
    # remove stale docker dir
    for stale_docker_dir in "${stale_docker_dir_union[@]}"; do
        if [ -d "${stale_docker_dir}" ]; then
            rm -rf "${stale_docker_dir}"
        fi
    done

    systemctl disable docker.service docker.socket
    rm -f /etc/systemd/system/{docker.service,docker.socket}
}
clean_env_ctr() {
    local count_running="$(ctr c list -q | wc -l)"
    local remaining_attempts=10
    declare -a running_tasks=()
    local count_tasks=0
    local sleep_time=1
    local time_out=10

    [ "$count_running" -eq "0" ] && return 0

    # readarray -t running_tasks < <(sudo ctr t list -q)

    echo "Wait until the containers gets removed"

    for task_id in "${running_tasks[@]}"; do
        sudo ctr t kill -a -s SIGTERM ${task_id} >/dev/null 2>&1
        sleep 0.5
    done

    # do not stop if the command fails, it will be evaluated by waitForProcess
    local cmd="[[ $(sudo ctr tasks list | grep -c "STOPPED") == "$count_running" ]]" || true

    local res="ok"
    waitForProcess "${time_out}" "${sleep_time}" "$cmd" || res="fail"

    [ "$res" == "ok" ] || sudo systemctl restart containerd

    while ((remaining_attempts > 0)); do
        sudo ctr c rm $(sudo ctr c list -q) >/dev/null 2>&1

        count_running="$(sudo ctr c list -q | wc -l)"

        [ "$count_running" -eq 0 ] && break

        remaining_attempts=$((remaining_attempts - 1))
    done

    count_tasks="$(sudo ctr t list -q | wc -l)"
    if ((count_tasks > 0)); then
        die "Can't remove running contaienrs."
    fi
}
function get_version() {
    dependency="$1"
    versions_file="${katacontainers_repo_dir}/versions.yaml"

    result=$("${GOPATH}/bin/yq" r -X "$versions_file" "$dependency")
    [ "$result" = "null" ] && result=""
    echo "$result"
}

delete_crio_stale_resource() {
    # stale cri-o related binary
    # sudo rm -rf /usr/local/bin/crio
    # sudo sh -c 'rm -rf /usr/local/libexec/crio/*'
    # sudo rm -rf /usr/local/bin/crio-runc
    # stale cri-o related configuration
    sudo rm -rf /etc/crio/crio.conf
    sudo rm -rf /usr/local/share/oci-umount/oci-umount.d/crio-umount.conf
    sudo rm -rf /etc/crictl.yaml
    # stale cri-o systemd service file
    sudo rm -rf /etc/systemd/system/crio.service
}

delete_containerd_cri_stale_resource() {
    # stop containerd service
    sudo systemctl stop containerd
    # remove stale binaries
    containerd_cri_dir=$(get_version "externals.containerd.url")
    release_bin_dir="${GOPATH}/src/${containerd_cri_dir}/bin"
    # binary_dir_union=("/usr/local/bin" "/usr/local/sbin")
    # for binary_dir in ${binary_dir_union[@]}; do
    #     for stale_binary in ${release_bin_dir}/*; do
    #         sudo rm -rf ${binary_dir}/$(basename ${stale_binary})
    #     done
    # done
    # remove cluster directory
    sudo rm -rf /opt/containerd/
    # remove containerd home/run directory
    sudo rm -r /var/lib/containerd
    sudo rm -r /var/lib/containerd-test
    sudo rm -r /run/containerd
    # sudo rm -r /run/containerd-test
    # remove configuration files
    sudo rm -f /etc/containerd/config.toml
    sudo rm -f /etc/crictl.yaml
    sudo rm -f /etc/systemd/system/containerd.service
}
cleanup_network_interface() {
    FLANNEL=$(ls /sys/class/net | grep flannel)
    CNI=$(ls /sys/class/net | grep cni)

    if [ "$FLANNEL" != "" ]; then
        ip link del $FLANNEL
    fi
    if [ "$CNI" != "" ]; then
        ip link del $CNI
    fi
    # FLANNEL=$(ls /sys/class/net | grep flannel)
    # CNI=$(ls /sys/class/net | grep cni)

    # [ "$FLANNEL" != "" ] && echo "$FLANNEL doesn't clean up"
    # [ "$CNI" != "" ] && echo "$CNI doesn't clean up"
    return 0
}

delete_stale_kata_resource() {
    for stale_kata_dir in "${stale_kata_dir_union[@]}"; do
        if [ -d "${stale_kata_dir}" ]; then
            sudo rm -rf "${stale_kata_dir}"
        fi
    done
}
gen_clean_arch() {
    KATA_DOCKER_TIMEOUT=30
    # Set up some vars
    stale_process_union=("docker-containerd-shim")
    #docker supports different storage driver, such like overlay2, aufs, etc.
    docker_storage_driver=$(timeout ${KATA_DOCKER_TIMEOUT} docker info --format='{{.Driver}}')
    stale_docker_mount_point_union=("/var/lib/docker/containers" "/var/lib/docker/${docker_storage_driver}")
    stale_docker_dir_union=("/var/lib/docker")
    stale_kata_dir_union=("/var/lib/vc" "/run/vc" "/usr/share/kata-containers" "/usr/share/defaults/kata-containers")

    echo "kill stale process"
    # kill_stale_process
    echo "delete stale docker resource under ${stale_docker_dir_union[@]}"
    delete_stale_docker_resource
    echo "remove containers started by ctr"
    # clean_env_ctr

    # reset k8s service may impact metrics test on x86_64
    [ $(uname -m) != "x86_64" -a "$(pgrep kubelet)" != "" ] && sudo sh -c 'kubeadm reset -f'
    echo "Remove installed kubernetes packages and configuration"
    # Remove existing k8s related configurations and binaries.
    sh -c 'rm -rf /opt/cni/bin/*'
    sh -c 'rm -rf /etc/cni /etc/kubernetes/'
    sh -c 'rm -rf /var/lib/cni /var/lib/etcd /var/lib/kubelet'
    sh -c 'rm -rf /run/flannel'

    echo "delete stale kata resource under ${stale_kata_dir_union[@]}"
    delete_stale_kata_resource
    echo "Remove installed kata packages"
    # ${kata_test_repo_dir}/cmd/kata-manager/kata-manager.sh remove-packages
    echo "Remove installed cri-o related binaries and configuration"
    # delete_crio_stale_resource
    echo "Remove installed containerd-cri related binaries and configuration"
    delete_containerd_cri_stale_resource

    if [ "$OPERATING_SYSTEM_VERSION" == "Ubuntu" ]; then
        sudo apt-get autoremove -y $(dpkg -l | awk '{print $2}' | grep -E '^(containerd(.\io)?|docker(\.io|-ce(-cli)?))$')
    fi

    echo "Clean up stale network interface"
    cleanup_network_interface
    # info "Clean GOCACHE"
    # if command -v go >/dev/null; then
    #     GOCACHE=${GOCACHE:-$(go env GOCACHE)}
    # else
    #     # if go isn't installed, try default dir
    #     GOCACHE=${GOCACHE:-$HOME/.cache/go-build}
    # fi
    # [ -d "$GOCACHE" ] && sudo rm -rf ${GOCACHE}/*

    # info "Clean rust environment"
    # [ -f "${HOME}/.cargo/env" ] && source "${HOME}/.cargo/env"
    # if command -v rustup >/dev/null; then
    #     info "uninstall rust using rustup"
    #     sudo -E env PATH="${HOME}/.cargo/bin":$PATH rustup self uninstall -y
    # fi
    # # make sure cargo and rustup home dir are removed
    # info "remove cargo and rustup home dir"
    # sudo rm -rf ~/.cargo ~/.rustup
}
readonly op_ns="confidential-containers-system"
wait_for_process() {
    wait_time="$1"
    sleep_time="$2"
    cmd="$3"
    while [ "$wait_time" -gt 0 ]; do
        if eval "$cmd"; then
            return 0
        else
            sleep "$sleep_time"
            wait_time=$((wait_time - sleep_time))
        fi
    done
    return 1
}
test_pod_for_deploy() {
    local cmd="kubectl get pods -n "$op_ns" --no-headers |"
    cmd+="egrep -q cc-operator-controller-manager.*'\<Running\>'"
    if ! wait_for_process 120 10 "$cmd"; then
        echo "ERROR: operator-controller-manager pod is not running"
        return 1
    fi
}
test_pod_for_ccruntime() {
    local pod=""
    local cmd=""
    for pod in cc-operator-daemon-install cc-operator-pre-install-daemon; do
        cmd="kubectl get pods -n "$op_ns" --no-headers |"
        cmd+="egrep -q ${pod}.*'\<Running\>'"
        if ! wait_for_process 180 30 "$cmd"; then
            echo "ERROR: $pod pod is not running"
            return 1
        fi
    done
}
remove_cni() {
    local dev="cni0"

    rm -rf /etc/cni/net.d
    ip link set dev "$dev" down || true
    ip link del "$dev" || true
}

remove_flannel() {
    local dev="flannel.1"

    ip link set dev "$dev" down || true
    ip link del "$dev" || true
}
reset_runtime() {
    OPERATOR_VERSION=$(jq -r .file.operatorVersion $TEST_COCO_PATH/../config/test_config.json)
    export KUBECONFIG=/etc/kubernetes/admin.conf
    # kubectl delete -f $TEST_COCO_PATH/../ccruntime.yaml
    kubectl delete -k github.com/confidential-containers/operator/config/samples/ccruntime/default?ref=v${OPERATOR_VERSION}
    # kubectl delete -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml
    # kubectl delete -f $GOPATH/src/github.com/operator-${OPERATOR_VERSION}/config/samples/ccruntime.yaml
    # kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/deploy/deploy.yaml

    # kubectl delete -f $GOPATH/src/github.com/operator-${OPERATOR_VERSION}/deploy/deploy.yaml
    kubectl delete -k github.com/confidential-containers/operator/config/release?ref=v${OPERATOR_VERSION}
    # kubectl delete -k github.com/confidential-containers/operator/config/default
    kubectl delete -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    kubeadm reset -f
    # if [ -f /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf ]; then
    #     rm /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf
    #     systemctl daemon-reload
    #     systemctl restart containerd
    # fi
    # rm -r $GOPATH/src/github.com/operator-${OPERATOR_VERSION}
    # REGISTRY_CONTAINER=$(docker ps -a | grep "registry" | awk '{print $1}')
    # if [ -n "$REGISTRY_CONTAINER" ]; then
    #     docker stop $REGISTRY_CONTAINER
    #     docker rm $REGISTRY_CONTAINER
    # fi
    # rm -rf ~/.kube/ || true
    # remove_cni

    # remove_flannel
    return 0
}
install_cc() {
    OPERATOR_VERSION=$(jq -r .file.operatorVersion $TEST_COCO_PATH/../config/test_config.json)

    # wget https://github.com/confidential-containers/operator/archive/refs/tags/v${OPERATOR_VERSION}.tar.gz
    # tar -zxf v${OPERATOR_VERSION}.tar.gz -C $GOPATH/src/github.com/
    # rm v${OPERATOR_VERSION}.tar.gz
    MASTER_NAME=$(kubectl get nodes | grep "control" | awk '{print $1}')
    kubectl label node $MASTER_NAME node-role.kubernetes.io/worker=

    # sed -i 's/latest/v0.1.0/g' $GOPATH/src/github.com/operator-0.1.0/deploy/deploy.yaml
    # kubectl apply -f $GOPATH/src/github.com/operator-${OPERATOR_VERSION}/deploy/deploy.yaml
    kubectl apply -k github.com/confidential-containers/operator/config/release?ref=v${OPERATOR_VERSION}
    # kubectl apply -k github.com/confidential-containers/operator/config/default
    # kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    test_pod_for_deploy
    if [ $? -eq 1 ]; then
        echo "ERROR: operator deployment failed !"
        return 1
    fi
    # sleep 1
    # kubectl apply -f $TEST_COCO_PATH/../ccruntime.yaml
    kubectl apply -k github.com/confidential-containers/operator/config/samples/ccruntime/default?ref=v${OPERATOR_VERSION}
    # kubectl apply -f https://raw.githubusercontent.com/confidential-containers/operator/main/config/samples/ccruntime.yaml
    # kubectl apply -f $GOPATH/src/github.com/operator-${OPERATOR_VERSION}/config/samples/ccruntime.yaml
    test_pod_for_ccruntime
    if [ $? -eq 1 ]; then
        echo "ERROR: confidential container runtime deploy failed !"
        return 1
    fi
    return 0
    # kubectl get runtimeclass
}
install_runtime() {
    # kubeadm reset -f
    # swapoff -a
    # modprobe br_netfilter
    # echo 1 >/proc/sys/net/ipv4/ip_forward
    # rm /etc/systemd/system/containerd.service.d/containerd-for-cc-override.conf
    # systemctl daemon-reload
    # systemctl restart containerd
    # iptables -P FORWARD ACCEPT
    kubeadm init --cri-socket /run/containerd/containerd.sock --pod-network-cidr=10.244.0.0/16 --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers
    export KUBECONFIG=/etc/kubernetes/admin.conf
    local label="node-role.kubernetes.io/control-plane-"
    if [ ! kubectl get node "$(hostname)" -o jsonpath='{.metadata.labels}' |
        grep -q "$label" ]; then
        kubectl label node "$(hostname)" "$label="
    fi
    # kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl taint nodes --all node-role.kubernetes.io/master-
    # exit 0
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    install_cc
    if [ $? -eq 1 ]; then
        echo "ERROR: deploy cc runtime falied"
        return 1
    fi
    return 0
}

init_kubeadm() {
    # echo "PATH=$PATH" >&3
    local kubeadm_config_file="/etc/kubeadm/kubeadm.conf"
    # Bootstrap the control-plane node.
    kubeadm init --config "${kubeadm_config_file}"

    export KUBECONFIG=/etc/kubernetes/admin.conf

    # TODO: if we want to run as a regular user.
    #mkdir -p $HOME/.kube
    #sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    #sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # TODO: wait node to show up
    #kubectl get nodes
    kubectl apply -f /opt/flannel/kube-flannel.yml
    kubectl taint nodes --all node-role.kubernetes.io/master-
    # local label="node-role.kubernetes.io/control-plane"
    # if [ ! $(kubectl get node "$(hostname| tr A-Z a-z)" -o=json|jq -r ".metadata.labels" |
    #     grep -q "$label") ]; then
    #     # kubectl label node "$(hostname| tr A-Z a-z)" "$label="
    #     kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    # fi
    install_cc
    if [ $? -eq 1 ]; then
        echo "ERROR: deploy cc runtime falied"
        return 1
    fi
}
