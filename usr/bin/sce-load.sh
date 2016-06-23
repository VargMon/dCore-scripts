#!/bin/busybox ash
# (c) Robert Shingledecker 2013
# Contributions by Jason Williams
. /etc/init.d/tc-functions

useBusybox
checknotroot
PROG_NAME=$(basename $0)
KERNELVER=$(uname -r)
unset BOOTING ONDEMAND SUPPRESS
FORCE="n"  # Overwrite system files default to no. Use -f to force overwrite.
SAVED_DIR=`pwd`
HERE=`pwd`
#ONBOOTNAME="$(getbootparam lst 2>/dev/null)"

if [ -f /tmp/.sceloadlock ]; then
	LOCK=`cat /tmp/.sceloadlock`
	if /bb/ps | /bb/grep "$LOCK " | grep "sce-load" > /dev/null 2>&1; then
		echo "Another sce-load session is presently in use, exiting.."
		exit 1
	fi
fi

echo "$$" > /tmp/.sceloadlock


[ -f /tmp/select.ans ] && sudo rm /tmp/select.ans

[ -n "$ONBOOTNAME" ] || ONBOOTNAME="onboot.lst"

[ -f /tmp/.installed ] || touch /tmp/.installed

abort(){
        echo "Run  sce-load --help  for usage information".
	exit 2
}

abort_to_saved_dir(){
	cd "$SAVED_DIR"
	[ -d /tmp/tcloop/"$APPNAME" ] && sudo rmdir /tmp/tcloop/"$APPNAME"
	exit 1
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
	echo " "
	echo "${YELLOW}sce-load - Load SCE(s) and any SCE(s) that it depends on into RAM for use,"
	echo "           SCEs typically located in /etc/sysconfig/tcedir/sce/.${NORMAL}"
	echo " "
	echo "Usage:"
	echo " "
	echo "${YELLOW}"sce-load"${NORMAL}             Menu prompt, select SCE to load."
	echo "${YELLOW}"sce-load SCE"${NORMAL}         Directly load the named SCE."
	echo "${YELLOW}"sce-load SCE1 SCE2"${NORMAL}   Directly load multiple SCEs."
	echo "${YELLOW}"sce-load -b SCE"${NORMAL}      Internal use only, to load SCEs at boot time."
	echo "${YELLOW}"sce-load -d SCE"${NORMAL}      Write any debug information to var/log/sce.log."
	echo "${YELLOW}"sce-load -s SCE"${NORMAL}      Suppress loading outputs like ' *.sce: OK '."
	echo " "
exit 1
fi


choose(){
	TMP=/tmp/select.$$
	SCE=/tmp/sce.$$
	MOUNTED=/tmp/mounted.$$
	ls -1 /etc/sysconfig/tcedir/sce/*.sce|awk 'BEGIN{FS="/"}{size=length($6)-4; print substr($6,0,size)}' > "$SCE"
	mount | awk '$3 ~ /tcloop/{print substr($3,13)}' > "$MOUNTED"

	cat "$SCE" "$MOUNTED" "$MOUNTED" | sort | uniq -u > "$TMP"
	for I in `cat "$TMP"`; do 
		grep "^$I:" /tmp/.debinstalled > /dev/null 2>&1 && sed -i "/^$I$/d" "$TMP"
	done
	rm "$SCE"
	rm "$MOUNTED"

	if [ ! -s "$TMP" ]; then
		echo "Nothing found to load, exiting.."
		exit 1
	fi
	select2 "Select SCE to load." "$TMP"
	TARGETAPP="$(cat  /tmp/select.ans)"
	rm "$TMP"
	if [ "$TARGETAPP" == "" ]; then
		echo "No selection made, exiting.."
		exit 0
	fi
	[ "$SUPPRESS" ] || echo "Loading "$TARGETAPP"..."

}

processAPP(){
	APPNAME=${TARGETAPP%%.sce}
	if [ ${TARGETAPP} == ${APPNAME} ]; then TARGETAPP=${TARGETAPP}.sce; fi
	APPNAME="${APPNAME/-KERNEL/-${KERNELVER}}"
	TARGETAPP="${TARGETAPP/-KERNEL.sce/-${KERNELVER}.sce}"

	#THISAPP=`basename $APPNAME .sce`
	if grep "^$APPNAME:" /tmp/.debinstalled > /dev/null 2>&1; then
		if [ "$BOOTING" ]; then
			continue
		else
		        [ "$SUPPRESS" ] || echo "${YELLOW}"$APPNAME"${NORMAL} is already loaded!"
			continue
		fi
	fi
	if [ -d /tmp/tcloop/"$APPNAME" ]; then
		if [ "$BOOTING" ]; then
			continue
		else
		        [ "$SUPPRESS" ] || echo "${YELLOW}"$APPNAME"${NORMAL} is already loaded!"
			continue
		fi
	fi
	if [ -f "$TARGETAPP" ]; then
		:
	elif [ -f "$TCEDIR"/sce/"$TARGETAPP" ]; then
		TARGETAPP="$TCEDIR"/sce/"$TARGETAPP"
	else
		echo "'"$TARGETAPP"' does not exist, not loading.."
		abort_to_saved_dir
	fi
	#FROMWHERE=`dirname "$TARGETAPP"` && cd "$FROMWHERE"
	EXTENSION=`basename "$TARGETAPP"`
	install "$TARGETAPP"
	[ "$SUPPRESS" ] || echo "$TARGETAPP: OK"
}

while getopts bdsf OPTION
do
	case ${OPTION} in
		b) BOOTING=TRUE ;;
		s) SUPPRESS=TRUE ;;
		f) FORCE="y" ;;
		d) DEBUG=TRUE ;;
		*) abort ;;
	esac
done
shift `expr $OPTIND - 1`

if grep -q " debug " /proc/cmdline > /dev/null 2>&1; then
	DEBUG=TRUE
fi

startupscript_check() {
	APPSSS_D="/tmp/tcloop/${APPNAME}/usr/local/tce.installed"
	if [ -d "$APPSSS_D" ]
	then
		for SS in $(ls "$APPSSS_D" )
		do
			if [ ! -e "$TCEINSTALLED"/"$SS" ]
			then
				[ -x "$APPSSS_D"/"$SS" ] && echo "$TCEINSTALLED"/"$SS" >> /tmp/ss$$.lst
			fi
		done
	else
		touch "$TCEINSTALLED"/${APPNAME}
	fi
}

update_system() {
	if [ "$BOOTING" ]; then
		[ "$MODULES" ] && sudo touch /etc/sysconfig/newmodules
	else
		if [ "$MODULES" ]; then
			sudo depmod -a > /dev/null 2>&1
			sudo /sbin/udevadm trigger > /dev/null 2>&1
		fi
	fi
	if [ -s /tmp/ss$$.lst ]; then
		if [ "$BOOTING" ] ; then
			cat /tmp/ss$$.lst >> /tmp/setup.lst
		else
			for SS in $(cat /tmp/ss$$.lst | grep -v "tce.installed/$APPNAME$")
			do
				APP=`basename "$SS"`
				if ! grep "^$APP:" /tmp/.installed > /dev/null 2>&1; then
					if [ "$DEBUG" == "TRUE" ]; then
					  echo "$APP:" >> /tmp/.installed
					  sudo echo "$APP:" | sudo tee -a /var/log/sce.log > /dev/null 2>&1
					  sudo $SS 2>&1 | sudo tee -a /var/log/sce.log > /dev/null 2>&1
					else
					  sudo $SS > /dev/null 2>&1 
					  echo "$APP:" >> /tmp/.installed
					fi
					
				fi
			done
			APP=`basename /usr/local/tce.installed/"$APPNAME"`
			if [ "$DEBUG" == "TRUE" ]; then
				echo "$APP:" >> /tmp/.installed
				sudo echo "$APP:" 2>&1 | sudo tee -a /var/log/sce.log > /dev/null 2>&1
				sudo /usr/local/tce.installed/"$APPNAME" 2>&1 | sudo tee -a /var/log/sce.log > /dev/null 2>&1
			else	
				echo "$APP:" >> /tmp/.installed
				sudo /usr/local/tce.installed/"$APPNAME" >> /dev/null 2>&1 
			fi
		   FREEDESKTOP="/tmp/tcloop/"$APPNAME"/usr/share/applications"
		   if [ "$(ls -A $FREEDESKTOP 2>/dev/null)" ]; then
		    	for F in $(ls "$FREEDESKTOP"/*.desktop | grep -v "tinycore-"| grep -Ev '(~[1-9][1-9]*)'.desktop); do
		     		if ! grep "OnlyShowIn" "$F" > /dev/null 2>&1 && ! grep "NoDisplay=true" "$F" > /dev/null 2>&1; then
		       			EXTNAME="${F%.desktop}"
		      			EXTNAME="${EXTNAME##*/}"
		       			desktop.sh "$EXTNAME" > /dev/null 2>&1
		     		fi
		    	done
		   fi
		   
		   FREEDESKTOP="/tmp/tcloop/"$APPNAME"/usr/local/share/applications"
		   if [ "$(ls -A $FREEDESKTOP 2>/dev/null)" ]; then
		    	for F in $(ls "$FREEDESKTOP"/*.desktop | grep -v "tinycore-"| grep -Ev '(~[1-9][1-9]*)'.desktop); do
		     		if ! grep "OnlyShowIn" "$F" > /dev/null 2>&1 && ! grep "NoDisplay=true" "$F" > /dev/null 2>&1; then
		       				EXTNAME="${F%.desktop}"
		       				EXTNAME="${EXTNAME##*/}"
		       				desktop.sh "$EXTNAME" > /dev/null 2>&1
		     		fi
		    	done
		   fi
		   
		fi
		
		rm /tmp/ss$$.lst
	fi
	sudo /sbin/ldconfig 2>/dev/null
	if [ -f /tmp/tcloop/"$APPNAME"/usr/local/postinst/libglib2.0-0 ]; then
		sudo /usr/local/postinst/libglib2.0-0
	fi
	if [ -f /tmp/tcloop/"$APPNAME"/usr/local/postinst/libgtk2.0-0 ]; then
		sudo /usr/local/postinst/libgtk2.0-0
	fi
	if [ -f /tmp/tcloop/"$APPNAME"/usr/local/postinst/libgtk-3-0 ]; then
		sudo /usr/local/postinst/libgtk-3-0
	fi
}

install(){
	unset MODULES EMPTYEXT

	if [ "$LANG" != "C" ]; then
		LOCALEEXT="${1%.sce}-locale.sce"
		[ -f "$LOCALEEXT" ] && install "$LOCALEEXT"
	fi

	THISAPP="$1"
	APPNAME=$(getbasefile "$THISAPP" 1)

	[ -d /tmp/tcloop/"$APPNAME" ] || sudo mkdir -p /tmp/tcloop/"$APPNAME"
	awk -v appname="/tmp/tcloop/$APPNAME" ' { if ( $2 == appname )  exit 1 }' /etc/mtab
	[ "$?" == 1 ] || sudo mount "$THISAPP" /tmp/tcloop/"$APPNAME" -t squashfs -o loop,ro,bs=4096 2>&1
	[ "$?" == 0 ] || abort_to_saved_dir
	[ -z "`ls /tmp/tcloop/${APPNAME}`" ] && EMPTYEXT=1
	[ "`sudo find /tmp/tcloop/${APPNAME} -mindepth 1 -maxdepth 2 | wc -l`" -le 1 ] && EMPTYEXT=1
	> /tmp/"$APPNAME".lnklst
	if [ -z "$EMPTYEXT" ]; then
		startupscript_check
		## Copy properly preserved symlinks to the filesystem, not create links to the links.
		cd /tmp/tcloop/"$APPNAME"
		for F in `sudo find /tmp/tcloop/"$APPNAME" -type l | sed "s:/tmp/tcloop/$APPNAME/::"`; do
			[ -e "/$F" ] || echo "$F" >> /tmp/"$APPNAME".lnklst
		done
		if [ -s /tmp/"$APPNAME".lnklst ]; then
			sudo /bb/tar -T /tmp/"$APPNAME".lnklst -cpf - | sudo tar xf - -C /
		fi
		## Symlink all other files to the filesystem not overwriting above links.
		yes "$FORCE" | sudo cp -ais /tmp/tcloop/"$APPNAME"/opt / 2>/dev/null
		yes "$FORCE" | sudo cp -ais /tmp/tcloop/"$APPNAME"/usr / 2>/dev/null
		yes "$FORCE" | sudo cp -ais /tmp/tcloop/"$APPNAME"/bin / 2>/dev/null
		yes "$FORCE" | sudo cp -ais /tmp/tcloop/"$APPNAME"/sbin / 2>/dev/null
		yes "$FORCE" | sudo cp -ais /tmp/tcloop/"$APPNAME"/lib / 2>/dev/null
		yes "$FORCE" | sudo cp -ais /tmp/tcloop/"$APPNAME"/dev / 2>/dev/null
		yes "$FORCE" | sudo cp -ai /tmp/tcloop/"$APPNAME"/etc / 2>/dev/null
		yes "$FORCE" | sudo cp -ai /tmp/tcloop/"$APPNAME"/var / 2>/dev/null
		## Determine if kernel modules exist in SCE
		[ ! -z "`sudo find /tmp/tcloop/"$APPNAME" -type f -name *.ko*`" ] && MODULES=TRUE
		## Determine if gdk-pixbuf-loaders have new types and update if needed
		LOADERS_DIR=/tmp/tcloop/"$APPNAME"/usr/lib/i386-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders
		LOADERS_DIR_OLD=/tmp/tcloop/"$APPNAME"/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders
		if sudo find "$LOADERS_DIR" "$LOADERS_DIR_OLD" -name *.so > /dev/null 2>&1; then
			sudo /usr/local/postinst/libgdk-pixbuf2.0-0 trigger > /dev/null 2>&1
		fi
		## Determine if gtk-2.0 immodules are in SCE and update if needed.
		IMMODULES_DIR=/usr/lib/i386-linux-gnu/gtk-2.0/2.10.0/immodules
		IMMODULES_DIR_OLD=/usr/lib/gtk-2.0/2.10.0/immodules
		if sudo find "$IMMODULES_DIR" "$IMMODULES_DIR_OLD" -name *.so > /dev/null 2>&1; then
			sudo /usr/local/postinst/libgtk2.0-0 trigger > /dev/null 2>&1
		fi
		## Determine if gtk-3.0 immodules are in SCE and update if needed.
		IMMODULES_DIR=/usr/lib/i386-linux-gnu/gtk-3.0/3.0.0/immodules
		IMMODULES_DIR_OLD=/usr/lib/gtk-3.0/3.0.0/immodules
		if sudo find "$IMMODULES_DIR" "$IMMODULES_DIR_OLD" -name *.so > /dev/null 2>&1; then
			sudo /usr/local/postinst/libgtk-3-0 trigger > /dev/null 2>&1
		fi

		update_system "$THISAPP" "$APPNAME"
		if [ ! "$BOOTING" ]; then
			[ -s /etc/sysconfig/desktop ] && desktop.sh "$APPNAME" > /dev/null 2>&1
		fi
		[ -f /tmp/"$APPNAME".lnklst ] && sudo rm /tmp/"$APPNAME".lnklst
		cd "$HERE"
	else
		umount -d /tmp/tcloop/"$APPNAME"
		update_system "$THISAPP" "$APPNAME"
	fi
	#grep "^$APPNAME:" /tmp/.installed > /dev/null 2>&1 || echo "$APPNAME:" >> /tmp/.installed
	if [ -f /tmp/tcloop/"$APPNAME"/usr/local/sce/"$APPNAME"/"$APPNAME".md5sum ]; then
		for I in `cat /tmp/tcloop/"$APPNAME"/usr/local/sce/"$APPNAME"/"$APPNAME".md5sum | cut -f1 -d:`; do
			grep "^$I:" /tmp/.debinstalled > /dev/null 2>&1 || echo "$I:" >> /tmp/.debinstalled
		done
	fi
	[ "$BOOTING" ] && [ "$SHOWAPPS" ] && echo -n "${YELLOW}$APPNAME ${NORMAL}"
}

# Main
TCEDIR=/etc/sysconfig/tcedir
[ -d "$TCEDIR" ] || exit 1
if [ -z "$1" ] && [ -z "$BOOTING" ]; then
	choose
fi
[ -f /etc/sysconfig/showapps ] && SHOWAPPS=TRUE && SUPPRESS=TRUE
TCEINSTALLED=/usr/local/tce.installed

getDeps() {
DEPLIST=" $1 $DEPLIST "

if [ -f "$TARGETDIR"/"$1".sce.dep ]; then
	for E in `cat "$TARGETDIR"/"$1".sce.dep`; do 
		H=" $E "
		if echo "$DEPLIST" | grep "$H" > /dev/null 2>&1; then
			continue
		else 
			getDeps "$E"
		fi
	done
fi
}



for TARGETAPP in `echo "$TARGETAPP" "$@"`; do
	TARGETAPP="${TARGETAPP/-KERNEL/-${KERNELVER}}"
	THISSCENAME=${TARGETAPP%%.sce}
	if [ ${TARGETAPP} == ${THISSCENAME} ]; then
		THISSCE=${TARGETAPP}.sce
	else
		THISSCE=${TARGETAPP}
	fi
	if [ -f "$THISSCE" ]; then
		TARGETDIR=`dirname "$THISSCE"`
	else
		TARGETDIR="$TCEDIR"/sce/
	fi

	if [ "$TARGETDIR" == "." ]; then
		TARGETDIR="`pwd`/"
	fi

	if [ ! -f "$TARGETDIR""$THISSCE" ]; then
		echo "${YELLOW}"$TARGETDIR""$THISSCE"${NORMAL} does not exist, not loading.."
		exit 1
	fi

	if ! cat /proc/cmdline | grep " nomd5 " > /dev/null 2>&1; then
		if [ -f "$TARGETDIR"/"$THISSCE".md5.txt ]; then
			cd "$TARGETDIR"
			md5sum -c "$THISSCE".md5.txt > /dev/null 2>&1
			if [ "$?" != 0 ]; then
				echo "Md5sum error on "$TARGETDIR""$THISSCE", not loading.."
				continue
			fi
			cd "$HERE"
		else
			echo "Missing md5sum file "$TARGETDIR""$THISSCE".md5.txt, not loading.."
			continue
		fi
	fi

	if [ -f "$TARGETDIR"/"$THISSCE".dep ]; then
		DEPLIST=" $THISSCENAME "
		for I in `cat "$TARGETDIR"/"$THISSCE".dep`; do 
			getDeps "$I"
		done
	else
		DEPLIST=" $THISSCENAME "
	
	fi

	for I in `echo "$DEPLIST"`; do
		if [ -f "$TARGETDIR"/"$I".sce ]; then
			:
		else
			echo "${YELLOW}"$TARGETDIR""$I".sce${NORMAL} does not exist,"
			echo "not loading the following:"
			## Strip leading and trailing white space.
			LIST=`echo "$DEPLIST" | sed 's/^[ \t]*//;s/[ \t]*$//'`
			echo "${YELLOW}$LIST${NORMAL}"
			exit 1
		fi
		if ! cat /proc/cmdline | grep " nomd5 " > /dev/null 2>&1; then
			if [ -f "$TARGETDIR""$I".sce.md5.txt ]; then
				cd "$TARGETDIR"
				md5sum -c "$I".sce.md5.txt > /dev/null 2>&1
				if [ "$?" != 0 ]; then
					echo "${RED}Md5sum error on "$TARGETDIR""$I".sce, not loading the following:"
					LIST=`echo "$DEPLIST" | sed 's/^[ \t]*//;s/[ \t]*$//'`
					echo "$LIST${NORMAL}"
					exit 0
				fi
				cd "$HERE"
			else
				echo "${RED}Missing md5sum file "$TARGETDIR""$I".sce.md5.txt, not loading the following:"
				LIST=`echo "$DEPLIST" | sed 's/^[ \t]*//;s/[ \t]*$//'`
				echo "$LIST${NORMAL}"
				exit 0
			fi
		fi
	done

	for I in `echo "$DEPLIST"`; do
		TARGETAPP=`echo "$I" | tr -d ' '`
		#APPNAME=${TARGETAPP%%.sce}
		#if [ ${TARGETAPP} == ${APPNAME} ]; then TARGETAPP=${TARGETAPP}.sce; fi
		processAPP
	done # for loop for dependencies
done # Finish the for-loop for multiple extensions 



cd "$SAVED_DIR"

[ "$BOOTING" ] && exit 0
if [ -n "$DISPLAY" ]
then
	[ $(which "$DESKTOP"_restart) ] && "$DESKTOP"_restart > /dev/null 2>&1
	[ $(which wbar) ] && pkill wbar && wbar.sh > /dev/null 2>&1
fi

exit 0
