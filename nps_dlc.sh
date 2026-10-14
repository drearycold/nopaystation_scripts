#!/bin/sh

# AUTHOR sigmaboy <j.sigmaboy@gmail.com>

# return codes:
# 1 user errors
# 2 no DLC available
# 4 not all keys or links available
# 5 game archive already exists

# get directory where the scripts are located
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"

# source shared functions
. "${SCRIPT_DIR}/functions.sh"
nps_load_config

my_usage(){
    echo ""
    echo "Usage:"
    echo "${0} \"/path/to/DLC.tsv\" \"PCSE00986\""
}

MY_BINARIES="pkg2zip sed grep t7z file"
sha256_choose; downloader_choose

check_binaries "${MY_BINARIES}"

# Get variables from script parameters
TSV_FILE="${1}"
GAME_ID="${2}"

if [ ! -f "${TSV_FILE}" ]
then
    echo "No TSV file found."
    my_usage
    exit 1
fi
if [ -z "${GAME_ID}" ]
then
    echo "No game ID found."
    my_usage
    exit 1
fi

check_valid_psv_id "${GAME_ID}"
MY_PATH="${NPS_OUTPUT_DIR}"

# make DESTDIR overridable
if [ -z "${DESTDIR}" ]
then
    DESTDIR="${GAME_ID}"
fi

if ! grep -q "^${GAME_ID}" "${TSV_FILE}"
then
    exit 2
fi

LIST=$(grep "^${GAME_ID}" "${TSV_FILE}" | cut -f"4,5,9" | tr '\t' '%' | tr -d '\r')
# '\r' bytes interfere with string comparison later on, so we remove them

for i in ${LIST}
do
    LINK=$(echo "${i}" | cut -d"%" -f1)
    KEY=$(echo "${i}" | cut -d"%" -f2)
    LIST_SHA256=$(echo "${i}" | xargs | cut -d"%" -f3)

    MISSING_COUNT=0
    if [ "${LINK}" = "MISSING" ] && [ "${KEY}" = "MISSING" ]
    then
        >&2 echo "Download link and zRIF key are missing."
        MISSING_COUNT=$((${MISSING_COUNT} + 1))
    elif [ "${LINK}" = "MISSING" ]
    then
        >&2 echo "Download link is missing."
        MISSING_COUNT=$((${MISSING_COUNT} + 1))
    elif [ "${KEY}" = "MISSING" ]
    then
        >&2 echo "zRIF key is missing."
        MISSING_COUNT=$((${MISSING_COUNT} + 1))
    else
        if [ ! -d "${MY_PATH}/${DESTDIR}_dlc" ]
        then
            mkdir "${MY_PATH}/${DESTDIR}_dlc"
        fi
        cd "${MY_PATH}/${DESTDIR}_dlc"

        if find . -maxdepth 1 -type f -name "*[${TITLE_ID}]*[DLC*.${ext}" | grep -q -E "\[${TITLE_ID}\].*\[DLC.*\.${ext}"
        then
            EXISTING_COUNT=0
            for FOUND_FILE in "$(find . -maxdepth 1 -type f -name "*[${TITLE_ID}]*[DLC*.${ext}" | grep -E "\[${TITLE_ID}\].*\[DLC.*\.${ext}" | sed 's@\./@@g')"
            do
                if [ "$(file -b --mime-type "${FOUND_FILE}")" = "${mime_type}" ]
                then
                    EXISTING_COUNT=$((${EXISTING_COUNT} + 1))
                    # print this to stderr
                    >&2 echo "File \"${FOUND_FILE}\" already exists."
                else
                    EXISTING_COUNT=$((${EXISTING_COUNT} + 1))
                    # print this to stderr
                    >&2 echo "File \"${FOUND_FILE}\" already exists."
                    >&2 echo "But it doesn't seem to be a valid ${ext} file"
                fi
            done
            >&2 echo ""
            >&2 echo "${EXISTING_COUNT} DLC(s) already present"
            cd "${MY_PATH}"
            exit 5
        else
            DOWNLOAD_WORK="$(nps_temp_dir "${NPS_DOWNLOAD_DIR}" "${GAME_ID}-dlc-download")" || exit 1
            EXTRACT_WORK="$(nps_temp_dir "${NPS_EXTRACT_DIR}" "${GAME_ID}-dlc-extract")" || exit 1
            PKG_FILE="${DOWNLOAD_WORK}/${GAME_ID}_dlc.pkg"
            my_download_file "${LINK}" "${PKG_FILE}"
            FILE_SHA256="$(my_sha256 "${PKG_FILE}")"
            compare_checksum "${LIST_SHA256}" "${FILE_SHA256}" "${PKG_FILE}"

            # get file name and modify it
            pkg2zip -l "${PKG_FILE}" | sed 's/\.zip//g' > "${EXTRACT_WORK}/${GAME_ID}_dlc.txt"
            MY_FILE_NAME="$(cat "${EXTRACT_WORK}/${GAME_ID}_dlc.txt")"
            MY_FILE_NAME="$(region_rename "${MY_FILE_NAME}")"

            # extract files and compress them with t7z
            cd "${EXTRACT_WORK}" || exit 1
            pkg2zip -x "${PKG_FILE}" "${KEY}"
            # add the -rs parameter until a bug on the t7z port for FreeBSD is fixed
            t7z -ba -rs a "${MY_PATH}/${DESTDIR}_dlc/${MY_FILE_NAME}.7z" "addcont/"
            cd "${MY_PATH}"
            nps_cleanup_dir "${EXTRACT_WORK}" "${NPS_EXTRACT_DIR}"
            nps_cleanup_dir "${DOWNLOAD_WORK}" "${NPS_DOWNLOAD_DIR}"
        fi
    fi
done
if [ ${MISSING_COUNT} -gt 0 ]
then
    exit 4
else
    exit 0
fi
