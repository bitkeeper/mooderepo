#!/bin/bash
#########################################################################
#
# Script for building CamillaDSP package
#
# (C) bitkeeper 2021 http://moodeaudio.org
# License: GPLv3
#
#########################################################################

. ../../scripts/rebuilder.lib.sh

PKG="camilladsp_3.0.0-1moode1"

PKG_SOURCE_GIT="https://github.com/HEnquist/camilladsp.git"
PKG_SOURCE_GIT_TAG="v3.0.0"

rbl_check_cargo
rbl_prepare_clone_from_git $PKG_SOURCE_GIT $PKG_SOURCE_GIT_TAG
rbl_create_git_archive $PKG_SOURCE_GIT_TAG $BUILD_ROOT_DIR/${PKGNAME}_${PKGVERSION}.orig.tar.gz

# ------------------------------------------------------------
# Custom part of the packing

# Install deps
rbl_check_build_dep libasound2-dev

# Set install location to /usr/local/bin
rbl_patch $BASE_DIR/camilladsp_cargo-deb.patch
mkdir debian
cp $BASE_DIR/camilladsp.service debian/service

# Add to [package.metadata.deb] section of Cargo.toml:
echo "" >> Cargo.toml
echo "revision=\"$DEBVER$DEBLOC\"" >> Cargo.toml

sed -i "s/^version[ ]=[ ]\".*\"/version=\"$PKGVERSION\"/" Cargo.toml

# Build it for arch with neon support
# if [ $ARCH64 -eq 1 ]
# then
#     rustup default stable-aarch64-unknown-linux-gnu
# else
#     rustup default stable-armv7-unknown-linux-gnueabihf
# fi
echo "starting build:"
RUSTFLAGS='' cargo-deb -- --no-default-features --features websocket

if [ $? -gt 0 ]
then
    echo "${RED}Error: cargo-deb failed during build"
    exit
fi

mv target/debian/* $BUILD_ROOT_DIR
#------------------------------------------------------------

rbl_move_to_dist

echo "done"
