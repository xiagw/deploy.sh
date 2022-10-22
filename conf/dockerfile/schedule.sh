#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

main() {
    for d in /app/*/ /var/www/*/; do
        [[ -f "$d"/cron.sh ]] && bash "$d"/cron.sh
    done
}

main "$@"
