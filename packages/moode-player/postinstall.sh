#!/bin/bash
#########################################################################
#
# Script for post processing afer moode-player package installation
#
# (C) bitkeeper 2022 http://moodeaudio.org
# License: GPLv3
#
#########################################################################

ACTION=$1
VERSION=$2

#TODO: make sure the build.sh sets this var
PKG_VERSION="8.0.0"

#TODO: support mode [full|update], required when the first update needs to be created
function import_stations() {
    #mode=$1
    #url=$2
    url="https://dl.cloudsmith.io/public/moodeaudio/m8y/raw/files/moode-stations-full_$PKG_VERSION.zip"
    if [ -z "$MOODE_STATIONS_URL" ]
    then
      MOODE_STATIONS_URL="$url"
    fi

    TMP_STATIONS_BACKUP="/tmp/"`basename $url`

    if [ -f $MOODE_STATIONS_URL ]
    then
      cp $MOODE_STATIONS_URL $TMP_STATIONS_BACKUP
    else
      wget --no-verbose -O $TMP_STATIONS_BACKUP $STATIONS_URL $MOODE_STATIONS_URL || true
    fi

    if [ -f $TMP_STATIONS_BACKUP $STATIONS_URL ]
    then
      /var/www/command/stationmanager.py --scope moode --how clear --import $TMP_STATIONS_BACKUP $STATIONS_URL > /dev/null
      rm -f $TMP_STATIONS_BACKUP $STATIONS_URL
    else
      echo "Couldn't import stations file from $MOODE_STATIONS_URL"
    fi
}

function on_install() {
      # perform install

      echo "** Basic optimizations"
      dphys-swapfile swapoff
      dphys-swapfile uninstall
      systemctl disable dphys-swapfile > /dev/null 2>&1
      systemctl disable cron.service > /dev/null 2>&1
      systemctl enable rpcbind > /dev/null 2>&1
      systemctl set-default multi-user.target > /dev/null 2>&1
      systemctl stop apt-daily.timer > /dev/null 2>&1
      systemctl disable apt-daily.timer > /dev/null 2>&1
      systemctl mask apt-daily.timer > /dev/null 2>&1
      systemctl stop apt-daily-upgrade.timer > /dev/null 2>&1
      systemctl disable apt-daily-upgrade.timer > /dev/null 2>&1
      systemctl mask apt-daily-upgrade.timer > /dev/null 2>&1

      echo "** Systemd enable/disable"
      systemctl daemon-reload > /dev/null 2>&1
      systemctl enable haveged > /dev/null 2>&1
      systemctl unmask hostapd > /dev/null 2>&1
      # These services are started on-demand or by moOde worker daemon (worker.php)
      disable_services=(
          bluetooth \
          bluez-alsa \
          dnsmasq \
          hciuart \
          hostapd \
          minidlna \
          mpd \
          mpd.service \
          mpd.socket \
          phpsessionclean.service \
          phpsessionclean.timer \
          shellinabox \
          shairport-sync \
          squeezelite \
          triggerhappy \
          udisks2 \
          upmpdcli)

      for service in "${disable_services[@]}"
      do
        systemctl stop "${service}" > /dev/null 2>&1
        systemctl disable "${service}" > /dev/null 2>&1
      done

      echo "** Create MPD runtime environment"
      touch /var/lib/mpd/state

      echo "** Set permissions for D-Bus (for bluez-alsa)"
      usermod -a -G audio mpd

      echo "** Create symlinks"
      [ ! -e /var/lib/mpd/music/NAS ] &&  ln -s /mnt/NAS /var/lib/mpd/music/NAS
      [ ! -e /var/lib/mpd/music/SDCARD ] && ln -s /mnt/SDCARD /var/lib/mpd/music/SDCARD
      [ ! -e /var/lib/mpd/music/USB ] && ln -s /media /var/lib/mpd/music/USB

      echo "** Create logfiles"
      touch /var/log/moode.log
      chmod 0666 /var/log/moode.log
      touch /var/log/php_errors.log
      chmod 0666 /var/log/php_errors.log

      chmod 0755 /home/pi/*.sh

      echo "** Reset permissions"
      chmod -R 0755 /var/www
      chmod -R 0755 /var/local/www
      chmod -R 0777 /var/local/www/db
      chmod -R ug-s /var/local/www

      chmod -R a+rw /usr/share/camilladsp

      echo "** Create database"
      if [ -f /var/local/www/db/moode-sqlite3.db ]
      then
        rm /var/local/www/db/moode-sqlite3.db
      fi
      # strip creation of radion stations from the sql, stations are create by the station backup import
      cat /var/local/www/db/moode-sqlite3.db.sql | grep -v "INSERT INTO cfg_radio" | sqlite3 /var/local/www/db/moode-sqlite3.db
      cat /var/local/www/db/moode-sqlite3.db.sql | grep "INSERT INTO cfg_radio" | grep "(499" | sqlite3 /var/local/www/db/moode-sqlite3.db

      # Set to Carrot for moOde 8 series
      sqlite3 /var/local/www/db/moode-sqlite3.db "UPDATE cfg_system SET value='Carrot' WHERE param='accent_color'"

      import_stations

      LIBCACHE_BASE="/var/local/www/libcache"
      echo "** Initial permissions for certain files. These also get set during moOde Worker startup"
      touch /var/local/www/playhistory.log
      touch /var/local/www/currentsong.txt
      chmod 0777 /var/local/www/playhistory.log
      chmod 0777 /var/local/www/currentsong.txt

      echo "** Establish permissions"
      chmod -R 0777 /var/local/www/db
      chown www-data:www-data /var/local/php

      echo "** Generate alsaequal binary"
      mkdir -p /opt/alsaequal/
      amixer -D alsaequal > /dev/null
      chmod 0755 /opt/alsaequal/alsaequal.bin
      chown mpd:audio /opt/alsaequal//alsaequal.bin

      echo "** Misc deletes"
      if [ -d "/var/www/html" ]
      then
        rm -rf /var/www/html
      fi
      rm -f /etc/update-motd.d/10-uname
      if [ -f /etc/motd ]
      then
        mv /etc/motd /etc/motd.default
      fi

      echo "** Update sudoers file"
      #TODO: this could be added a config file instead
      if [ ! -e /etc/sudoers.d/010_www-data-nopasswd ]; then
        echo -e "www-data\tALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/010_www-data-nopasswd
        chmod 0440 /etc/sudoers.d/010_www-data-nopasswd
      fi

      echo "** Setup config files"
      # ------------------------------------------------------------------------------------------
      # Overwrite files not owned by moode-player (a prob owned by other packages)
      # ------------------------------------------------------------------------------------------
      SRC=/usr/share/moode-player
      cp -rf $SRC/etc/* /etc/
      cp -rf $SRC/lib/* /lib/ > /dev/null 2>&1
      cp -rf $SRC/usr/* /usr/ > /dev/null 2>&1
      cp -rf $SRC/boot/* /boot/ > /dev/null 2>&1


      # ------------------------------------------------------------------------------------------
      # Patch files with sed
      # ------------------------------------------------------------------------------------------
      # From the root moode git repo find files to patch with sed:
      #  find . -name "*.sed*" |sort
      PHP_VER="7.4"

      # /etc/bluetooth/main.conf
		  # Name = Moode Bluetooth
		  # Class = 0x20041C
          #   2  = Service Class: Audio
          #   4  = Major Device Class: Audio/Video
          #   1C = Minor Device Class: Loudspeaker x14 & Headphones  x18
		  # DiscoverableTimeout = 0
          #   Stay discoverable forever
		  # ControllerMode = dual
          #   Both BR/EDR and LE transports enabled (when supported by the HW)
          #   NOTE: May need to have UI option to set ControllerMode = bredr to enable Pi-to Pi connections
      sed -i -e 's/[#]Name[ ]=[ ].*/Name = Moode Bluetooth/' \
             -e 's/[#]Class[ ]=[ ].*/Class = 0x20041C/' \
             -e 's/#DiscoverableTimeout[ ]/DiscoverableTimeout /' \
             -e 's/[#]ControllerMode[ ]=[ ].*/ControllerMode = dual/' \
             /etc/bluetooth/main.conf

      # /etc/default/mpd
      # Uncomment # MPDCONF=/etc/mpd.conf
      sed -i "s/^#[ ]MPDCONF/MPDCONF/" /etc/default/mpd

      # /etc/php/$PHP_VER/cli/php.ini
      sed -i -e "s/^post_max_size.*/post_max_size = 50M/" \
             -e "s/^upload_max_filesize.*/upload_max_filesize = 50M/" \
             -e "s/^;session.save_path.*/session.save_path = \"0;666;\/var\/local\/php\"/" \
             /etc/php/$PHP_VER/cli/php.ini

      # /etc/php/$PHP_VER/fpm/pool.d/www.conf
			# pm.max_children = 50
      sed -i "s/^pm[.]max_children.*/pm.max_children = 50/" /etc/php/$PHP_VER/fpm/pool.d/www.conf

      # /etc/php/$PHP_VER/fpm/php.ini
      # max_execution_time = 300
      # max_input_vars = 10000
      # memory_limit = -1
      # upload_max_filesize = 75M
      # session.save_path = "0;666;/var/local/php"
      sed -i -e "s/^;session.save_path.*/session.save_path = \"0;666;\/var\/local\/php\"/" \
             -e "s/^max_execution_time.*/max_execution_time = 300/" \
             -e "s/^max_input_time.*/max_input_time = -1/" \
             -e "s/^max_input_vars.*/max_input_vars = 10000/" \
             -e "s/^memory_limit.*/memory_limit = -1/" \
             -e "s/^post_max_size.*/post_max_size = 75M/" \
             -e "s/^upload_max_filesize.*/upload_max_filesize = 75M/" \
             -e "s/^;defensive.*/defensive = 1/" \
             /etc/php/$PHP_VER/fpm/php.ini

      # /etc/dnsmasq.conf
      # interface=wlan0      # Use interface wlan0
      # bind-interfaces      # Bind to the interface to make sure we aren't sending things elsewhere
      # server=127.0.0.1     # Forward DNS requests to self
      # domain-needed        # Don't forward short names
      # bogus-priv           # Never forward addresses in the non-routed address spaces.
      # dhcp-range=172.24.1.50,172.24.1.150,12h # IP address range and lease time
      sed -i -e 's/^[#]bind-interfaces$/bind-interfaces/' \
             -e 's/^[#]interface=$/interface=wlan0/' \
             -e '0,/^#server/s/#server=.*/server=127.0.0.1/' \
             -e 's/^[#]domain-needed$/domain-needed/' \
             -e 's/^[#]bogus-priv$/bogus-priv/' \
             -e '0,/^[#]dhcp-range=.*$/s/^[#]dhcp-range=.*/dhcp-range=172.24.1.50,172.24.1.150,12h/' \
             /etc/dnsmasq.conf

      # /etc/minidlna.conf
  		# media_dir=A,/var/lib/mpd/music
      # log_level=off
      # friendly_name=Moode DLNA
      # model_name=MiniDLNA
      # inotify=no
      # wide_links=yes
      sed -i -e '/^media_dir=.*/s/media_dir=.*/media_dir=A,\/var\/lib\/mpd\/music/' \
             -e 's/^[#]log_level=.*/log_level=off/' \
             -e 's/^[#]friendly_name=.*/friendly_name=Moode DLNA/' \
             -e 's/^[#]model_name=.*/model_name=MiniDLNA/' \
             -e 's/^[#]inotify=yes/inotify=no/' \
             -e 's/^[#]wide_links=no/wide_links=yes/' \
             /etc/minidlna.conf

      # /etc/modules
      # add line i2c-dev
      [[ -z $(grep "^i2c-dev" /etc/modules) ]] && sed -i '$a i2c-dev' /etc/modules

      # /etc/shairport-sync.conf
			# interpolation = "soxr";
      # audio_backend_latency_offset_in_seconds = 0.0;
      # audio_backend_buffer_desired_length_in_seconds = 0.2;
      # run_this_before_entering_active_state = "/var/local/www/commandw/spspre.sh";
      # run_this_after_exiting_active_state = "/var/local/www/commandw/spspost.sh";
      # active_state_timeout = 10.0;
      # wait_for_completion = "yes";
      # allow_session_interruption = "no";
      # session_timeout = 120;
      # output_rate = 44100;
      # output_format = "S16";
      # disable_standby_mode = "auto";
      sed -i -e 's/\/\/.*interpolation[ ]=[ ]\"auto\"[;]\(.*\)/interpolation = "soxr";\1/' \
             -e 's/\/\/[[:space:]]\+\(audio_backend_latency_offset_in_seconds\)/\1/' \
             -e 's/\/\/.*\(audio_backend_buffer_desired_length_in_seconds\)/\1/' \
             -e 's/\/\/.*\(run_this_before_entering_active_state\)[ ]=[ ]\".*\"\(.*\)/\1 = "\/var\/local\/www\/commandw\/spspre.sh"\2/' \
             -e 's/\/\/.*\(run_this_after_exiting_active_state\)[ ]=[ ]\".*\"\(.*\)/\1 = "\/var\/local\/www\/commandw\/spspost.sh"\2/' \
             -e 's/\/\/[[:space:]]\+\(active_state_timeout\)/\1/' \
             -e 's/\/\/[[:space:]]\+wait_for_completion[ ]=[ ]\"no\"[;]\(.*\)/wait_for_completion = "yes";\1/' \
             -e 's/\/\/[[:space:]]\+\(allow_session_interruption\)/\1/' \
             -e 's/\/\/[[:space:]]\+\(session_timeout\)/\1/' \
             -e 's/\/\/[[:space:]]\+output_rate[ ]=[ ]\"auto\"[;]\(.*\)/output_rate = 44100;\1/' \
             -e 's/\/\/[[:space:]]\+output_format[ ]=[ ]\"auto\"[;]\(.*\)/output_format = "S16";\1/' \
             -e 's/\/\/[[:space:]]\+disable_standby_mode[ ]=[ ]\"never\"[;]\(.*\)/disable_standby_mode = "auto";\1/' \
             /etc/shairport-sync.conf

      # /etc/nsswitch.conf
      # passwd:         compat
      # group:          compat
      # shadow:         compat
      # hosts:          files mdns4_minimal [NOTFOUND=return] dns wins mdns4
      sed -i -e '/^passwd:/s/files/compat/' \
             -e '/^group:/s/files/compat/' \
             -e '/^shadow:/s/files/compat/' \
             -e 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns wins mdns4/' \
             -e '/^hosts/s/files.*/files mdns4_minimal [NOTFOUND=return] dns wins mdns4/' \
             /etc/nsswitch.conf

      # /etc/upmpdcli.conf
	  # friendlyname = Moode UPNP
      # avfriendlyname = Moode UPNP
      # upnpav = 1
      # openhome = 0
      # checkcontentformat = 1
      # iconpath = /usr/share/upmpdcli/moode_audio.png
      # ohproductroom = Moode UPNP
      sed -i -e 's/[#]friendlyname[ ]=.*/friendlyname = Moode UPNP/' \
             -e 's/[#]avfriendlyname[ ]=.*/avfriendlyname = Moode UPNP/' \
             -e 's/[#]upnpav[ ]=.*/upnpav = 1/' \
             -e 's/[#]openhome[ ]=.*/openhome = 0/' \
             -e 's/[#]checkcontentformat[ ]=.*/checkcontentformat = 1/' \
             -e 's/[#]iconpath[ ]=.*/iconpath = \/usr\/share\/upmpdcli\/moode_audio.png/' \
             -e 's/[#]ohproductroom[ ]=.*/ohproductroom = Moode UPNP/' \
            /etc/upmpdcli.conf

      # /etc/X11/Xwrapper.config
      # allowed_users=anybody
      sed -i "s/^allowed_users.*/allowed_users=anybody/" /etc/X11/Xwrapper.config

      # /etc/systemd/journald.conf
      # SystemMaxUse=20M
      # RuntimeMaxUse=20M
      sed -i -e "s/^#SystemMaxUse.*/SystemMaxUse=20M/" \
             -e "s/^#RuntimeMaxUse.*/RuntimeMaxUse=20M/" \
             /etc/systemd/journald.conf

      cp -f $SRC/etc/nginx/nginx.conf /etc/nginx/nginx.conf

      # mpd
      touch /etc/mpd.conf
      chown mpd:audio /etc/mpd.conf
      chmod 0666 /etc/mpd.conf

      # in case any changes are made to systemd file reload config
      systemctl daemon-reload

      sync

      #--------------------------------------------------------------------------------------------------------
      # bring it alive ;-)
      #--------------------------------------------------------------------------------------------------------
      #echo "** Starting servers"
      # restart some services to pickup new configuration
      # systemctl stop nginx
      # systemctl restart php7.4-fpm
      # systemctl start nginx
      # systemctl restart smbd
      # systemctl restart nmbd
      # systemctl restart winbind

      #TODO: make this a systemd service
      # /usr/bin/udisks-glue --config=/etc/udisks-glue.conf > /dev/null 2>&1
      # systemctl restart udisks-glue

      #don't now why there is a empty database dir instead of a database file
      if [ -d /var/lib/mpd/database ]
      then
        rmdir -rf /var/lib/mpd/database
      fi

      # On boot set default playlist and output 1
cat > /etc/runonce.d/moode_first_boot <<EOL
#!/bin/bash
timeout 30s bash -c 'until mpc status; do sleep 3; done';
mpc status
if [[ $? -eq 0 ]]
then
  mpc load "Default Playlist"
  mpc enable only 1
fi
EOL

      echo "moode-player install finished, please reboot"
}

function on_upgrade() {
      #--------------------------------------------------------------------------------------------------------
      # Upgrades can come from any version:
      # - Detect if a patch is needed to apply
      # - Make the upgrade patches as fault tolerant as p needed
      #--------------------------------------------------------------------------------------------------------

      # Fix missing radio station seperator record with id 499, use instead of insert, insert or ignore
      cat /var/local/www/db/moode-sqlite3.db.sql | grep "INSERT INTO cfg_radio" | grep "(499"  | sed "s/^INSERT/INSERT OR IGNORE/" |  sqlite3 /var/local/www/db/moode-sqlite3.db

      # TODO: support update of stations
      #import_stations update

      #--------------------------------------------------------------------------------------------------------
      # bring it alive ;-)
      #--------------------------------------------------------------------------------------------------------
      # just start it to add playlist and then stop it
      #echo "wait at max 30 seconds until mpd is started ...."
      #/usr/local/bin/moodeutl -r
      #timeout 30s bash -c 'until mpc status; do sleep 3; done';
      echo "moode-player upgrade finished, please reboot"
}


if [ "$ACTION" = "configure" ] && [ -z $VERSION ] || [ "$ACTION" = "abort-remove" ]
then
      on_install
elif [ "$ACTION" = "configure" ] && [ -n $VERSION ]
then
      #--------------------------------------------------------------------------------------------------------
      # perform upgrade"
      # Existing configuration files that are change are NOT updated.
      # If you need to patch a config file this is the right place
      #--------------------------------------------------------------------------------------------------------
      on_upgrade
elif echo "${ACTION}" | grep -E -q "(abort|fail)"
then
      echo "Failed to install before the post-installation script was run." >&2
      exit 1
fi
