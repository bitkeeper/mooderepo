#!/bin/bash
#########################################################################
#
# Build recipe for patched in tree aloop driver with 384kHz support
#
# (C) bitkeeper 2021 http://moodeaudio.org
# License: GPLv3
#
#########################################################################

. ../../scripts/rebuilder.lib.sh

KERNEL_VER=$(rbl_get_current_kernel_version)

PKG="aloop_0.1-1"

# required for creating a dkms project:
DKMS_MODULE="aloop/0.1"
SRC_DIR="aloop-0.1"

ARCHS=( rpi8-rpi-v8 rpi8-rpi-2712 )

MODULE="snd-aloop.ko"
MODULE_PATH='sound/drivers'

rbl_dkms_prepare intree

#------------------------------------------------------------
# Custom part of the packing

# 1. build the modules with dkms:
dkms build --dkmstree $BUILD_ROOT_DIR ${DKMS_OPTS[@]} --sourcetree $BUILD_ROOT_DIR/source $DKMS_KERNEL_STRING $DKMS_MODULE

if [ $? -gt 0 ]
then
  echo "${RED}Error: problem during dkms build${NORMAL}"
  exit 1
fi

# 2. packed it with fpm:
# (wanted multiple arch deb which isn't possible with dkms and wanted to prevent install deps of dkms and related)

# create deb postinstall and afterremove scripts based on template:
rbl_dkms_apply_template $PKGBUILD_ROOT/scripts/templates/deb_dkms/postinstall.sh $BUILD_ROOT_DIR/postinstall.sh
rbl_dkms_apply_template $PKGBUILD_ROOT/scripts/templates/deb_dkms/afterremove.sh $BUILD_ROOT_DIR/afterremove.sh

# place build modules in the correct file tree
rbl_dkms_grab_modules

# build the package
fpm -s dir -t deb -n $PKGNAME-${KERNEL_VER} -v $PKGVERSION \
--license GPLv3 \
--category sound \
-S moode \
--iteration $DEBVER$DEBLOC \
--deb-priority optional \
--url https://github.com/moode-player/pkgbuild \
-m $DEBEMAIL \
--description "Patched aloop driver with 384kHz support." \
--post-install $BUILD_ROOT_DIR/postinstall.sh \
--after-remove  $BUILD_ROOT_DIR/afterremove.sh  \
$BUILD_ROOT_DIR/lib/=/lib/.


#------------------------------------------------------------
rbl_move_to_dist

echo "done"