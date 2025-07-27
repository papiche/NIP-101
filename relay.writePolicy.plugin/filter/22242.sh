#!/bin/bash
# filter/22242.sh (OPTIMIZED)
# This script handles Nostr events of kind:22242

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr.auth.22242.log"
ensure_log_dir "$LOG_FILE"

# Logging function
log_event() {
    log_with_timestamp "$LOG_FILE" "$1"
}

# Extract event data in one optimized call
event_json="$1"
extract_event_data "$event_json"

# Check authorization using common function
if ! check_authorization "$pubkey" "log_event"; then
    exit 1
fi

# Log the successful event
log_event "ACCEPTED: Kind 22242 event from ${pubkey:0:8}... (Email: $EMAIL, Source: $SOURCE)"

exit 0 