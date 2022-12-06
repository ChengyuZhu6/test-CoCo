load ../run/lib.sh
load ../run/cc_deploy.sh
@test "Test uninstall operator" {
	#skip
	run -0 reset_runtime
	[ "$output" = "foo: no such file 'nonexistent_filename'" ]
}
