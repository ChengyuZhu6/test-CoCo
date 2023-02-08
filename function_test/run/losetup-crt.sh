#!/bin/bash
if [ ! -f $1 ]; then
    echo "$1 does not exist"
    exit 1
fi

FLAG=$2
MNT_DIR=$(basename -s .img $1)

echo "MNT_DIR=$MNT_DIR"
#startsector=$(file $1 | awk '{match($11,/(.*),/,a);print a[1]}' )
startsector=$(fdisk -l $1 | tail -n 1 | awk '{print $2}')
#echo $?
echo $startsector
mkdir -p /mnt/$MNT_DIR || exit 1
losetup -Pf $1 || exit 1
DEV="$(losetup -l | grep "$1" | awk '{print $1}')p1"
echo $DEV
if [ "$startsector" == "" ]; then
    echo "mount $DEV"
    mount $DEV /mnt/$MNT_DIR || exit 1
else
    echo "mount $DEV with offset"
    #mount -ooffset=$((512*$startsector)) $DEV /mnt/$MNT_DIR || exit 1
    mount $DEV /mnt/$MNT_DIR || exit 1
fi

if [ $FLAG == "c" ]; then

    cat $TEST_COCO_PATH/../certs/domain.crt >>/mnt/$MNT_DIR/etc/ssl/certs/ca-certificates.crt

    # cp /usr/local/bin/attestation-agent /mnt/$MNT_DIR/usr/local/bin/attestation-agent
    # cp $GOPATH/src/github.com/attestation-agent/app/target/x86_64-unknown-linux-gnu/release/attestation-agent /mnt/$MNT_DIR/usr/local/bin/attestation-agent
elif [ $FLAG == "r" ]; then
    cp ./mnt/ca-certificates.crt /mnt/$MNT_DIR/etc/ssl/certs/ca-certificates.crt
    # cp ./mnt/attestation-agent /mnt/$MNT_DIR/usr/local/bin/attestation-agent
else
    pushd /mnt/$MNT_DIR
    bash
    popd
fi

umount /mnt/$MNT_DIR
echo "umount and detach.."
losetup -D
echo "rm /mnt/$MNT_DIR .."
rm -r /mnt/$MNT_DIR
