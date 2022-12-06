load ../run/lib.sh
@test "Test uninstall operator" {
	#skip
	reset_runtime
	echo $? >&3
	if [ $? -ne 0 ]; then
        echo "ERROR: uninstall operator failed !" >&3
        return 1
    fi
	return 0
}
