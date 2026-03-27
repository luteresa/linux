#!/bin/bash

OUTDIR=../out
#sudo ip tuntap add dev tap0 mode tap user $(whoami)
#sudo ip link set tap0 up
#sudo ip addr add 192.168.100.1/24 dev tap0

# for rootfs.img
#qemu-system-aarch64  -nographic  -machine virt -cpu cortex-a57  -m 8192 -smp 8 -kernel arch/arm64/boot/Image   --append "noinitrd root=/dev/vda rw console=ttyAMA0 loglevel=8"  -drive if=none,file=rootfs.img,id=hd0 -device virtio-blk-device,drive=hd0 -device virtio-net-device,netdev=net0 -netdev tap,id=net0,ifname=tap0,script=no,downscript=no 

# for $1--xxx.img
#qemu-system-aarch64  -nographic  -machine virt -cpu cortex-a57  -m 1024 -smp 8 -kernel arch/arm64/boot/Image   --append "noinitrd root=/dev/vda rw console=ttyAMA0 loglevel=8 memblock=debug "  -drive if=none,file=$1,id=hd0 -device virtio-blk-device,drive=hd0 -device virtio-net-device,netdev=net0 -netdev tap,id=net0,ifname=tap0,script=no,downscript=no
qemu-system-aarch64  -nographic  -machine virt -cpu cortex-a57  -m 1G -smp 8 -kernel $OUTDIR/arch/arm64/boot/Image   --append "noinitrd root=/dev/vda rw console=ttyAMA0 loglevel=8 "  -drive if=none,file=$1,id=hd0 -device virtio-blk-device,drive=hd0 
