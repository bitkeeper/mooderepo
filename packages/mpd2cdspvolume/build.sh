#!/bin/bash
#########################################################################
#
# Build recipe for mpd2cdspvolume debian package
#
# (C) bitkeeper 2023 http://moodeaudio.org
# License: GPLv3
#
#########################################################################

. ../../scripts/rebuilder.lib.sh


PKG="mpd2cdspvolume_0.1.0-1moode1"

PKG_SOURCE_GIT="https://github.com/bitkeeper/mpd2cdspvolume.git"
PKG_SOURCE_GIT_TAG="v0.1.0"

rbl_prepare_clone_from_git $PKG_SOURCE_GIT $PKG_SOURCE_GIT_TAG

#------------------------------------------------------------
# Custom part of the packing

mkdir -p root/usr/local/bin
cp mpd2cdspvolume.py root/usr/local/bin/mpd2cdspvolume
cp cdspstorevolume.sh root/usr/local/bin/cdspstorevolume

chmod a+x root/usr/local/bin/mpd2cdspvolume
chmod a+x root/usr/local/bin/cdspstorevolume

# build the package
fpm -s dir -t deb -n $PKGNAME -v $PKGVERSION \
--license MIT \
--category misc \
-S moode \
--iteration $DEBVER$DEBLOC \
-a all \
--deb-priority optional \
--url https://github.com/moode-player/pkgbuild \
-m $DEBEMAIL \
--license LICENSE \
--description "Service for synchronizing MPD volume to CamillaDSP." \
--deb-systemd mpd2cdspvolume.service \
--depends python3-mpd2 \
--depends python3-camilladsp \
root/usr/=/usr/.

if [[ $? -gt 0 ]]
then
  exit 1
fi

#-----------------------------------------------------------
rbl_move_to_dist
echo "done"
