#!/bin/bash
# filter/30303.sh
# Log TrocZen BON (kind 30303)

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Source common functions
source "$MY_PATH/common.sh"

# Extract event data using optimized common function
event_json="$1"
extract_event_data "$event_json"

# Define log file
LOG_FILE="$HOME/.zen/tmp/nostr_kind30303.log"

# Ensure log directory exists
ensure_log_dir "$LOG_FILE"


# Log the profile update with more fields
log_with_timestamp "$LOG_FILE" "=== TrocZen BON (kind 30303) ==="
log_with_timestamp "$LOG_FILE" "Pubkey: $pubkey"
log_with_timestamp "$LOG_FILE" "Event ID: $event_id"
log_with_timestamp "$LOG_FILE" "Full content: $content"
if check_amis_of_amis "$pubkey"; then
    log_with_timestamp "Pubkey is in amisOfAmis.txt"
fi
log_with_timestamp "$LOG_FILE" "================================"

# Accept the event
exit 0
