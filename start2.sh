qemu-system-aarch64 -machine virt -cpu cortex-a57 -machine type=virt -m 1024 -smp 4 -kernel arch/arm64/boot/Image --append "noinitrd root=/dev/vda rw console=ttyAMA0 loglevel=8"  -nographic -drive if=none,file=rootfs_ext4.img,id=hd0 -device virtio-blk-device,drive=hd0 --fsdev local,id=kmod_dev,path=$PWD/k_shared,security_model=none -device virtio-9p-device,fsdev=kmod_dev,mount_tag=kmod_mount

