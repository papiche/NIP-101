#!/bin/bash
# filter/22242.sh
# This script handles Nostr events of kind:22242
# It verifies if the pubkey is present in local HEX keys or in the swarm
# and determines the associated email
#
# Example Event Structure:
# {
#   "kind": 22242,
#   "created_at": 1675642635,
#   "content": "Event content...",
#   "tags": [
#     ["t", "topic"],
#     ["e", "event-id", "relay-url"],
#     ["p", "pubkey", "relay-url"]
#   ],
#   "pubkey": "...",
#   "id": "..."
# }

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Define log file for kind 22242 events
LOG_FILE="$HOME/.zen/tmp/nostr_22242.log"

# Ensure the log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function for kind 22242 events
log_event() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Extract necessary information from the JSON event passed as argument
event_json="$1"

event_id=$(echo "$event_json" | jq -r '.event.id')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
content=$(echo "$event_json" | jq -r '.event.content')
created_at=$(echo "$event_json" | jq -r '.event.created_at')

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
    log_event "AUTHORIZED: Pubkey ${pubkey:0:8}... found in local keys with email: $EMAIL"
fi

# If not found locally, check swarm
if [[ "$AUTHORIZED" == "false" ]]; then
    swarm_email=$(search_swarm_for_pubkey "$pubkey")
    if [[ -n "$swarm_email" ]]; then
        AUTHORIZED=true
        EMAIL="$swarm_email"
        SOURCE="swarm"
        log_event "AUTHORIZED: Pubkey ${pubkey:0:8}... found in swarm with email: $EMAIL"
    fi
fi

# If still not found, check amisOfAmis.txt
if [[ "$AUTHORIZED" == "false" ]]; then
    if check_amis_of_amis "$pubkey"; then
        AUTHORIZED=true
        EMAIL="amisOfAmis"
        SOURCE="amisOfAmis"
        log_event "AUTHORIZED: Pubkey ${pubkey:0:8}... found in amisOfAmis.txt"
    fi
fi

# Reject the event if the sender is not authorized
if [[ "$AUTHORIZED" == "false" ]]; then
    log_event "REJECTED: Pubkey ${pubkey:0:8}... not found in local keys, swarm, or amisOfAmis"
    exit 1
fi

# Log the successful event
log_event "ACCEPTED: Kind 22242 event from ${pubkey:0:8}... (Email: $EMAIL, Source: $SOURCE)"

exit 0 