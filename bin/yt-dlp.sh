#!/usr/bin/env bash

set -x
# Download youtube video with desired quality
# youtube-dl accepts both fully qualified URLs and video id's such as AQcQgfvfF1M

me_name="$(basename "$0")"
me_path="$(cd "$(dirname "$0")" && pwd)"

if command -v yt-dlp; then
    yt_opt='yt-dlp'
elif command -v youtube-dl; then
    yt_opt='youtube-dl'
else
    echo "command \"$yt_opt\" not found"
    exit 1
fi

url_file=$me_path/${me_name}.url.txt

while [ $# -ge 0 ]; do
    case $1 in
    -a | --aria2c | --aria2)
        yt_opt="$yt_opt --external-downloader aria2c"
        ;;
    -f | --format)
        video_type=$2
        shift
        ;;
    -p | --proxy)
        yt_opt="$yt_opt --proxy ${http_proxy:-http://127.0.0.1:1080}"
        ;;
    -k | --keep-video)
        yt_opt="$yt_opt --keep-video"
        ;;
    -r | --restrict-filenames)
        yt_opt="$yt_opt --restrict-filenames"
        ;;
    -u | --url)
        url_file=$2
        shift
        ;;
    *)
        if [ -z "$1" ]; then
            urls="$(cat "$url_file")"
            if [ -z "$urls" ]; then
                echo "No URLs found in $url_file, exit."
                exit 1
            fi
        else
            urls="$*"
        fi
        break
        ;;
    esac
    shift
done

for url in $urls; do
    tmp_file=$(mktemp)
    echo "Fetching available formats for $url..."
    $yt_opt --list-formats "$url" | tee "$tmp_file"

    video_type="${video_type:-$(awk '/[0-9].*mp4/ {print $1}' "$tmp_file" | grep -v '\(best\)' | tail -n 1)}"
    audio_type="${audio_type:-$(awk '/[0-9].*m4a/ {print $1}' "$tmp_file" | tail -n 1)}"
    echo "Streaming with quality ${video_type}+${audio_type} ..."
    # mpv --cache=1024 $(youtube-dl -f $FORMAT -g "$url")
    if [[ -z "${video_type}" || -z "${audio_type}" ]]; then
        format_opt="mp4"
    else
        format_opt="${video_type:-mp4}+${audio_type}"
    fi
    $yt_opt -o "%(id)s.%(title).50s.%(ext)s" --format "$format_opt" "$url"

    unset audio_type video_type
    rm -f "$tmp_file"
done
