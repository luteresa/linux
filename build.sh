export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

#make yos_defconfig
OUTDIR='../out'
#make O=../out ARCH=arm64 yos_defconfig
#make O=../out ARCH=arm64 menuconfig
#make O=../out ARCH=arm64 savedefconfig
make O=$OUTDIR  -j 16
