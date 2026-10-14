#!/bin/sh

# AUTHOR sigmaboy <j.sigmaboy@gmail.com>

# return codes:
# 1 user errors
# 2 no DLC available
# 4 not all keys or links available
# 5 all available DLC archives already exist

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

find_existing_dlc() {
    local DLC_ID="${1}"
    local FOUND_FILE

    for FOUND_FILE in "${DLC_OUTPUT_DIR}"/*."${ext}"
    do
        test -f "${FOUND_FILE}" || continue
        case "${FOUND_FILE##*/}" in
            *"[${GAME_ID}] "*"[DLC-${DLC_ID}].${ext}")
                if [ "$(file -b --mime-type "${FOUND_FILE}")" = "${mime_type}" ]
                then
                    echo "File \"${FOUND_FILE}\" already exists. Skipping this DLC." >&2
                    return 0
                fi
                echo "File \"${FOUND_FILE}\" is not a valid ${ext} archive. Aborting." >&2
                return 2
                ;;
        esac
    done
    return 1
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

LIST=$(grep "^${GAME_ID}" "${TSV_FILE}" | cut -f"4,5,6,9" | tr '\t' '%' | tr -d '\r')
# '\r' bytes interfere with string comparison later on, so we remove them

DLC_OUTPUT_DIR="${MY_PATH}/${DESTDIR}_dlc"
MISSING_COUNT=0
EXISTING_COUNT=0
DOWNLOADED_COUNT=0

for i in ${LIST}
do
    LINK=$(echo "${i}" | cut -d"%" -f1)
    KEY=$(echo "${i}" | cut -d"%" -f2)
    CONTENT_ID=$(echo "${i}" | cut -d"%" -f3)
    LIST_SHA256=$(echo "${i}" | xargs | cut -d"%" -f4)

    # pkg2zip names DLC archives using the final component of Content ID.
    # Quote the identifiers in the matcher so brackets are treated literally.
    case "${CONTENT_ID}" in
        ??????-"${GAME_ID}"_??-?*)
            DLC_ID="${CONTENT_ID##*-}"
            find_existing_dlc "${DLC_ID}"
            EXISTING_STATUS=${?}
            case "${EXISTING_STATUS}" in
                0)
                    EXISTING_COUNT=$((EXISTING_COUNT + 1))
                    continue
                    ;;
                2) exit 1 ;;
            esac
            ;;
    esac

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
        if [ ! -d "${DLC_OUTPUT_DIR}" ]
        then
            mkdir "${DLC_OUTPUT_DIR}" || exit 1
        fi
        DOWNLOAD_WORK="$(nps_temp_dir "${NPS_DOWNLOAD_DIR}" "${GAME_ID}-dlc-download")" || exit 1
        EXTRACT_WORK="$(nps_temp_dir "${NPS_EXTRACT_DIR}" "${GAME_ID}-dlc-extract")" || exit 1
        PKG_FILE="${DOWNLOAD_WORK}/${GAME_ID}_dlc.pkg"
        my_download_file "${LINK}" "${PKG_FILE}" || exit 1
        FILE_SHA256="$(my_sha256 "${PKG_FILE}")"
        compare_checksum "${LIST_SHA256}" "${FILE_SHA256}" "${PKG_FILE}"

        # get file name and modify it
        pkg2zip -l "${PKG_FILE}" | sed 's/\.zip//g' > "${EXTRACT_WORK}/${GAME_ID}_dlc.txt"
        MY_FILE_NAME="$(cat "${EXTRACT_WORK}/${GAME_ID}_dlc.txt")"
        MY_FILE_NAME="$(region_rename "${MY_FILE_NAME}")"

        # Without Content ID metadata, check the exact name after listing.
        if [ -e "${DLC_OUTPUT_DIR}/${MY_FILE_NAME}.${ext}" ]
        then
            if [ "$(file -b --mime-type "${DLC_OUTPUT_DIR}/${MY_FILE_NAME}.${ext}")" != "${mime_type}" ]
            then
                echo "Existing archive is invalid: ${MY_FILE_NAME}.${ext}" >&2
                exit 1
            fi
            echo "File \"${MY_FILE_NAME}.${ext}\" already exists. Skipping this DLC." >&2
            EXISTING_COUNT=$((EXISTING_COUNT + 1))
            nps_cleanup_dir "${EXTRACT_WORK}" "${NPS_EXTRACT_DIR}"
            nps_cleanup_dir "${DOWNLOAD_WORK}" "${NPS_DOWNLOAD_DIR}"
            continue
        fi

        # extract files and compress them with t7z
        cd "${EXTRACT_WORK}" || exit 1
        pkg2zip -x "${PKG_FILE}" "${KEY}" || exit 1
        # add the -rs parameter until a bug on the t7z port for FreeBSD is fixed
        t7z -ba -rs a "${DLC_OUTPUT_DIR}/${MY_FILE_NAME}.${ext}" "addcont/" || exit 1
        DOWNLOADED_COUNT=$((DOWNLOADED_COUNT + 1))
        cd "${MY_PATH}" || exit 1
        nps_cleanup_dir "${EXTRACT_WORK}" "${NPS_EXTRACT_DIR}"
        nps_cleanup_dir "${DOWNLOAD_WORK}" "${NPS_DOWNLOAD_DIR}"
    fi
done
echo "${EXISTING_COUNT} DLC(s) already present; ${DOWNLOADED_COUNT} downloaded." >&2
if [ ${MISSING_COUNT} -gt 0 ]
then
    exit 4
elif [ ${DOWNLOADED_COUNT} -eq 0 ] && [ ${EXISTING_COUNT} -gt 0 ]
then
    exit 5
else
    exit 0
fi
