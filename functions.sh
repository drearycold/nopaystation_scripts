#!/bin/sh

ext="7z"
mime_type="application/x-7z-compressed"

nps_load_config() {
    local call_dir config_file env_download env_extract env_output env_checksum_action

    call_dir="$(pwd)"
    config_file="${XDG_CONFIG_HOME:-${HOME}/.config}/nopaystation/config"
    env_download="${NPS_DOWNLOAD_DIR:-}"
    env_extract="${NPS_EXTRACT_DIR:-}"
    env_output="${NPS_OUTPUT_DIR:-}"
    env_checksum_action="${NPS_CHECKSUM_MISMATCH_ACTION:-}"

    NPS_DOWNLOAD_DIR="${call_dir}"
    NPS_EXTRACT_DIR="${call_dir}"
    NPS_OUTPUT_DIR="${call_dir}"
    NPS_CHECKSUM_MISMATCH_ACTION="no"
    if [ -f "${config_file}" ]
    then
        . "${config_file}"
    fi

    test -n "${env_download}" && NPS_DOWNLOAD_DIR="${env_download}"
    test -n "${env_extract}" && NPS_EXTRACT_DIR="${env_extract}"
    test -n "${env_output}" && NPS_OUTPUT_DIR="${env_output}"
    test -n "${env_checksum_action}" && NPS_CHECKSUM_MISMATCH_ACTION="${env_checksum_action}"

    mkdir -p "${NPS_DOWNLOAD_DIR}" "${NPS_EXTRACT_DIR}" "${NPS_OUTPUT_DIR}" || exit 1
    NPS_DOWNLOAD_DIR="$(cd "${NPS_DOWNLOAD_DIR}" && pwd)"
    NPS_EXTRACT_DIR="$(cd "${NPS_EXTRACT_DIR}" && pwd)"
    NPS_OUTPUT_DIR="$(cd "${NPS_OUTPUT_DIR}" && pwd)"
    export NPS_DOWNLOAD_DIR NPS_EXTRACT_DIR NPS_OUTPUT_DIR NPS_CHECKSUM_MISMATCH_ACTION
}

nps_temp_dir() {
    local parent label

    parent="${1}"
    label="${2}"
    mktemp -d "${parent%/}/nps-${label}.XXXXXX"
}

nps_cleanup_dir() {
    local directory parent

    directory="${1}"
    parent="${2}"
    case "${directory}" in
        "${parent%/}"/nps-*) rm -rf "${directory}" ;;
        *) echo "Refusing to remove unexpected temporary directory: ${directory}" >&2 ;;
    esac
}

sha256_choose() {
    if which sha256 > /dev/null 2>&1
    then
        MY_BINARIES="${MY_BINARIES} sha256"
        SHA256="sha256"
    else
        MY_BINARIES="${MY_BINARIES} sha256sum"
        SHA256="sha256sum"
    fi
}

my_sha256() {
    local file="${1}"

    case "$SHA256" in
        "sha256sum")
        sha256sum "${file}" | awk '{ print $1 }' ;;
        "sha256")
        sha256    "${file}" | awk '{ print $4 }' ;;
    esac
}

downloader_choose() {
    if which wget > /dev/null 2>&1
    then
        MY_BINARIES="${MY_BINARIES} wget"
        DOWNLOADER="wget"
    else
        MY_BINARIES="${MY_BINARIES} curl"
        DOWNLOADER="curl"
    fi
}

my_download_file() {
    local url="${1}"
    local destination="${2}"

    case "${DOWNLOADER}" in
        "wget")
        wget --no-verbose --show-progress -O "${destination}" "${url}" ;;
        "curl")
        curl --progress-bar -o "${destination}" "${url}" ;;
    esac
}

check_binaries(){
    local BINARIES="${1}"
    for bins in ${BINARIES}
    do
        if ! which ${bins} > /dev/null 2>&1
        then
            echo "${bins} isn't installed."
            echo "Please install it and try again"
            exit 1
        fi
    done
}

region_rename() {
    local NAME="${1}"

    if echo "${NAME}" | grep -q "\[USA\]"
    then
        local NAME="$(echo "${NAME}" | sed 's/USA/NTSC/g')"
    elif echo "${NAME}" | grep -q "\[JPN\]"
    then
        NAME="$(echo "${NAME}" | sed 's/JPN/NTSC-J/g')"
    elif echo "${NAME}" | grep -q "\[EUR\]"
    then
        NAME="$(echo "${NAME}" | sed 's/EUR/PAL/g')"
    elif echo "${NAME}" | grep -q "\[ASA\]"
    then
        NAME="$(echo "${NAME}" | sed 's/ASA/NTSC-C/g')"
    fi
    echo ${NAME}
}

check_valid_psv_id() {
    local TITLE_ID="${1}"
    if ! echo "${TITLE_ID}" | grep -q -E -i 'PCS[ABCDEFGH][0-9]{5}'
    then
        echo ""
        echo "Error"
        echo "Title ID is not valid."
        echo "It should be the following format:"
        echo "PCSA01234"
        echo "Check your title id parameter."
        exit 1
    fi
}

check_valid_psm_id() {
    local TITLE_ID="${1}"
    if ! echo "${TITLE_ID}" | grep -q -E -i 'NP[NPOQ]A[0-9]{5}'
    then
        echo ""
        echo "Error"
        echo "Title ID is not valid."
        echo "It should be the following format:"
        echo "NPNA01234"
        echo "Check your title id parameter."
        exit 1
    fi
}

check_valid_psp_id() {
    local TITLE_ID="${1}"
    if ! echo "${TITLE_ID}" | grep -q -E -i '[NU][PCL][UJEHA][DFGHJQSXZ][0-9]{5}'
    then
        echo ""
        echo "Error"
        echo "Title ID is not valid."
        echo "It should be the following format:"
        echo "NPUF00001"
        echo "Check your title id parameter."
        exit 1
    fi
}

yesno_checksum() {
    local GAME_ID="${1}"
    local DOWNLOAD_FILE="${2:-${GAME_ID}.pkg}"
    while true
    do
        echo "Do you want to continue? (yes/no)"
        if ! read INPUT
        then
            INPUT="no"
        fi
        case "${INPUT}" in
            Yes|YES|yes|Y|y)
                break
                ;;
            No|NO|no|n)
                echo "User aborted."
                if [ -n "${DOWNLOAD_FILE}" ] && [ -e "${DOWNLOAD_FILE}" ]
                then
                    if rm "${DOWNLOAD_FILE}"
                    then
                        echo "Downloaded file removed."
                    else
                        echo "Something went wrong while removing pkg file."
                    fi
                fi
                exit 1
                ;;
        esac
    done
}

checksum_mismatch_action() {
    local DOWNLOAD_FILE="${1}"
    local ACTION

    ACTION="$(printf '%s' "${NPS_CHECKSUM_MISMATCH_ACTION:-no}" | tr '[:upper:]' '[:lower:]')"
    case "${ACTION}" in
        yes|continue)
            echo "Continuing despite checksum mismatch."
            ;;
        prompt|ask|interactive)
            yesno_checksum "" "${DOWNLOAD_FILE}"
            ;;
        no|abort|"")
            echo "Aborting because of checksum mismatch."
            if [ -n "${DOWNLOAD_FILE}" ] && [ -e "${DOWNLOAD_FILE}" ]
            then
                rm "${DOWNLOAD_FILE}"
                echo "Downloaded file removed."
            fi
            exit 1
            ;;
        *)
            echo "Invalid NPS_CHECKSUM_MISMATCH_ACTION: ${NPS_CHECKSUM_MISMATCH_ACTION}" >&2
            echo "Use no, yes, or prompt. Aborting." >&2
            exit 1
            ;;
    esac
}
exit_if_fail() {
    local _msg="${1}"
    if [ "${?}" -ne 0 ]
    then
        echo "${_msg}"
        exit 1
    fi
}

check_announce_url() {
    local URL="${1}"
    echo "${URL}" | grep "^http" &> /dev/null
    if [ ${?} -ne 0 ]
    then
        echo "No valid announce url provided. Be sure that the url starts with \"http\" and has a correct hostname"
        exit 1
    fi
}

compare_checksum(){
    local LIST="${1}"
    local FILE="${2}"
    local DOWNLOAD_FILE="${3:-}"
    if [ -n "${LIST}" ]
    then
        if [ "${FILE}" != "${LIST}" ]
        then
            echo "Checksum of downloaded file does not match checksum in list"
            echo "${FILE} != ${LIST}"
            checksum_mismatch_action "${DOWNLOAD_FILE}"
        fi
    else
        echo "No checksum available in *.tsv list."
        echo "Maybe you could report it:"
        echo "\"${FILE}\""
        echo ""
    fi
}
