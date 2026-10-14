#!/bin/sh

# AUTHOR sigmaboy <j.sigmaboy@gmail.com>

# return codes:
# 1 user errors
# 2 no updates available
# 5 game archives already exist

# get directory where the scripts are located
SCRIPT_DIR="$(dirname "$(readlink -f "$(which "${0}")")")"

# source shared functions
. "${SCRIPT_DIR}/functions.sh"
nps_load_config

# check for "-a" parameter
if [ "${1}" == "-a" ]
then
    ALL=1
    shift
else
    ALL=0
fi

my_usage(){
    echo ""
    echo "Usage:"
    echo "${0} \"PCSE00986\""
}

MY_BINARIES="pkg2zip sed grep file python3 pyNPU.py t7z"
sha256_choose; downloader_choose

check_binaries "${MY_BINARIES}"

# Get variables from script parameters
TITLE_ID="${1}"

if [ -z "${TITLE_ID}" ]
then
    echo "No game ID found."
    my_usage
    exit 1
fi

check_valid_psv_id "${TITLE_ID}"

# get current working directory
MY_PATH="${NPS_OUTPUT_DIR}"


# test if any update is available
pyNPU.py --link --title-id ${TITLE_ID} > /dev/null
if [ "${?}" -eq 2 ]
then
    >&2 echo "No updates available for title ID \"${TITLE_ID}\"."
    exit 2
fi

GAME_NAME="$(pyNPU.py --name --title-id "${TITLE_ID}")"

# make DESTDIR overridable
if [ -z "${DESTDIR}" ]
then
    RENAME=1
    DESTDIR="${TITLE_ID}"
else
    RENAME=0
fi

# create download dir if updates for this game are available
if [ ! -d "${MY_PATH}/${DESTDIR}_update" ]
then
    mkdir "${MY_PATH}/${DESTDIR}_update"
fi

# get the download links from the pyton script
# check if the script should just output the latest update or all
if [ "${ALL}" -eq 0 ]
then
    LIST="$(pyNPU.py --link --title-id "${TITLE_ID}")"
else
    LIST="$(pyNPU.py --link --all --title-id "${TITLE_ID}")"
fi

# download changelog in *.txt format
pyNPU.py --changelog --title-id "${TITLE_ID}" > "${MY_PATH}/${DESTDIR}_update/changelog.txt"

for i in ${LIST}
do
    cd "${MY_PATH}/${DESTDIR}_update"
    if find . -maxdepth 1 -type f -name "*[${TITLE_ID}]*.${ext}" | grep -q -E "\[${TITLE_ID}\].*\.${ext}"
    then
        COUNT=0
        for FOUND_FILE in "$(find . -maxdepth 1 -type f -name "*[${TITLE_ID}]*[PATCH]*.${ext}" | grep -E "\[${TITLE_ID}\].*\[PATCH\].*\.${ext}" | sed 's@\./@@g')"
        do
            if [ "$(file -b --mime-type "${FOUND_FILE}")" = "${mime_type}" ]
            then
                COUNT=$((${COUNT} + 1))
                # print this to stderr
                >&2 echo "File \"${FOUND_FILE}\" already exists."
            else
                COUNT=$((${COUNT} + 1))
                # print this to stderr
                >&2 echo "File \"${FOUND_FILE}\" already exists."
                >&2 echo "But it doesn't seem to be a valid ${ext} file"
            fi
        done
        >&2 echo ""
        >&2 echo "${COUNT} updates already present"
        cd "${MY_PATH}"
        exit 5
    else
        DOWNLOAD_WORK="$(nps_temp_dir "${NPS_DOWNLOAD_DIR}" "${TITLE_ID}-update-download")" || exit 1
        EXTRACT_WORK="$(nps_temp_dir "${NPS_EXTRACT_DIR}" "${TITLE_ID}-update-extract")" || exit 1
        PKG_FILE="${DOWNLOAD_WORK}/${TITLE_ID}_update.pkg"
        my_download_file "${i}" "${PKG_FILE}"

        pkg2zip -l "${PKG_FILE}" | sed 's/\.zip//g' > "${EXTRACT_WORK}/${TITLE_ID}_update.txt"
        MY_FILE_NAME="$(cat "${EXTRACT_WORK}/${TITLE_ID}_update.txt")"
        MY_FILE_NAME="$(region_rename "${MY_FILE_NAME}")"

        # extract files and compress them with t7z
        cd "${EXTRACT_WORK}" || exit 1
        pkg2zip -x "${PKG_FILE}"
        # add the -rs parameter until a bug on the t7z port for FreeBSD is fixed
        t7z -ba -rs a "${MY_PATH}/${DESTDIR}_update/${MY_FILE_NAME}.${ext}" "patch/"
        cd "${MY_PATH}"
        nps_cleanup_dir "${EXTRACT_WORK}" "${NPS_EXTRACT_DIR}"
        nps_cleanup_dir "${DOWNLOAD_WORK}" "${NPS_DOWNLOAD_DIR}"
    fi
done

if [ ${RENAME} -eq 1 ]
then
    # this code is pretty ugly. It's just to make sure the directory naming scheme behaves like when overriding $DESTDIR with the game name
    REGION_NAME="$(basename "$(find "${MY_PATH}/${DESTDIR}_update" -type f -name "*.${ext}" | head -n 1)" | sed "s/.*\[${TITLE_ID}\] \[//g" | sed 's/\] \[PATCH.*//')"
    mv "${MY_PATH}/${DESTDIR}_update" "${MY_PATH}/${GAME_NAME} [${TITLE_ID}] [${REGION_NAME}]_update"
fi
