#!/bin/sh

# AUTHOR sigmaboy <j.sigmaboy@gmail.com>

# return codes:
# 1 user errors
# 3 game is only available physically
# 4 link or key missing.
# 5 game archive already exists

# get directory where the scripts are located
SCRIPT_DIR="$(dirname "$(readlink -f "$(which "${0}")")")"

# source shared functions
. "${SCRIPT_DIR}/functions.sh"
nps_load_config

my_usage() {
    echo ""
    echo "Usage:"
    echo "${0} \"/path/to/PSM.tsv\" \"PCSE00986\""
}

MY_BINARIES="pkg2zip sed grep file t7z"
sha256_choose; downloader_choose

check_binaries "${MY_BINARIES}"

# Get variables from script parameters
TSV_FILE="${1}"
TITLE_ID="${2}"


if [ ! -f "${TSV_FILE}" ]
then
    echo "No TSV file found."
    my_usage
    exit 1
fi
if [ -z "${TITLE_ID}" ]
then
    echo "No game ID found."
    my_usage
    exit 1
fi

check_valid_psm_id "${TITLE_ID}"

# check if MEDIA ID is found in download list
if ! grep "^${TITLE_ID}" "${TSV_FILE}" > /dev/null
then
    echo "ERROR:"
    echo "Title ID is not found in your *.tsv file"
    echo "Check your input for a valid media ID"
    echo "Search on: \"https://renascene.com/psv/\" for"
    echo "Media IDs or simple open the *.tsv with your Office Suite."
    exit 1
fi

# get link, encryption key and sha256sum
LIST=$(grep "^${TITLE_ID}" "${TSV_FILE}" | tr -d '\r' | cut -f"4,5,9")

# save those in separete variables
LINK=$(echo "${LIST}" | cut -f1)
KEY=$(echo "${LIST}" | cut -f2)
LIST_SHA256=$(echo "${LIST}" | cut -f3)

if [ "${LINK}" = "MISSING" ] && [ "${KEY}" = "MISSING" ]
then
    echo "Download link and zRIF key of \"${TITLE_ID}\" are missing."
    echo "Cannot proceed."
    exit 4
elif [ "${LINK}" = "MISSING" ]
then
    echo "Download link of \"${TITLE_ID}\" is missing."
    echo "Cannot proceed."
    exit 4
elif [ "${KEY}" = "MISSING" ]
then
    echo "zrif key of \"${TITLE_ID}\" is missing."
    echo "Cannot proceed."
    exit 4
elif [ "${LINK}" = "CART ONLY" ]
then
    echo "\"${GANE_ID}\" is only available via cartridge"
    exit 3
else
    if find "${NPS_OUTPUT_DIR}" -maxdepth 1 -type f -name "*[${TITLE_ID}]*.${ext}" | grep -q -E "\[${TITLE_ID}\].*\.${ext}"
    then
        FOUND_FILE=$(find "${NPS_OUTPUT_DIR}" -maxdepth 1 -type f -name "*[${TITLE_ID}]*.${ext}" | grep -E "\[${TITLE_ID}\].*\.${ext}" | head -n 1)
        # write package name into txt file for depending steps like downloading dlc and update
        basename "${FOUND_FILE}" ".${ext}" > "${NPS_OUTPUT_DIR}/${TITLE_ID}.txt"

        # test if archive is a ${ext} file
        if [ "$(file -b --mime-type "${FOUND_FILE}")" = "${mime_type}" ]
        then
            # print this to stderr
            >&2 echo "File \"${FOUND_FILE}\" already exists."
            exit 5
        else
            # print this to stderr
            >&2 echo "File \"${FOUND_FILE}\" already exists."
            >&2 echo "But it doesn't seem to be a valid ${ext} file"
            exit 5
        fi
    else
        DOWNLOAD_WORK="$(nps_temp_dir "${NPS_DOWNLOAD_DIR}" "${TITLE_ID}-psm-download")" || exit 1
        EXTRACT_WORK="$(nps_temp_dir "${NPS_EXTRACT_DIR}" "${TITLE_ID}-psm-extract")" || exit 1
        PKG_FILE="${DOWNLOAD_WORK}/${TITLE_ID}.pkg"
        my_download_file "${LINK}" "${PKG_FILE}"
        FILE_SHA256="$(my_sha256 "${PKG_FILE}")"
        compare_checksum "${LIST_SHA256}" "${FILE_SHA256}" "${PKG_FILE}"

        # get file name and modify it
        pkg2zip -l "${PKG_FILE}" | sed 's/.zip//g' > "${NPS_OUTPUT_DIR}/${TITLE_ID}.txt"
        MY_FILE_NAME="$(cat "${NPS_OUTPUT_DIR}/${TITLE_ID}.txt")"
        MY_FILE_NAME="$(region_rename "${MY_FILE_NAME}")"
        cd "${EXTRACT_WORK}" || exit 1
        pkg2zip -x "${PKG_FILE}" "${KEY}"
        # add the -rs parameter until a bug on the t7z port for FreeBSD is fixed
        t7z -ba -rs a "${NPS_OUTPUT_DIR}/${MY_FILE_NAME}.${ext}" "psm/"
        cd "${NPS_OUTPUT_DIR}" || exit 1
        nps_cleanup_dir "${EXTRACT_WORK}" "${NPS_EXTRACT_DIR}"
        nps_cleanup_dir "${DOWNLOAD_WORK}" "${NPS_DOWNLOAD_DIR}"
    fi
fi
exit 0
