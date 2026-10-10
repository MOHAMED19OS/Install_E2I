#!/usr/bin/bash

curl --help >/dev/null 2>&1 && DOWNLOADER="curl -L -J -s -o -" || DOWNLOADER="wget --no-check-certificate -q -O -"
command -v python3 >/dev/null 2>&1 && pyInterpreter=python3 || pyInterpreter=python

###########################################
# Configure where we can find things here #
TMPDIR='/tmp/'
PLUGINPATH='/usr/lib/enigma2/python/Plugins/Extensions/'
SETTINGS='/etc/enigma2/settings'
URL='https://github.com/oe-mirrors/e2iplayer/archive/refs/heads'
LOGFILE="${TMPDIR}_e2iplayer_install.log"
archRead=$(uname -m)
NICE=/bin/nice

[ -e ${LOGFILE} ] && rm -fr ${LOGFILE}
exec > >(tee -a "$LOGFILE") 2>&1

# If the script was already running but ended with an Error, delete any remains.
"${NICE}" -n 19 rm -rf "${TMPDIR}e2iplayer-"* "${TMPDIR}python"*.gz "${TMPDIR}master."* "${TMPDIR}opkg-"*

SourcePath=$(find / -type f -name "retObj.conf" 2>/dev/null | head -n 1)
if [ -n "${SourcePath}" ]; then
    # shellcheck source=/dev/null
    source "${SourcePath}"
else
    printf "The process has stopped — (Sorry, E2Iplayer was not installed)\n"
    exit 1
fi

# Loop through candidate mount locations in priority order
for MOUNT_DIR in "/media/hdd" "/media/mmc" "/media/usb"; do
    if [ -d "$MOUNT_DIR" ] && mountpoint -q "$MOUNT_DIR"; then
        MY_PATH="${MOUNT_DIR}/"
        break
    fi
done

MyFile="${MY_PATH}File/"
mkdir -p "${MyFile}"

if [ -d "${MyFile}" ]; then
    TorrServerDir="${MY_PATH}"
else
    TorrServerDir="/usr/bin/"
fi

TorrServerBinDir="${TorrServerDir}TorrServer"

#########################
DownTorrServer(){
    [ -e "${TorrServerBinDir}" ] && "${NICE}" -n 19 rm -rf "${TorrServerBinDir}"
    local TorrSerVersion="${1:-146}"

    case "$archRead" in
        armv7l)
            torrArch="arm7"
            ;;
        mips|mipsel)
            torrArch="mipsle"
            ;;
        aarch64)
            torrArch="arm64"
            ;;
        *)
            printf "Sorry Not Support Architecture: %s\n" "$archRead"
            ;;
    esac
    printf "Please Wait to install TorrServer (%s)\n" "${TorrSerVersion}"

    torrUrl="https://github.com/YouROK/TorrServer/releases/download/MatriX.${TorrSerVersion}/TorrServer-linux-${torrArch}"

    ${DOWNLOADER%-} "${TorrServerBinDir}" "${torrUrl}"
    [ -e "${TorrServerBinDir}" ] && chmod +x "${TorrServerBinDir}" || printf "error downloading TorrServer, end\n"
}

#########################
[ -z "$(find /var/lib/opkg/lists -type f -mmin -60 2>/dev/null)" ] && opkg update >/dev/null 2>&1

pkgInstall() {
    if ! opkg list | grep -q "^$1 "; then
        printf "Package not found in feed (%s)\n" "$1"
    else
        if ! grep -qs "Package: $1" '/var/lib/opkg/status'; then
            printf "====|Please Wait to install (%s)|====" "$1"
            sleep 0.8 && echo
            opkg install "$1"
            sleep 0.8 && echo
        fi
    fi
}
#########################
FileTar="python3.tar.gz"

printf "Downloading E2iPlayer plugin Please Wait ......\n"
${DOWNLOADER%-} "${TMPDIR}${FileTar}" "${URL}/${FileTar}"

if ! [ -e "${TMPDIR}${FileTar}" ]; then
    printf "error downloading archive, end\n"
    printf "ABORT --- ( More Details in %s )" "$LOGFILE"
    exit 1
else
    printf "Archive downloaded\n"
fi
tar -xzf "${TMPDIR}${FileTar}" -C ${TMPDIR}

if ! [ -e "${TMPDIR}e2iplayer-python3" ]; then
    printf "error extracting archive, end\n"
    "${NICE}" -n 19 rm -rf "${TMPDIR}e2iplayer-"* "${TMPDIR}python"*.gz "${TMPDIR}master."* "${TMPDIR}opkg-"*
    printf "ABORT --- ( More Details in %s )" "$LOGFILE"
    exit 1
else
    printf "Archive extracted\n"
    rm -f "${TMPDIR}${FileTar}"
fi

if [ -e "${PLUGINPATH}IPTVPlayer" ]; then
    [ -e "${PLUGINPATH}IPTVPlayer/libs/iptvsubparser/_subparser.so" ] && cp -rf "${PLUGINPATH}IPTVPlayer/libs/iptvsubparser/_subparser.so" ${TMPDIR}

    printf "Removed old version of E2Iplayer\n"
    "${NICE}" -n 19 rm -rf "${PLUGINPATH}IPTVPlayer"
fi

find "${TMPDIR}e2iplayer-python3/IPTVPlayer" -type f -name "*xxx*.*" -exec rm -rf {} + 2>/dev/null
"${NICE}" -n 19 cp -rf "${TMPDIR}e2iplayer-python3/IPTVPlayer" "${PLUGINPATH}"
[ -e "${TMPDIR}_subparser.so" ] && "${NICE}" -n 19 cp -rf "${TMPDIR}_subparser.so" "${PLUGINPATH}IPTVPlayer/libs/iptvsubparser/"

if ! [ -e "${PLUGINPATH}IPTVPlayer" ]; then
    printf "error installing E2Iplayer, end\n"
    printf "ABORT --- ( More Details in %s )" "$LOGFILE"
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

    if [[ "${WebVersion}" == "${TorrVersion}" ]];then
        printf "TorrServer are Found :)\n" && sleep 0.8
    else
        DownTorrServer "$WebVersion"
    fi
else
    DownTorrServer "$WebVersion"
fi

sleep 0.8
if [ -e "${PLUGINPATH}IPTVPlayer" ]; then
    printf ":Your Device IS %s processor ..." "$archRead"
    echo "Add Setting To ${SETTINGS} ..."
    init 4 && sleep 2
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
        echo "config.plugins.iptvplayer.CacheDir=${MY_PATH}IPTVCache/"
        echo "config.plugins.iptvplayer.ConfigDir=${MY_PATH}IPTVPlayer/"
        echo "config.plugins.iptvplayer.configMenuView=categories"
        echo "config.plugins.iptvplayer.debug_max_size=2"
        echo "config.plugins.iptvplayer.debugprint=/tmp/iptv.dbg"
        echo "config.plugins.iptvplayer.showinSystemMenu=False"
        echo "config.plugins.iptvplayer.skinforceallinternal=True"
        echo "config.plugins.iptvplayer.storageExpertMode=True"
        echo "config.plugins.iptvplayer.cookiesCacheDeleteAfterDays=2"
        echo "config.plugins.iptvplayer.jsCacheDeleteAfterDays=2"
        echo "config.plugins.iptvplayer.movieMetaDataCacheDeleteAfterDays=2"
        echo "config.plugins.iptvplayer.mye2i_browser=edge_canary"
        echo "config.plugins.iptvplayer.extplayer_infobanner_clockformat=24"
        echo "config.plugins.iptvplayer.extplayer_skin=black-white"
        echo "config.plugins.iptvplayer.extplayer_subtitle_background=transparent"
        echo "config.plugins.iptvplayer.extplayer_subtitle_border_width=1"
        echo "config.plugins.iptvplayer.extplayer_subtitle_font_size=45"
        echo "config.plugins.iptvplayer.extplayer_subtitle_line_height=65"
        curl --help >/dev/null 2>&1 && echo "config.plugins.iptvplayer.http_downloader=curl"
        [ -n "${IconsSize:-}" ] && echo "config.plugins.iptvplayer.IconsSize=${IconsSize}"
        echo "config.plugins.iptvplayer.IPTVWebIterface=True"
        echo "config.plugins.iptvplayer.moviePlayerPickerMode=extended"
        echo "config.plugins.iptvplayer.DownloadsDir=${MY_PATH}MoviePlayer/"
        # echo "config.plugins.iptvplayer.osk_type=own"
        echo "config.plugins.iptvplayer.remember_last_position=true"
        [ -d "${MyFile}" ] && echo "config.plugins.iptvplayer.Sciezkaurllist=${MyFile}"
        echo "config.plugins.iptvplayer.torrserver_path=${TorrServerBinDir}"
        $pyInterpreter -c "import pycurl" &> /dev/null && echo "config.plugins.iptvplayer.usepycurl=True"
        [ -n "${YouTube_Oauth:-}" ] && echo "config.plugins.iptvplayer.youtube_oauth_refresh_token=${YouTube_Oauth}"
        echo "config.plugins.iptvplayer.ytDefaultformat=9999"
        echo "config.plugins.iptvplayer.ytUseDF=False"
        echo "config.plugins.iptvplayer.ytVP9=True"
    } >>${SETTINGS}
fi

init 3 && sleep 2

# Delete the remains.
printf "\nDelete remains (*.tar.gz/*.zip and Directory e2iplayer-*) ...\n"
"${NICE}" -n 19 rm -rf "${TMPDIR}e2iplayer-"* "${TMPDIR}python"*.gz "${TMPDIR}master."* "${TMPDIR}opkg-"* "${TMPDIR}_subparser.so"

sync
${DOWNLOADER} "http://localhost/web/powerstate?newstate=3" > /dev/null 2>&1
