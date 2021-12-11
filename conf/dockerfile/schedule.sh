#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

main() {
    for d in /app/*/ /var/www/*/; do
        [[ -f "$d"/task.sh ]] && bash "$d"/task.sh
    done
}

main "$@"
