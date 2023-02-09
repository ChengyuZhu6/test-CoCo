#!/usr/bin/env bash

usage() {
    cat <<-EOF
	Utility to install/uninstall the operator.

	Use: $0 [-h|--help] [command], where:
	-h | --help : show this usage
	command : optional command (build and install by default). Can be:
	 "install": install only,
	 "uninstall": uninstall the operator.
     "function": Running function tests \$test_type \$runtimeclass 
            test_type:
            "i" image
            "p" pod_spec
            "f" functions
            "c" concurrency
	EOF
}
parse_args() {
    eval set -- $@
    echo $@
    while true; do
        case $1 in
        -h | help) usage && exit 0 ;;
        -i | install)
            echo "install"
            ./Install/install.sh
            break
            ;;
        -u | uninstall)
            echo "uninstall"
            ./Install/uninstall.sh
            break
            ;;
        -f | function)
            echo "function $2 $3"
            ./function_test/test_runner.sh -f kata-qemu
            break
            ;;
        *)
            echo "Unknown command '$1'"
            usage && exit 1
            ;;
        esac
    done
}
main() {
    parse_args $@

}

main "$@"
