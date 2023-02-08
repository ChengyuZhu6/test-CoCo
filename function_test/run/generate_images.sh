source $(pwd)/function_test/run/common.bash
source $(pwd)/function_test/run/lib.sh

read_config
echo "start generate images"
# pull_image
for image in ${EXAMPLE_IMAGE_LISTS[@]}; do
    generate_encrypted_image ci-$image
    # exit 0
    # generate_offline_encrypted_image ci-$image
    # generate_cosign_image $REGISTRY_NAME/ci-$image
    # generate_simple_sign_image
done
echo "generate images success"