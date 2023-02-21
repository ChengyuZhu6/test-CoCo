#!/usr/bin/env bash
script_name=$(basename "$0")
usage() {
    exit_code="$1"
    cat <<EOF
--------------------------------------------------
Copy local files to the guest image.

Usage:

    ${script_name} <rootfs_path> <destination_directory_path> <source_file_1> <source_file_2> ......

Example:
    ## Copy init_k8s.sh and operator.sh to etc in kata-ubuntu-latest.image
    sudo -E ./cp_to_img.sh /opt/confidential-containers/share/kata-containers/kata-ubuntu-latest.image  etc  init_k8s.sh operator.sh
--------------------------------------------------
EOF
}
# Copy local files to the guest image.
#
# Parameters:
#	$1      - destination directory in the image. It is created if not exist.
#	$2..*   - list of local files.
#
cp_to_guest_img() {
    local image_path="$1"
    local dest_dir="$2"
    shift 2 # remaining arguments are the list of files.
    local src_files=($@)
    local rootfs_dir=""

    rootfs_dir="$(mktemp -d)"

    # Open the original initrd/image, inject the agent file

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
main() {
    if [ $# -lt 3 ]; then
        echo "Expected 3 or more parameters !!!"
        usage 1
        return 1
    fi
    local image_path="$1"
    local dest_dir="$2"
    shift 2 # remaining arguments are the list of files.
    local src_files=($@)
    if [ "${#src_files[@]}" -eq 0 ]; then
        usage 1
        return 1
    fi
    cp_to_guest_img $image_path $dest_dir $src_files
    echo "Copy files to rootfs successful!!!"
}
main "$@"
