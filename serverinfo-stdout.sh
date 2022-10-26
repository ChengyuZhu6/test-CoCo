#!/bin/sh
SCRIPT_FOLDER=$(dirname "$0")
cat /etc/issue | sed -n '1p'
uname -a | cut -d ' ' -f 2 | sed s/^/HostName:' '/
uname -a | cut -d ' ' -f 3 | sed s/^/Kernel:' '/
dmidecode -t system | awk -f $SCRIPT_FOLDER/serverinfo/servername.awk
echo "\n--------BIOS:-------"
dmidecode -t bios|grep Vendor|sed 's/^[ \t]*//g'
dmidecode -t bios|awk -f $SCRIPT_FOLDER/serverinfo/bios.awk|sed 's/^[ \t]*//g'
echo "\n--------CPU:-------"
lscpu | grep 'CPU'|egrep -v 'NUMA|Vulnerability'
echo "\n------内存:------"
dmidecode -t memory | grep -A7 Physical|sed 's/^[ \t]*//g'
dmidecode -t memory | grep -e "Size.*[0-9]" -A8 | awk -f $SCRIPT_FOLDER/serverinfo/mem.awk|sed 's/^[ \t]*//g'
echo "\n-------磁盘:-------"
lshw -class disk|egrep -v "bus|serial"