# Test-CoCo
This repository is the home of the Test-CoCo code .

## Introduction

Test-CoCo contains function tests for testing the Confidential Containers code repositories.


## Run
./test_runner.sh -h

```bash
# ./test_runner.sh -h
Overview:
    Tests for confidential containers
    test_runner.sh <command>
Commands:
        -u:     Multiple pod spec and container image tests
        -e:     Encrypted image tests
        -s:     Signed image tests
        -t:     Trusted storage for container image tests
        -n:     Attestation tests
        -b:     Measured boot tests
        -m:     Multiple registries tests
        -i:     Image sharing tests
        -o:     OnDemand image pulling tests
        -p:     TD preserving tests
        -c:     Common Cloud Native projects tests
        -a:     All tests
        -h:     help
```

Result of example:
```bash
# ./test_runner.sh -a
Test install operator|Test unencrypted unsigned image|Test encrypted image|Test signed image|Test trust storage|Test attestation|Test measured boot|Test multiple registries|Test image sharing|Test OnDemand image pulling|Test TD preserving|Test common cloud native projects|Test uninstall operator
Ubuntu 20.04.5 LTS \n \l
HostName: zcy-Z390-AORUS-MASTER
Kernel: 5.15.0-52-generic
Product Name: Z390 AORUS MASTER
Serial Number: WO155815L02S001

--------BIOS:-------
Vendor: American Megatrends Inc.
Version: F11c
Release Date: 12/18/2019
Runtime Size: 64 kB
ROM Size: 16 MB
BIOS Revision: 5.13

--------CPU:-------
CPU 运行模式：                   32-bit, 64-bit
CPU:                             8
在线 CPU 列表：                  0-7
CPU 系列：                       6
型号名称：                       Intel(R) Core(TM) i7-9700 CPU @ 3.00GHz
CPU MHz：                        3000.000
CPU 最大 MHz：                   4700.0000
CPU 最小 MHz：                   800.0000

------内存:------
Physical Memory Array
Location: System Board Or Motherboard
Use: System Memory
Error Correction Type: None
Maximum Capacity: 64 GB
Error Information Handle: Not Provided
Number Of Devices: 4

Size: 16384 MB          Speed: 2666 MT/s
Size: 16384 MB          Speed: 2666 MT/s
Size: 16384 MB          Speed: 2666 MT/s
Size: 16384 MB          Speed: 2666 MT/s

-------磁盘:-------
  *-namespace               
       description: NVMe namespace
       physical id: 1
       logical name: /dev/nvme0n1
       size: 953GiB (1024GB)
       capabilities: partitioned partitioned:dos
       configuration: logicalsectorsize=512 sectorsize=512 signature=d6ce0081
  *-disk
       description: ATA Disk
       product: CT1000MX500SSD1
       physical id: 0.0.0
       logical name: /dev/sda
       version: 032
       size: 931GiB (1TB)
       capabilities: gpt-1.00 partitioned partitioned:gpt
       configuration: ansiversion=5 guid=9ff0a851-5b2b-42a6-9d6c-8107e045fb0b logicalsectorsize=512 sectorsize=4096



--------Operator Version--------
Operator Version: v0.1.0

--------Test Cases--------
unsigned unencrpted images: 
    busybox 1.24MB
    redis 117MB
trust storage images: 
    busybox 1.24MB
    redis 117MB
signed images: 
    busybox 1.24MB
    redis 117MB
encrypted images: 
    busybox 1.24MB
    redis 117MB
Attestation: TODO
Measured boot: TODO
Multiple registries: TODO
Image sharing: TODO
OnDemand image pulling: TODO
TD Preserving: TODO
Common Cloud Native projects: TODO


install Kubernetes
k8s_non_tee_cc.bats
 ✓ Test install operator
 ✓ Test unencrypted unsigned image
 ✓ Test trust storage
 ✓ Test signed image
 - Test encrypted image (skipped: need to rebuild rootfs including eaa_bkc and guest kernel to test encrypted image, which is not supported in branch main of operator)
 - Test attestation (skipped: TODO)
 - Test measured boot (skipped: TODO)
 - Test multiple registries (skipped: TODO)
 - Test image sharing (skipped: TODO)
 - Test OnDemand image pulling (skipped: TODO)
 - Test TD preserving (skipped: TODO)
 - Test common cloud native projects (skipped: TODO)
 ✓ Test uninstall operator

13 tests, 0 failures, 8 skipped
```


