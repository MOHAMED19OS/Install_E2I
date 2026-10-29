#!/usr/bin/bash

curl --help >/dev/null 2>&1 && DOWNLOADER="curl -L -J -s -o -" || DOWNLOADER="wget --no-check-certificate -q -O -"
command -v python3 >/dev/null 2>&1 && pyInterpreter=python3 || pyInterpreter=python

###########################################
# Configure where we can find things here #
TMP='/var/volatile/tmp'
WORKDIR=/home/root/_workdir # Can be changed as desired, e.g. on HDD to /media/hdd/_workdir or just /media/hdd/dirname_as_desired.
PLUGINPATH='/usr/lib/enigma2/python/Plugins/Extensions'
SETTINGS='/etc/enigma2/settings'
URL='https://github.com/oe-mirrors/e2iplayer/archive/refs/heads'
archRead=$(uname -m)
NICE=/bin/nice
NICE_ARGS="-n 19"

# $TMP (/var/volatile/tmp) is a RAM Disk. On Boxes with little RAM (e.g. DM800SE) the Source Package
# does not fit there ("No space left on device"), then use a tmp Directory in the Working Directory.
TMP_NEEDED_KB=100000
TMP_FREE_KB="$(df -Pk ${TMP} 2> /dev/null | tail -n 1 | awk '{print $4}')"
if [ -z "$TMP_FREE_KB" ] || [ "$TMP_FREE_KB" -lt "$TMP_NEEDED_KB" ] ; then
	TMP=$WORKDIR/tmp
	mkdir -p "${TMP}"
fi

# If the script was already running but ended with an Error, delete any remains.
"${NICE}" "$NICE_ARGS" rm -rf "${TMP}/e2iplayer-"* "${TMP}/python"*.gz "${TMP}/master."* "${TMP}/opkg-"*

# Search for retObj.conf in specific directories instead of whole root "/"
SourcePath=$(find /tmp /etc /media -type f -name "retObj.conf" 2>/dev/null | head -n 1)
if [ -n "${SourcePath}" ]; then
    # shellcheck source=/dev/null
    source "${SourcePath}"
fi

# Loop through candidate mount locations in priority order
for MOUNT_DIR in "/media/hdd" "/media/mmc" "/media/usb" "/media/mmcblk1"; do
    if mountpoint -q "$MOUNT_DIR"; then
        MY_PATH="${MOUNT_DIR}/"
        break
    fi
done

# Fallback path if no mount point was found
: "${MY_PATH:=/etc/enigma2/}"

MyFile="${MY_PATH}File/"

# Exception for creating a File folder if the path is /etc/enigma2/
if [ "${MY_PATH}" != "/etc/enigma2/" ]; then
    mkdir -p "${MyFile}"
fi

TorrServerDir="${MyFile}"
[ -d "${TorrServerDir}" ] || TorrServerDir="/usr/bin/"

TorrServerBinDir="${TorrServerDir}TorrServer"

#########################
DownTorrServer(){
    [ -e "${TorrServerBinDir}" ] && "${NICE}" "$NICE_ARGS" rm -rf "${TorrServerBinDir}"
    local TorrSerVersion="${1:-146}"

    case "$archRead" in
        armv7l)       torrArch="arm7" ;;
        mips|mipsel)  torrArch="mipsle" ;;
        aarch64)      torrArch="arm64" ;;
        *)
            printf "Sorry, Unsupported Architecture: %s\n" "$archRead"
            return 1
            ;;
    esac

    printf "Please Wait to install TorrServer (%s)\n" "${TorrSerVersion}"

    torrUrl="https://github.com/YouROK/TorrServer/releases/download/MatriX.${TorrSerVersion}/TorrServer-linux-${torrArch}"

    ${DOWNLOADER%-} "${TorrServerBinDir}" "${torrUrl}"
    [ -e "${TorrServerBinDir}" ] && chmod +x "${TorrServerBinDir}" || printf "Error downloading TorrServer!\n"
}

#########################
[ -z "$(find /var/lib/opkg/lists -type f -mmin -60 2>/dev/null)" ] && opkg update >/dev/null 2>&1

pkgInstall() {
    if ! opkg list | grep -q "^$1 "; then
        printf "Package not found in feed (%s)\n" "$1"
    else
        if ! grep -qs "Package: $1" '/var/lib/opkg/status'; then
            printf "====|Please Wait to install (%s)|====\n" "$1"
            opkg install "$1"
            sleep 0.8
        fi
    fi
}

#########################
FileTar="python3.tar.gz"

IPTVSUBPARSER="$PLUGINPATH/IPTVPlayer/libs/iptvsubparser"
SUBPARSER_BACKUP="$TMP/_subparser.so"
rm -f "$SUBPARSER_BACKUP"

printf "Downloading E2iPlayer plugin Please Wait ......\n"
${DOWNLOADER%-} "${TMP}/${FileTar}" "${URL}/${FileTar}"

if ! [ -e "${TMP}/${FileTar}" ]; then
    printf "error downloading archive, end\n"
    exit 1
else
    printf "Archive downloaded\n"
fi

# Only the IPTVPlayer Directory is needed, the rest of the Repository (Backup, tests, ...) is not unpacked.
tar -xzf "${TMP}/${FileTar}" -C ${TMP} e2iplayer-python3/IPTVPlayer > /dev/null

# Path to the unpacked E2iPlayer Source Package.
EXTRACTED_SOURCE_PATH="${TMP}/e2iplayer-python3/IPTVPlayer"

# Check it before the installed E2iPlayer gets deleted, otherwise the Box ends up without E2iPlayer.
if [ ! -f $EXTRACTED_SOURCE_PATH/plugin.py ] ; then
    echo -e "\n... ERROR ...\n$EXTRACTED_SOURCE_PATH is missing or incomplete ! \nThe installed E2iPlayer was not touched.\nrestart e2iplayer_install.sh.\n\n" >&2
    "${NICE}" "$NICE_ARGS" rm -rf "${TMP}/e2iplayer-"* "${TMP}/python"*.gz "${TMP}/master."* "${TMP}/opkg-"*
    exit 1
else
    printf "Archive extracted\n"
    "${NICE}" "$NICE_ARGS" rm -f "${TMP}/${FileTar}"
fi

if [ -e "$PLUGINPATH/IPTVPlayer" ]; then
	# keep the native subtitles parser (_subparser.so), it is not part of the source archive
	if [ -e "$IPTVSUBPARSER/_subparser.so" ] ; then
		$NICE "$NICE_ARGS" cp -f "$IPTVSUBPARSER/_subparser.so" "$SUBPARSER_BACKUP"
	fi

    printf "Removed old version of E2Iplayer\n"
    "${NICE}" "$NICE_ARGS" rm -rf "$PLUGINPATH/IPTVPlayer"
fi

find "${TMP}/e2iplayer-python3/IPTVPlayer" -type f -name "*xxx*.*" -exec rm -rf {} + 2>/dev/null
"${NICE}" "$NICE_ARGS" cp -rf "${TMP}/e2iplayer-python3/IPTVPlayer" "$PLUGINPATH/"

# restore the native subtitles parser saved above, unless the new E2iPlayer brings its own
if [ -e "$SUBPARSER_BACKUP" ] && [ ! -e "$IPTVSUBPARSER/_subparser.so" ] ; then
	$NICE "$NICE_ARGS" cp -f "$SUBPARSER_BACKUP" "$IPTVSUBPARSER/_subparser.so"
fi

if ! [ -e "$PLUGINPATH/IPTVPlayer" ]; then
    printf "error installing E2Iplayer, end\n"
    exit 1
else
    printf "E2Iplayer installed\n"
fi

sleep 3
arrVar=("enigma2-plugin-extensions-e2iplayer-deps" "exteplayer3" "gstplayer" "hlsdl" "duktape" "$pyInterpreter-pycurl" "$pyInterpreter-json" "curl-impersonate" "$pyInterpreter-pycryptodome")
for i in "${arrVar[@]}"; do
    pkgInstall "$i"
done

TorrOutput=$(${DOWNLOADER} "https://github.com/YouROK/TorrServer/tags" | grep -oE 'MatriX\.[0-9.]+' | head -1)
[ -z "$TorrOutput" ] && TorrOutput=$(${DOWNLOADER} "https://api.github.com/repos/YouROK/TorrServer/releases/latest" | grep -oE '"tag_name": *"[^"]+"')

WebVersion=$(echo "$TorrOutput" | grep -oE '[0-9]+(\.[0-9]+)*' | head -1)
if [ -e "${TorrServerBinDir}" ]; then
    ! [ -x "${TorrServerBinDir}" ] && chmod +x "${TorrServerBinDir}"
    TorrVersion=$("${TorrServerBinDir}" --help 2>&1 | grep -oE 'TorrServer\s+MatriX\.[0-9.]+' | grep -oE '[0-9]+(\.[0-9]+)*')

    if [[ "${WebVersion}" == "${TorrVersion}" ]]; then
        printf "TorrServer is Found :)\n" && sleep 0.8
    else
        DownTorrServer "$WebVersion"
    fi
else
    DownTorrServer "$WebVersion"
fi

# link duktape, only if duk (duktape binary) exists in /usr/bin and not in the .../IPTVPlayer/bin directory, link it there.
if [ -e /usr/bin/duk ] && [ ! -e "$PLUGINPATH/IPTVPlayer/bin/duk" ] ; then
	ln -s /usr/bin/duk "$PLUGINPATH/IPTVPlayer/bin"
fi

sleep 0.8
if [ -e "$PLUGINPATH/IPTVPlayer" ]; then
    printf ":Your Device IS %s processor ...\n" "$archRead"
    echo "Add Setting To ${SETTINGS} ..."
    { init 4; sleep 3; }
    sed -i '/config\.plugins\.iptvplayer\./d' "${SETTINGS}"
    sleep 1
    {
        echo "config.plugins.iptvplayer.defaultMoviePlayer=exteplayer"
        echo "config.plugins.iptvplayer.alternativeMoviePlayer=extgstplayer"
        echo "config.plugins.iptvplayer.defaultMoviePlayer0=exteplayer"
        echo "config.plugins.iptvplayer.alternativeMoviePlayer0=extgstplayer"
        [ -n "${Tmdb_API_KEY:-}" ] && echo "config.plugins.iptvplayer.meta_tmdb_apikey=${Tmdb_API_KEY}"
        [ -n "${OMDB_API_KEY:-}" ] && echo "config.plugins.iptvplayer.meta_omdb=True"
        [ -n "${OMDB_API_KEY:-}" ] && echo "config.plugins.iptvplayer.meta_omdb_apikey=${OMDB_API_KEY}"
        [ -n "${OpenSubtitles_org_LOGIN:-}" ] && echo "config.plugins.iptvplayer.opensuborg_login=${OpenSubtitles_org_LOGIN}"
        [ -n "${OpenSubtitles_org_PASSWORD:-}" ] && echo "config.plugins.iptvplayer.opensuborg_password=${OpenSubtitles_org_PASSWORD}"
        [ -n "${OpenSubtitles_com_API_KEY:-}" ] && echo "config.plugins.iptvplayer.opensubcom_apikey=${OpenSubtitles_com_API_KEY}"
        [ -n "${OpenSubtitles_com_LOGIN:-}" ] && echo "config.plugins.iptvplayer.opensubcom_login=${OpenSubtitles_com_LOGIN}"
        [ -n "${OpenSubtitles_com_PASSWORD:-}" ] && echo "config.plugins.iptvplayer.opensubcom_password=${OpenSubtitles_com_PASSWORD}"
        [ -n "${SubDL_API_KEY:-}" ] && echo "config.plugins.iptvplayer.subdlapi=${SubDL_API_KEY}"
        [ -n "${SubSource_API_KEY:-}" ] && echo "config.plugins.iptvplayer.subsourceapi=${SubSource_API_KEY}"
        [ -n "${ArabP2P_LOGIN:-}" ] && echo "config.plugins.iptvplayer.arabp2p_login=${ArabP2P_LOGIN}"
        [ -n "${ArabP2P_PASSWORD:-}" ] && echo "config.plugins.iptvplayer.arabp2p_password=${ArabP2P_PASSWORD}"
        [ -n "${Febbox_Token:-}" ] && echo "config.plugins.iptvplayer.showbox_febbox_token=${Febbox_Token}"
        echo "config.plugins.iptvplayer.CacheDir=${MY_PATH}IPTVCache/"
        echo "config.plugins.iptvplayer.ConfigDir=${MY_PATH}IPTVPlayer/"
        echo "config.plugins.iptvplayer.configMenuView=categories"
        echo "config.plugins.iptvplayer.debug_max_size=2"
        echo "config.plugins.iptvplayer.debugprint=/tmp/iptv.dbg"
        echo "config.plugins.iptvplayer.showinSystemMenu=False"
        echo "config.plugins.iptvplayer.skinforceallinternal=True"
        echo "config.plugins.iptvplayer.storageExpertMode=True"
        if [ -n "${TorrServer_Enabled:-}" ]; then
            if [ "${MY_PATH}" != "/etc/enigma2/" ]; then
                echo "config.plugins.iptvplayer.torrserver_cache_dir=${MY_PATH}IPTVCache/"
                echo "config.plugins.iptvplayer.torrserver_cache_location=disk"
            fi
            echo "config.plugins.iptvplayer.torrserver_enabled=True"
            echo "config.plugins.iptvplayer.torrserver_path=${TorrServerBinDir}"
            echo "config.plugins.iptvplayer.torrserver_remove_cache=False"
            echo "config.plugins.iptvplayer.torrserver_ul_limit=0"
            echo "config.plugins.iptvplayer.torrserver_upload=True"
        fi
        echo "config.plugins.iptvplayer.cookiesCacheDeleteAfterDays=2"
        echo "config.plugins.iptvplayer.jsCacheDeleteAfterDays=2"
        echo "config.plugins.iptvplayer.movieMetaDataCacheDeleteAfterDays=2"
        echo "config.plugins.iptvplayer.extplayer_infobanner_clockformat=24"
        echo "config.plugins.iptvplayer.extplayer_skin=black-white"
        echo "config.plugins.iptvplayer.extplayer_subtitle_background=transparent"
        echo "config.plugins.iptvplayer.extplayer_subtitle_border_width=1"
        echo "config.plugins.iptvplayer.extplayer_subtitle_font_size=45"
        echo "config.plugins.iptvplayer.extplayer_subtitle_line_height=65"
        echo "config.plugins.iptvplayer.host_list_titles=short"
        curl --help >/dev/null 2>&1 && echo "config.plugins.iptvplayer.http_downloader=curl"
        [ -n "${IconsSize:-}" ] && echo "config.plugins.iptvplayer.IconsSize=${IconsSize}"
        echo "config.plugins.iptvplayer.IPTVWebIterface=True"
        echo "config.plugins.iptvplayer.moviePlayerPickerMode=extended"
        echo "config.plugins.iptvplayer.mye2i_browser=edge_canary"
        echo "config.plugins.iptvplayer.mye2i_close_start_page=True"
        echo "config.plugins.iptvplayer.DownloadsDir=${MY_PATH}MoviePlayer/"
        [ -n "${AdultPIN:-}" ] && echo "config.plugins.iptvplayer.pin=${AdultPIN}"
        echo "config.plugins.iptvplayer.preferred_quality=max"
        echo "config.plugins.iptvplayer.remember_last_position=true"
        [ -d "${MyFile}" ] && echo "config.plugins.iptvplayer.Sciezkaurllist=${MyFile}"
        $pyInterpreter -c "import pycurl" &> /dev/null && echo "config.plugins.iptvplayer.usepycurl=True"
        [ -n "${YouTube_Oauth:-}" ] && echo "config.plugins.iptvplayer.youtube_oauth_refresh_token=${YouTube_Oauth}"
        echo "config.plugins.iptvplayer.ytDefaultformat=9999"
        echo "config.plugins.iptvplayer.ytUseDF=False"
        echo "config.plugins.iptvplayer.ytVP9=True"
    } >> "${SETTINGS}"
fi

{ init 3; sleep 3; }

# Delete the remains.
printf "\nDelete remains (*.tar.gz/*.zip and Directory e2iplayer-*) ...\n"
"${NICE}" "$NICE_ARGS" rm -rf "${TMP}/e2iplayer-"* "${TMP}/python"*.gz "${TMP}/master."* "${TMP}/opkg-"* "$SUBPARSER_BACKUP"
[ -e "${WORKDIR}/tmp" ] && rmdir "${WORKDIR}/tmp" 2> /dev/null

sync
${DOWNLOADER} "http://127.0.0.1/web/powerstate?newstate=3" > /dev/null 2>&1 || { init 4 ; sleep 3 ; init 3 ; }
