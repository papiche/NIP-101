#!/bin/bash
# filter/30078.sh
# This script handles Nostr events of kind:30078 (user statuses/mood updates)
#
# NIP-38 Overview:
# - kind:30078 is used for user statuses and mood updates
# - Contains information about a user's current status, mood, or activity
# - Must include 'd' tag with a unique identifier for the status
# - Can include 'content' with the status message
# - Can include 'emoji' tag with mood emoji
# - Can include 'expiration' tag with expiration timestamp
# - Can include 'status' tag with status type (online, away, busy, etc.)
#
# Example Event Structure:
# {
#   "kind": 30078,
#   "created_at": 1675642635,
#   "content": "Working on UPlanet project",
#   "tags": [
#     ["d", "status-2024-01-15"],
#     ["emoji", "💻"],
#     ["status", "busy"],
#     ["expiration", "1675729035"],
#     ["t", "status"]
#   ],
#   "pubkey": "...",
#   "id": "..."
# }

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Define log file for kind 30078 events
LOG_FILE="$HOME/.zen/tmp/nostr_statuses.30078.log"

# Ensure the log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function for kind 30078 events
log_status() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Extract necessary information from the JSON event passed as argument
event_json="$1"

event_id=$(echo "$event_json" | jq -r '.event.id')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
content=$(echo "$event_json" | jq -r '.event.content')
created_at=$(echo "$event_json" | jq -r '.event.created_at')

# Extract important tags
status_id=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "d") | .[1]' | head -n1)
emoji=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "emoji") | .[1]' | head -n1)
status_type=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "status") | .[1]' | head -n1)
expiration=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "expiration") | .[1]' | head -n1)

# Function to check if a key is authorized and get the associated email
KEY_DIR="$HOME/.zen/game/nostr"
get_key_email() {
    local pubkey="$1"
    local key_file
    local found_email=""

    while IFS= read -r -d $'\0' key_file; do
        if [[ "$pubkey" == "$(cat "$key_file")" ]]; then
            # Extract the directory name which should be the email
            found_email=$(basename "$(dirname "$key_file")")
            echo "$found_email"
            return 0 # Key authorized
        fi
    done < <(find "$KEY_DIR" -type f -name "HEX" -print0)
    echo ""
    return 1 # Key not authorized
}

# Function to search for pubkey in swarm and get associated G1PUBNOSTR
search_swarm_for_pubkey() {
    local pubkey="$1"
    
    # Search for the specific HEX in SWARM PLAYERs
    FOUND_DIR=$(find ${HOME}/.zen/tmp/swarm/*/TW/* -name "HEX" -exec grep -l "$pubkey" {} \; 2>/dev/null)
    [[ -z "$FOUND_DIR" ]] && FOUND_DIR=$(find ${HOME}/.zen/tmp/${IPFSNODEID}/TW/* -name "HEX" -exec grep -l "$pubkey" {} \; 2>/dev/null)

    if [ -n "$FOUND_DIR" ]; then
        # Get the directory name which should be the email
        local swarm_email=$(basename "$(dirname "$FOUND_DIR")")
        echo "$swarm_email"
        return 0
    else
        echo ""
        return 1
    fi
}

# Check if pubkey is in amisOfAmis.txt
check_amis_of_amis() {
    local pubkey="$1"
    AMISOFAMIS_FILE="${HOME}/.zen/strfry/amisOfAmis.txt"
    
    if [[ -f "$AMISOFAMIS_FILE" && "$pubkey" != "" ]]; then
        if grep -q "^$pubkey$" "$AMISOFAMIS_FILE"; then
            return 0 # Found in amisOfAmis
        fi
    fi
    return 1 # Not found in amisOfAmis
}

# Main verification logic
AUTHORIZED=false
EMAIL=""
SOURCE=""

# First, check local HEX keys
local_email=$(get_key_email "$pubkey")
if [[ -n "$local_email" ]]; then
    AUTHORIZED=true
    EMAIL="$local_email"
    SOURCE="local"
    log_status "AUTHORIZED: Status sender ${pubkey:0:8}... found in local keys with email: $EMAIL"
fi

# If not found locally, check swarm
if [[ "$AUTHORIZED" == "false" ]]; then
    swarm_email=$(search_swarm_for_pubkey "$pubkey")
    if [[ -n "$swarm_email" ]]; then
        AUTHORIZED=true
        EMAIL="$swarm_email"
        SOURCE="swarm"
        log_status "AUTHORIZED: Status sender ${pubkey:0:8}... found in swarm with email: $EMAIL"
    fi
fi

# If still not found, check amisOfAmis.txt
if [[ "$AUTHORIZED" == "false" ]]; then
    if check_amis_of_amis "$pubkey"; then
        AUTHORIZED=true
        EMAIL="amisOfAmis"
        SOURCE="amisOfAmis"
        log_status "AUTHORIZED: Status sender ${pubkey:0:8}... found in amisOfAmis.txt"
    fi
fi

# Reject the event if the sender is not authorized
if [[ "$AUTHORIZED" == "false" ]]; then
    log_status "REJECTED: Status sender ${pubkey:0:8}... not found in local keys, swarm, or amisOfAmis"
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
if [[ -n "$status_type" ]]; then
    log_status "STATUS: Type: $status_type"
fi
if [[ -n "$emoji" ]]; then
    log_status "STATUS: Emoji: $emoji"
fi
if [[ -n "$content" ]]; then
    log_status "STATUS: Message: $content"
fi
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
        if [[ -n "$status_type" ]]; then
            log_status "INFO: Custom status type: $status_type"
        fi
        ;;
esac

# Check for UPlanet-specific content
if [[ -n "$content" ]]; then
    if [[ "$content" == *"UPlanet"* || "$content" == *"#BRO"* || "$content" == *"#BOT"* ]]; then
        log_status "UPLANET: Status contains UPlanet-related content"
    fi
fi

echo ">>> (30078) STATUS: ${pubkey:0:8}... → $status_id ${emoji:-} ${status_type:-}"

exit 0 