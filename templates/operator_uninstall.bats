load ../run/lib.sh
@test "Test uninstall operator" {
	#skip
	reset_runtime
	if [ $? -ne 0 ]; then
        echo "ERROR: uninstall operator failed !" >&3
        return 1
    fi
	return 0
}
