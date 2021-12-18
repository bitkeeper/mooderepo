#!/bin/bash

. ../../scripts/rebuilder.lib.sh

PKG="camilladsp_0.6.3-1moode1"

PKG_SOURCE_GIT="https://github.com/HEnquist/camilladsp.git"
PKG_SOURCE_GIT_TAG="v0.6.3"

rbl_check_cargo
rbl_prepare_clone_from_git $PKG_SOURCE_GIT $PKG_SOURCE_GIT_TAG
rbl_create_git_archive $PKG_SOURCE_GIT_TAG ../${PKGNAME}_${PKGVERSION}.orig.tar.gz

# ------------------------------------------------------------
# Custom part of the packing

# install deps
rbl_check_build_dep libasound2-dev

#Add to [package.metadata.deb] section of Cargo.toml:
echo "[package.metadata.deb]" >> Cargo.toml
echo "revision=\"$DEBVER$DEBLOC\"" >> Cargo.toml


# Build it for arch with neon support
RUSTFLAGS='-C target-feature=+neon -C target-cpu=native' cargo-deb -- --no-default-features --features alsa-backend --features websocket
if [[ $? -gt 0 ]]
then
    echo "${RED}Error: cargo-deb failed during build"
    exit
fi

mv target/debian/* $BUILD_ROOT_DIR
#------------------------------------------------------------

rbl_move_to_dist

echo "done"

