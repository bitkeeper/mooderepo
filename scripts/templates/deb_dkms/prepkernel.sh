#!/bin/bash
#########################################################################
#
# Prep a kernel source for a certain architecture version
#
# (C) bitkeeper 2022 http://moodeaudio.org
# License: GPLv3
#
#########################################################################
echo "prepkernel"
index=$1

declare -A ARCHS
ARCHS=(["v7+"]=0 ["v7l+"]=1 ["v8+"]=2)
INDEX=${ARCHS[$index]}
if [ -z $INDEX ]
then
    echo "Error: For arch $index no architecture lookup found!"
    exit 1
fi

# lookup lists for different architecture indexes:
SYMBOLS=( 7 7l 8)
DEFCONFIGS=(bcm2709_defconfig bcm2711_defconfig bcm2711_defconfig)

KERNEL_HASH=`rpi-source --dry-run --skip-update --download-only --dest /tmp | grep -i 'firmware' | sed -r 's/.*revision[:][ ]//'`
SYMBOL="${SYMBOLS[$INDEX]}"
DEFCONFIG="${DEFCONFIGS[INDEX]}"
echo "Prepping kernel source for module build."
echo "kernel    : $(uname -r) (current running)"
echo "arch      : $index"
echo "hash      : $KERNEL_HASH"
echo "symvers   : $SYMBOL"
echo "defconfig : $DEFCONFIG"
echo "location  : $(pwd)"
echo ""

make mrproper
if [ ! -f "Module$SYMBOL.symvers" ]
then
   wget --no-verbose -O ./Module$SYMBOL.symvers https://raw.githubusercontent.com/raspberrypi/rpi-firmware/$KERNEL_HASH/Module$SYMBOL.symvers
fi
cp ./Module$SYMBOL.symvers ./Module.symvers
make $DEFCONFIG
make prepare
make modules_prepare
