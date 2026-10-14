#!/bin/sh
# Offline stand-ins for update metadata, downloads, and packaging.
case "${0##*/}" in
    pyNPU.py)
        case " $* " in
            *" --link "*)
                test "${TEST_METADATA_STATUS:-0}" -eq 0 || exit "${TEST_METADATA_STATUS}"
                case " $* " in
                    *" --all "*) cat "${TEST_METADATA_FILE}" ;;
                    *) tail -n 1 "${TEST_METADATA_FILE}" ;;
                esac
                ;;
            *" --name "*) echo 'Test Game' ;;
            *" --changelog "*) echo 'Test changelog' ;;
        esac
        ;;
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
                version="$(cat "${2}")"
                printf 'Test Game [PCSG00025] [JPN] [PATCH] [v%s].zip\n' "${version%.pkg}"
                ;;
            -x) mkdir -p patch; touch patch/content.bin ;;
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
    nps_game.sh)
        printf 'Test Game [PCSG00025] [NTSC-J]\n' > "${NPS_OUTPUT_DIR}/PCSG00025.txt"
        ;;
    nps_dlc.sh) exit 2 ;;
    mktorrent) exit 0 ;;
esac
