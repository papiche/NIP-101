#!/bin/bash
# filter/0.sh
# Log profile updates (kind 0) with more fields

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Source common functions
source "$MY_PATH/common.sh"

# Extract event data using optimized common function
event_json="$1"
extract_event_data "$event_json"

# Define log file
LOG_FILE="$HOME/.zen/tmp/nostr_kind0.log"

# Ensure log directory exists
ensure_log_dir "$LOG_FILE"

# Parse additional fields from the content (JSON)
name=$(echo "$content" | jq -r '.name // empty')
display_name=$(echo "$content" | jq -r '.display_name // empty')
about=$(echo "$content" | jq -r '.about // empty')
picture=$(echo "$content" | jq -r '.picture // empty')
picture_64=$(echo "$content" | jq -r '.picture_64 // empty')
website=$(echo "$content" | jq -r '.website // empty')
nip05=$(echo "$content" | jq -r '.nip05 // empty')
g1pub=$(echo "$content" | jq -r '.g1pub // empty')

# Log the profile update with more fields
log_with_timestamp "$LOG_FILE" "=== Profile update (kind 0) ==="
log_with_timestamp "$LOG_FILE" "Pubkey: $pubkey"
log_with_timestamp "$LOG_FILE" "Event ID: $event_id"
log_with_timestamp "$LOG_FILE" "Created at: $created_at"
log_with_timestamp "$LOG_FILE" "Name: $name"
log_with_timestamp "$LOG_FILE" "Display Name: $display_name"
log_with_timestamp "$LOG_FILE" "About: $about"
log_with_timestamp "$LOG_FILE" "Picture URL: $picture"
log_with_timestamp "$LOG_FILE" "Picture 64: $picture_64"
log_with_timestamp "$LOG_FILE" "Website: $website"
log_with_timestamp "$LOG_FILE" "NIP-05: $nip05"
log_with_timestamp "$LOG_FILE" "G1PUB: $g1pub"
log_with_timestamp "$LOG_FILE" "Full content: $content"
log_with_timestamp "$LOG_FILE" "================================"
if check_amis_of_amis "$pubkey"; then
    log_with_timestamp "$LOG_FILE" "Pubkey $pubkey is in amisOfAmis.txt"
fi

# Accept the event
exit 0
