load ../run/lib.sh
load ../run/cc_deploy.sh
@test "Test uninstall operator" {
	#skip
	run reset_runtime
	[ "$status" -ge 1 ]
	[ "$output" = "foo: no such file 'nonexistent_filename'" ]
}
