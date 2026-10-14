#!/bin/sh

# AUTHOR sigmaboy <j.sigmaboy@gmail.com>

# return codes:
# 1 user or tool errors
# 2 no updates available
# 5 all requested update archives already exist

SCRIPT_DIR="$(dirname "$(readlink -f "$(which "${0}")")")"
. "${SCRIPT_DIR}/functions.sh"
nps_load_config

my_usage() {
    echo "Usage: ${0} [-a] <TITLE_ID>"
}

find_existing_patch_in_dir() {
    local SEARCH_DIR="${1}"
    local FOUND_FILE

    for FOUND_FILE in "${SEARCH_DIR}"/*."${ext}"
    do
        test -f "${FOUND_FILE}" || continue
        case "${FOUND_FILE##*/}" in
            *"[${TITLE_ID}] "*"[PATCH] [v${PATCH_VERSION}].${ext}"|\
            *"[${TITLE_ID}] "*"[PATCH] [v${PATCH_VERSION#0}].${ext}")
                if [ "$(file -b --mime-type "${FOUND_FILE}")" = "${mime_type}" ]
                then
                    echo "File \"${FOUND_FILE}\" already exists. Skipping this version." >&2
                    return 0
                fi
                echo "File \"${FOUND_FILE}\" is not a valid ${ext} archive. Aborting." >&2
                return 2
                ;;
        esac
    done
    return 1
}

find_existing_patch() {
    local SEARCH_DIR STATUS

    find_existing_patch_in_dir "${UPDATE_OUTPUT_DIR}"
    STATUS=${?}
    test "${STATUS}" -eq 1 || return "${STATUS}"
    if [ "${DEFAULT_OUTPUT}" -eq 1 ]
    then
        # Include legacy title-ID folders and folders renamed by older runs.
        for SEARCH_DIR in "${MY_PATH}/${TITLE_ID}_update" \
            "${MY_PATH}"/*" [${TITLE_ID}] ["*"]_update"
        do
            test -d "${SEARCH_DIR}" || continue
            test "${SEARCH_DIR}" != "${UPDATE_OUTPUT_DIR}" || continue
            find_existing_patch_in_dir "${SEARCH_DIR}"
            STATUS=${?}
            test "${STATUS}" -eq 1 || return "${STATUS}"
        done
    fi
    return 1
}

ALL=0
if [ "${1}" = "-a" ]
then
    ALL=1
    shift
fi
case "${1}" in
    -h|--help) my_usage; exit 0 ;;
esac
TITLE_ID="${1}"
if [ -z "${TITLE_ID}" ]
then
    my_usage
    exit 1
fi
check_valid_psv_id "${TITLE_ID}"

MY_BINARIES="pkg2zip sed grep file python3 pyNPU.py t7z"
downloader_choose
check_binaries "${MY_BINARIES}"
MY_PATH="${NPS_OUTPUT_DIR}"

if [ "${ALL}" -eq 0 ]
then
    LIST="$(pyNPU.py --link --with-version --title-id "${TITLE_ID}")"
else
    LIST="$(pyNPU.py --link --with-version --all --title-id "${TITLE_ID}")"
fi
METADATA_STATUS=${?}
if [ "${METADATA_STATUS}" -eq 2 ] || { [ "${METADATA_STATUS}" -eq 0 ] && [ -z "${LIST}" ]; }
then
    echo "No updates available for title ID \"${TITLE_ID}\"." >&2
    exit 2
elif [ "${METADATA_STATUS}" -ne 0 ]
then
    echo "Cannot retrieve updates for title ID \"${TITLE_ID}\"." >&2
    exit 1
fi

DEFAULT_OUTPUT=0
if [ -n "${DESTDIR}" ]
then
    UPDATE_OUTPUT_DIR="${MY_PATH}/${DESTDIR}_update"
else
    DEFAULT_OUTPUT=1
    GAME_NAME="$(pyNPU.py --name --title-id "${TITLE_ID}")" || exit 1
    case "${TITLE_ID}" in
        PCSA*|PCSE*) REGION_NAME="NTSC" ;;
        PCSB*|PCSF*) REGION_NAME="PAL" ;;
        PCSC*|PCSG*) REGION_NAME="NTSC-J" ;;
        PCSD*|PCSH*) REGION_NAME="NTSC-C" ;;
    esac
    UPDATE_OUTPUT_DIR="${MY_PATH}/${GAME_NAME} [${TITLE_ID}] [${REGION_NAME}]_update"
    # Reuse an existing folder even if the remote display name has changed.
    for EXISTING_DIR in "${MY_PATH}"/*" [${TITLE_ID}] ["*"]_update" \
        "${MY_PATH}/${TITLE_ID}_update"
    do
        if [ -d "${EXISTING_DIR}" ]
        then
            UPDATE_OUTPUT_DIR="${EXISTING_DIR}"
            break
        fi
    done
fi
mkdir -p "${UPDATE_OUTPUT_DIR}" || exit 1
pyNPU.py --changelog --title-id "${TITLE_ID}" > "${UPDATE_OUTPUT_DIR}/changelog.txt"

EXISTING_COUNT=0
DOWNLOADED_COUNT=0
TAB="$(printf '\t')"
while IFS="${TAB}" read -r PATCH_VERSION LINK
do
    printf '%s\n' "${PATCH_VERSION}" | grep -q '^[0-9][0-9]*\.[0-9][0-9]*$' || exit 1
    case "${LINK}" in
        http://*|https://*) ;;
        *) echo "Invalid update URL for version ${PATCH_VERSION}." >&2; exit 1 ;;
    esac
    find_existing_patch
    EXISTING_STATUS=${?}
    case "${EXISTING_STATUS}" in
        0)
            EXISTING_COUNT=$((EXISTING_COUNT + 1))
            continue
            ;;
        2) exit 1 ;;
    esac

    DOWNLOAD_WORK="$(nps_temp_dir "${NPS_DOWNLOAD_DIR}" "${TITLE_ID}-update-download")" || exit 1
    EXTRACT_WORK="$(nps_temp_dir "${NPS_EXTRACT_DIR}" "${TITLE_ID}-update-extract")" || exit 1
    PKG_FILE="${DOWNLOAD_WORK}/${TITLE_ID}_update.pkg"
    my_download_file "${LINK}" "${PKG_FILE}" || exit 1
    PACKAGE_NAME="$(pkg2zip -l "${PKG_FILE}")" || exit 1
    MY_FILE_NAME="$(region_rename "${PACKAGE_NAME%.zip}")"

    # Check the exact package name too, in case metadata uses another version form.
    if [ -e "${UPDATE_OUTPUT_DIR}/${MY_FILE_NAME}.${ext}" ]
    then
        if [ "$(file -b --mime-type "${UPDATE_OUTPUT_DIR}/${MY_FILE_NAME}.${ext}")" != "${mime_type}" ]
        then
            echo "Existing archive is invalid: ${MY_FILE_NAME}.${ext}" >&2
            exit 1
        fi
        EXISTING_COUNT=$((EXISTING_COUNT + 1))
    else
        cd "${EXTRACT_WORK}" || exit 1
        pkg2zip -x "${PKG_FILE}" || exit 1
        t7z -ba -rs a "${UPDATE_OUTPUT_DIR}/${MY_FILE_NAME}.${ext}" "patch/" || exit 1
        DOWNLOADED_COUNT=$((DOWNLOADED_COUNT + 1))
        cd "${MY_PATH}" || exit 1
    fi
    nps_cleanup_dir "${EXTRACT_WORK}" "${NPS_EXTRACT_DIR}"
    nps_cleanup_dir "${DOWNLOAD_WORK}" "${NPS_DOWNLOAD_DIR}"
done <<EOF
${LIST}
EOF

echo "${EXISTING_COUNT} update(s) already present; ${DOWNLOADED_COUNT} downloaded." >&2
if [ "${DOWNLOADED_COUNT}" -eq 0 ] && [ "${EXISTING_COUNT}" -gt 0 ]
then
    exit 5
fi
exit 0
