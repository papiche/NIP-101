#!/bin/bash
# filter/30078.sh (OPTIMIZED)
# This script handles Nostr events of kind:30078 (user statuses/mood updates)

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr_statuses.30078.log"
ensure_log_dir "$LOG_FILE"

# Logging function for statuses
log_status() {
    log_with_timestamp "$LOG_FILE" "$1"
}

# Extract event data in one optimized call
event_json="$1"
extract_event_data "$event_json"

# Extract specific tags for kind 30078 events
extract_tags "$event_json" "d" "emoji" "status" "expiration"
status_id="$d"
emoji="$emoji"
status_type="$status"
expiration="$expiration"

# Check authorization using common function
if ! check_authorization "$pubkey" "log_status"; then
    exit 1
fi

# Validate required tags
if [[ -z "$status_id" ]]; then
    log_status "REJECTED: Status missing required 'd' tag (status identifier)"
    exit 1
fi

# Check if status has expired
if [[ -n "$expiration" ]]; then
    current_time=$(date +%s)
    if [[ "$current_time" -gt "$expiration" ]]; then
        log_status "REJECTED: Status has expired (expired: $expiration, current: $current_time)"
        exit 1
    fi
fi

# Log the status details
log_status "STATUS: ${pubkey:0:8}... updated status (ID: $status_id)"
[[ -n "$status_type" ]] && log_status "STATUS: Type: $status_type"
[[ -n "$emoji" ]] && log_status "STATUS: Emoji: $emoji"
[[ -n "$content" ]] && log_status "STATUS: Message: $content"

if [[ -n "$expiration" ]]; then
    expiration_date=$(date -d "@$expiration" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    log_status "STATUS: Expires: $expiration_date"
fi

# Check for specific status types that might be interesting
case "$status_type" in
    "online"|"available")
        log_status "INFO: User is online and available"
        ;;
    "away"|"busy"|"dnd")
        log_status "INFO: User is away/busy/do not disturb"
        ;;
    "offline")
        log_status "INFO: User marked as offline"
        ;;
    "streaming"|"gaming")
        log_status "INFO: User is streaming/gaming"
        ;;
    *)
        [[ -n "$status_type" ]] && log_status "INFO: Custom status type: $status_type"
        ;;
esac

# Check for UPlanet-specific content
if [[ -n "$content" ]]; then
    if [[ "$content" == *"UPlanet"* || "$content" == *"#BRO"* || "$content" == *"#BOT"* ]]; then
        log_status "UPLANET: Status contains UPlanet-related content"
    fi
fi

log_status "ACCEPTED: Status from ${pubkey:0:8}... (Email: $EMAIL, Source: $SOURCE)"
echo ">>> (30078) STATUS: ${pubkey:0:8}... → $status_id ${emoji:-} ${status_type:-}"

exit 0 