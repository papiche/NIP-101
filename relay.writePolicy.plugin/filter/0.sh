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
# Rejeter les bots RSS détectés par le pattern du nom "(RSS Feed)"
if echo "$name" | grep -qi "(RSS Feed)"; then
    log_with_timestamp "$LOG_FILE" "REJECTED: RSS bot by name pattern: $name (pubkey: $pubkey)"
    exit 1
fi

# Rejeter les bots agrégateurs RSS connus via leur domaine nip05
if [[ -n "$nip05" ]] && echo "$nip05" | grep -qiE "@atomstr\.data\.haus$"; then
    log_with_timestamp "$LOG_FILE" "REJECTED: atomstr.data.haus RSS bot (nip05: $nip05, pubkey: $pubkey)"
    exit 1
fi

# Vérifier l'autorisation : accepter uniquement les joueurs MULTIPASS ou amisOfAmis
_log_key() { log_with_timestamp "$LOG_FILE" "$1"; }
check_authorization "$pubkey" "_log_key"

if [[ "$AUTHORIZED" != "true" ]]; then
    log_with_timestamp "$LOG_FILE" "REJECTED: Unauthorized pubkey $pubkey (not in MULTIPASS, swarm, or amisOfAmis)"
    exit 1
fi

if [[ "$SOURCE" == "amisOfAmis" ]]; then
    log_with_timestamp "$LOG_FILE" "Pubkey $pubkey is in amisOfAmis.txt"
fi

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

log_with_timestamp "$LOG_FILE" "ACCEPTED: Authorized pubkey $pubkey (source: $SOURCE, email: $EMAIL)"

# Accept the event
exit 0
