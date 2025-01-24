#!/bin/bash
#########################################################################
#
# Build recipe for camillagui + camillagui-backend debian package
#
# (C) bitkeeper 2021 http://moodeaudio.org
# License: GPLv3
#
#########################################################################

. ../../scripts/rebuilder.lib.sh

PKG="camillagui_3.0.0-1moode2"

PKG_SOURCE_GIT="https://github.com/HEnquist/camillagui.git"
PKG_SOURCE_GIT_TAG="v3.0.0"
# PKG_SOURCE_GIT_TAG="mixer_matrix"

PKG_SOURCE_GIT_BACKEND="https://github.com/HEnquist/camillagui-backend.git"
PKG_SOURCE_GIT_TAG_BACKEND="v3.0.0"

# gui is a react app
rbl_check_build_dep npm
# For packign fpm is used, which is created with Ruby
rbl_check_fpm

rbl_prepare_clone_from_git $PKG_SOURCE_GIT $PKG_SOURCE_GIT_TAG

# ------------------------------------------------------------
# Custom part of the packing

echo "build root : $BUILD_ROOT_DIR"
# ---------------------------------------------------------------
# A. camillagui
# ---------------------------------------------------------------
# upgrade npm package will cause a strange layout on the files tab
# (maybe todo with the old npm/Typescript tooling on the Pi?)
# git revert  --no-edit a7e09fdb81b25df91b033786a9109ab0514ee05e

# add option to hide files tab on expert mode:
rbl_patch $BASE_DIR/camillagui_hide_files.patch
# rbl_patch $BASE_DIR/camillagui_remove_quick_config.patch
# installing npm deps with npm ci failed, so use npm install instead

npm install
npx browserslist@latest --update-db

npm run-script build --force
if [[ ! $? -eq 0 ]]
then
    echo "${RED} Error: npm build  failed.${NORMAL}"
    cd ..
    exit 1
else
    echo "${GREEN} npm build is ok.${NORMAL}"
fi
cd ..

# ---------------------------------------------------------------
# B. camillagui-backend
# ---------------------------------------------------------------
git clone $PKG_SOURCE_GIT_BACKEND
cd camillagui-backend
# git checkout -b $PKG_SOURCE_GIT_TAG_BACKEND origin/$PKG_SOURCE_GIT_TAG_BACKEND
git checkout -b $PKG_SOURCE_GIT_TAG_BACKEND $PKG_SOURCE_GIT_TAG_BACKEND
# add option to hide files tab on expert mode:
rbl_patch $BASE_DIR/camillagui_backend_hide_files.patch
rbl_patch $BASE_DIR/camillagui_backend_default_shortcuts.patch
rm -rf backend/*.orig
cd ..

# ---------------------------------------------------------------
# C. packing
# ---------------------------------------------------------------

# Create the package
# setup a directory structure for the files which should end up in the deb file:
rm -rf package
mkdir -p package/opt/camillagui
mkdir -p package/etc/systemd/system

# copy the required files into the directory structure
cp -r camillagui-$PKGVERSION/build camillagui-backend/backend camillagui-backend/config camillagui-$PKGVERSION/LICENSE.txt camillagui-backend/main.py camillagui-backend/README.md package/opt/camillagui
if [[ ! $? -eq 0 ]]
then
    echo "${RED} Error: Copy files failed.${NORMAL}"
    exit 1
else
    echo "${GREEN} Copy files is ok.${NORMAL}"
fi
cp $BASE_DIR/css-variables.css package/opt/camillagui/build
cp $BASE_DIR/camillagui.yml package/opt/camillagui/config
cp $BASE_DIR/gui-config.yml package/opt/camillagui/config
cp $BASE_DIR/camillagui.service package/etc/systemd/system

# build a deb files based on the directory structure
fpm -s dir -t deb -n $PKGNAME -v $PKGVERSION \
--license GPLv3 \
--category sound \
-S moode \
--iteration $DEBVER$DEBLOC \
-a all \
--deb-priority optional \
--url https://github.com/HEnquist/camilladsp \
-m moodeaudio.org \
--description 'CamillaGUI is a web-based GUI for CamillaDSP.' \
--depends python3-camilladsp \
--depends python3-camilladsp-plot \
--depends python3-aiohttp \
--depends python3-websocket \
--depends python3-jsonschema \
--depends python3-numpy \
--pre-install $BASE_DIR/deb_preinstall.sh \
--before-remove $BASE_DIR/deb_beforeremove.sh \
--after-install $BASE_DIR/deb_postinstall.sh \
--deb-no-default-config-files \
package/opt/camillagui/.=/opt/camillagui \
package/etc/=/etc/.

if [[ $? -gt 0 ]]
then
    echo "${RED}Error: failure during fpm.${NORMAL}"
    exit 1
fi


# mv ${PKGNAME}_${FULL_VERSION}*.deb $BASE_DIR
#cd $BASE_DIR

#------------------------------------------------------------
rbl_move_to_dist

echo "done"
