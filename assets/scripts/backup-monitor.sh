#!/usr/bin/env bash

set -euo pipefail

CONFIG_DIR="${HOME}/.config/cachyos-migration-tool"
BACKUP_ENV="${CONFIG_DIR}/backup.env"
STATUS_FILE="${CONFIG_DIR}/backup-status.json"
RESTIC_PASSWORD_FILE="${CONFIG_DIR}/restic-password"

if [ ! -f "$BACKUP_ENV" ]; then
    printf '{"status":"fail","snapshot_count":0,"total_size_gb":0,"last_snapshot_time":"","last_snapshot_id":"","error":"Config file not found"}\n' > "$STATUS_FILE"
    exit 1
fi

# shellcheck disable=SC1090
source "$BACKUP_ENV"

export RESTIC_PASSWORD_FILE

build_status_json() {
    local status="$1"
    local count="$2"
    local size="$3"
    local time="$4"
    local id="$5"
    local error="$6"
    local server="$7"
    local server_status="$8"

    local formatted_size=""
    formatted_size="$(LC_NUMERIC=C printf "%.1f" "$size" 2>/dev/null || echo "0")"
    cat <<EOF
{"status":"$status","snapshot_count":$count,"total_size_gb":$formatted_size,"last_snapshot_time":"$time","last_snapshot_id":"$id","error":"$error","server":"$server","server_status":"$server_status"}
EOF
}

try_repo() {
    local repo_host="$1"
    local repo_path="$2"
    [ -n "$repo_host" ] || return 1

    export RESTIC_REPOSITORY="sftp:${repo_host}:${repo_path}"

    # Match the backup runner: prefer validating the SFTP endpoint instead of a
    # generic SSH command, because some hosts allow the repository transport but
    # reject ad hoc shell commands.
    if ! printf 'pwd\nbye\n' | sftp -o BatchMode=yes -o ConnectTimeout="${BACKUP_CONNECT_TIMEOUT:-8}" "$repo_host" >/dev/null 2>&1; then
        return 1
    fi

    if ! restic cat config >/dev/null 2>&1; then
        return 2
    fi

    return 0
}

check_stale() {
    local last_time="$1"
    if [ -z "$last_time" ]; then
        return 1
    fi

    local last_epoch=0
    local now_epoch=0
    last_epoch="$(date -d "$last_time" +%s 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    local diff=$((now_epoch - last_epoch))
    local stale_threshold=$((86400))

    [ "$diff" -gt "$stale_threshold" ]
}

main() {
    local count=0
    local size_gb=0
    local last_time=""
    local last_id=""
    local status="fail"
    local error=""
    local server=""
    local server_status="fail"
    local snapshots_json

    if try_repo "$BACKUP_SFTP_HOST_LAN" "$BACKUP_SFTP_REPOSITORY_PATH" 2>/dev/null; then
        server="LAN"
        server_status="ok"
        :
    elif try_repo "$BACKUP_SFTP_HOST_REMOTE" "$BACKUP_SFTP_REPOSITORY_PATH" 2>/dev/null; then
        server="Internet"
        server_status="ok"
        :
    else
        build_status_json "fail" 0 0 "" "" "Repository not accessible" "" "fail" > "$STATUS_FILE"
        return 1
    fi

    if ! snapshots_json=$(restic snapshots --json 2>/dev/null); then
        build_status_json "fail" 0 0 "" "" "Failed to read snapshots" "$server" "$server_status" > "$STATUS_FILE"
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        count=$(echo "$snapshots_json" | jq 'length' 2>/dev/null || echo 0)
        if [ "$count" -gt 0 ]; then
            last_time=$(echo "$snapshots_json" | jq -r '.[-1].time' 2>/dev/null | cut -d'T' -f1,2 | cut -d'.' -f1)
            last_id=$(echo "$snapshots_json" | jq -r '.[-1].short_id' 2>/dev/null)
        fi
    else
        count=$(echo "$snapshots_json" | grep -c '"time"' || echo 0)
        if [ "$count" -gt 0 ]; then
            last_time=$(echo "$snapshots_json" | grep '"time"' | tail -1 | sed 's/.*"\([^"]*\)".*/\1/' | cut -d'T' -f1,2 | cut -d'.' -f1)
            last_id=$(echo "$snapshots_json" | grep '"short_id"' | tail -1 | sed 's/.*"\([^"]*\)".*/\1/')
        fi
    fi

    if ! stats_output=$(restic stats 2>/dev/null | grep "Total Size" || echo ""); then
        build_status_json "fail" "$count" 0 "$last_time" "$last_id" "Failed to calculate stats" "$server" "$server_status" > "$STATUS_FILE"
        return 1
    fi

    if [ -n "$stats_output" ]; then
        size_gb=$(echo "$stats_output" | awk '{print $(NF-1)}' | sed 's/GiB//' || echo 0)
    else
        size_gb=0
    fi

    status="ok"
    error=""
    if [ "$count" -eq 0 ]; then
        status="pending"
        error="No snapshots yet"
    elif check_stale "$last_time"; then
        status="stale"
        error="No recent backup"
    fi

    build_status_json "$status" "$count" "$size_gb" "$last_time" "$last_id" "$error" "$server" "$server_status" > "$STATUS_FILE"
}

main "$@"
