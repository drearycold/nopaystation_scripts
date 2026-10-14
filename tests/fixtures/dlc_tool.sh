#!/bin/sh
# Offline stand-ins for external tools used by the DLC regression tests.
case "${0##*/}" in
    wget)
        while [ "${#}" -gt 0 ]
        do
            case "${1}" in
                -O) shift; destination="${1}" ;;
                https://*) link="${1}" ;;
            esac
            shift
        done
        printf '%s\n' "${link}" >> "${TEST_DOWNLOAD_LOG}"
        printf '%s' "${link##*/}" > "${destination}"
        ;;
    pkg2zip)
        case "${1}" in
            -l)
                dlc_id="$(cat "${2}")"
                printf 'Test DLC [PCSG00025] [JPN] [DLC-%s].zip\n' "${dlc_id%.pkg}"
                ;;
            -x) mkdir -p addcont; touch addcont/content.bin ;;
        esac
        ;;
    t7z)
        test "${TEST_FAIL_ARCHIVE:-0}" -eq 0 || exit 1
        printf 'archive' > "${4}"
        ;;
    file)
        if [ "$(cat "${3}")" = archive ]
        then
            echo application/x-7z-compressed
        else
            echo text/plain
        fi
        ;;
    mktorrent) exit 0 ;;
esac
