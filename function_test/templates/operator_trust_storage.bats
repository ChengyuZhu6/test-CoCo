@test "Test uninstall open-local" {
	helm delete open-local
	rm -r $GOPATH/open-local
	#reset_runtime
}
