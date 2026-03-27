#!/bin/bash
set -e

OUT=../out
DEF=arch/arm64/configs/yos_defconfig
ARCH=arm64

make O=$OUT ARCH=$ARCH yos_defconfig
make O=$OUT ARCH=$ARCH menuconfig
make O=$OUT ARCH=$ARCH savedefconfig
cp $OUT/defconfig $DEF

echo "updated $DEF"
