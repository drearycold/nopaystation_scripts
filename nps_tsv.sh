#!/bin/sh

# get directory where the scripts are located
SCRIPT_DIR="$(dirname "$(readlink -f "$(which "${0}")")")"

# source shared functions
. "${SCRIPT_DIR}/functions.sh"
nps_load_config

HEADER="https://"
BASE_URL="nopaystation.com"
MY_URL_PATH="tsv"
LIST="PSV_GAMES PSV_DLCS PSM_GAMES PSV_UPDATES PSV_THEMES PSX_GAMES PSP_GAMES"
LIST="${LIST} PSP_DLCS PSP_THEMES PS3_GAMES PS3_DLCS PS3_THEMES PS3_AVATARS"
LIST="${LIST} PS4_GAMES PS4_DLCS PS4_UPDATES PS4_THEMES"
MY_NAME="NoPayStation"

MY_BINARIES=""
downloader_choose

check_binaries "${MY_BINARIES}"

if [ -z "${1}" ]
then
    DEST="${NPS_OUTPUT_DIR}"
else
    DEST="${1}"
fi
mkdir -p "${DEST}" || exit 1
MY_DATE="$(date "+%Y_%m_%d")"
if [ -f "${DEST}/${MY_NAME}_${MY_DATE}.tar.gz" ]
then
    echo "Backup of the current day already exists. Skipping"
    exit 1
fi

DOWNLOAD_WORK="$(nps_temp_dir "${NPS_DOWNLOAD_DIR}" "tsv-${MY_DATE}-download")" || exit 1
mkdir "${DOWNLOAD_WORK}/${MY_DATE}" || exit 1

for i in ${LIST}
do
    my_download_file "${HEADER}${BASE_URL}/${MY_URL_PATH}/${i}.tsv" \
                     "${DOWNLOAD_WORK}/${MY_DATE}/${i}.tsv"
done

tar -C "${DOWNLOAD_WORK}" -czf "${DEST}/${MY_NAME}_${MY_DATE}.tar.gz" "${MY_DATE}"
nps_cleanup_dir "${DOWNLOAD_WORK}" "${NPS_DOWNLOAD_DIR}"
