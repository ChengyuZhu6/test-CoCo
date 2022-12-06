load ../run/lib.sh
load ../run/cc_deploy.sh
@test "Test uninstall operator" {
	#skip
	reset_runtime
	[ "$status" -ne 0 ]
	[ "$output" = "foo: no such file 'nonexistent_filename'" ]
}
