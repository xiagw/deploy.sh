#!/usr/bin/env bash

_backup_zfs() {
    local zfs_src="${1:-zfs01/share}"
    local zfs_dest="${2:-zfs02/share}"
    local snap
    snap="$(date +%s)"
    local start_time
    start_time=$(date +%Y%m%d-%u-%T.%3N)

    echo "Starting backup at $start_time"
    zfs list -t snapshot

    # Rename existing snapshots
    for fs in "$zfs_src" "$zfs_dest"; do
        if zfs list -t snapshot -o name -s creation -H -r "${fs}@now"; then
            zfs list -t snapshot -o name -s creation -H -r "${fs}@last" &&
                zfs rename "${fs}@last" "${fs}@${snap}"
            zfs rename "${fs}@now" "${fs}@last"
        fi
    done

    # Create new snapshot
    zfs snapshot "${zfs_src}@now"

    # Check for pv command
    local has_pv=0
    command -v pv >/dev/null 2>&1 && has_pv=1

    # Perform incremental or full backup
    if zfs list -t snapshot -o name -s creation -H -r "${zfs_src}@last" >/dev/null 2>&1; then
        # Incremental backup
        if [[ "$has_pv" -eq 1 ]]; then
            zfs send -v -i "${zfs_src}@last" "${zfs_src}@now" | pv | zfs recv "${zfs_dest}"
        else
            zfs send -v -i "${zfs_src}@last" "${zfs_src}@now" | zfs recv "${zfs_dest}"
        fi
    else
        ## full backup
        zfs snapshot "${zfs_src}@last"
        if [[ "$has_pv" -eq 1 ]]; then
            zfs send -v "${zfs_src}@last" | pv | zfs recv "${zfs_dest}"
        else
            zfs send -v "${zfs_src}@last" | zfs recv "${zfs_dest}"
        fi
    fi

    # Clear snapshots
    zfs destroy "${zfs_src}@${snap}" "${zfs_dest}@${snap}"

    echo "Backup completed at $(date +%Y%m%d-%u-%T.%3N)"
    echo "Total duration: $(($(date +%s) - snap)) seconds"
}

set -e
_backup_zfs "$@"
