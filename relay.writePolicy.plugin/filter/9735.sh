#!/bin/bash
# filter/9735.sh
# This script handles Nostr events of kind:9735 (Zap receipts)
#
# NIP-57 Overview:
# - kind:9735 is used for Zap receipts
# - Contains information about a Zap payment
# - Must include 'p' tag with the recipient's pubkey
# - Must include 'e' tag with the event being zapped (optional)
# - Must include 'bolt11' tag with the Lightning invoice
# - Must include 'description' tag with the Zap request
# - Can include 'preimage' tag with the payment preimage
# - Can include 'amount' tag with the amount in millisatoshis
#
# Example Event Structure:
# {
#   "kind": 9735,
#   "created_at": 1675642635,
#   "content": "",
#   "tags": [
#     ["p", "recipient-pubkey"],
#     ["e", "event-being-zapped"],
#     ["bolt11", "lightning-invoice"],
#     ["description", "zap-request"],
#     ["preimage", "payment-preimage"],
#     ["amount", "1000"]
#   ],
#   "pubkey": "...",
#   "id": "..."
# }

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Define log file for kind 9735 events
LOG_FILE="$HOME/.zen/tmp/nostr_zaps.9735.log"

# Ensure the log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function for kind 9735 events
log_zap() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Extract necessary information from the JSON event passed as argument
event_json="$1"

event_id=$(echo "$event_json" | jq -r '.event.id')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
content=$(echo "$event_json" | jq -r '.event.content')
created_at=$(echo "$event_json" | jq -r '.event.created_at')

# Extract important tags
recipient_pubkey=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "p") | .[1]' | head -n1)
zapped_event_id=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "e") | .[1]' | head -n1)
bolt11_invoice=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "bolt11") | .[1]' | head -n1)
description=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "description") | .[1]' | head -n1)
preimage=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "preimage") | .[1]' | head -n1)
amount=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "amount") | .[1]' | head -n1)

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
    log_zap "AUTHORIZED: Zap sender ${pubkey:0:8}... found in local keys with email: $EMAIL"
fi

# If not found locally, check swarm
if [[ "$AUTHORIZED" == "false" ]]; then
    swarm_email=$(search_swarm_for_pubkey "$pubkey")
    if [[ -n "$swarm_email" ]]; then
        AUTHORIZED=true
        EMAIL="$swarm_email"
        SOURCE="swarm"
        log_zap "AUTHORIZED: Zap sender ${pubkey:0:8}... found in swarm with email: $EMAIL"
    fi
fi

# If still not found, check amisOfAmis.txt
if [[ "$AUTHORIZED" == "false" ]]; then
    if check_amis_of_amis "$pubkey"; then
        AUTHORIZED=true
        EMAIL="amisOfAmis"
        SOURCE="amisOfAmis"
        log_zap "AUTHORIZED: Zap sender ${pubkey:0:8}... found in amisOfAmis.txt"
    fi
fi

# Reject the event if the sender is not authorized
if [[ "$AUTHORIZED" == "false" ]]; then
    log_zap "REJECTED: Zap sender ${pubkey:0:8}... not found in local keys, swarm, or amisOfAmis"
    exit 1
fi

# Validate required tags
if [[ -z "$recipient_pubkey" ]]; then
    log_zap "REJECTED: Zap missing required 'p' tag (recipient pubkey)"
    exit 1
fi

if [[ -z "$bolt11_invoice" ]]; then
    log_zap "REJECTED: Zap missing required 'bolt11' tag (Lightning invoice)"
    exit 1
fi

if [[ -z "$description" ]]; then
    log_zap "REJECTED: Zap missing required 'description' tag (Zap request)"
    exit 1
fi

# Check if recipient is part of UPlanet
recipient_in_uplanet=false
recipient_g1pubnostr=""

# Check if recipient is in local keys
recipient_local_email=$(get_key_email "$recipient_pubkey")
if [[ -n "$recipient_local_email" ]]; then
    recipient_in_uplanet=true
    recipient_g1pubnostr="$recipient_local_email"
fi

# If not found locally, check swarm
if [[ "$recipient_in_uplanet" == "false" ]]; then
    recipient_swarm_email=$(search_swarm_for_pubkey "$recipient_pubkey")
    if [[ -n "$recipient_swarm_email" ]]; then
        recipient_in_uplanet=true
        recipient_g1pubnostr="$recipient_swarm_email"
    fi
fi

# If still not found, check amisOfAmis.txt
if [[ "$recipient_in_uplanet" == "false" ]]; then
    if check_amis_of_amis "$recipient_pubkey"; then
        recipient_in_uplanet=true
        recipient_g1pubnostr="amisOfAmis"
    fi
fi

# Log the zap details
if [[ "$recipient_in_uplanet" == "true" ]]; then
    log_zap "ZAP: ${pubkey:0:8}... zapped ${recipient_pubkey:0:8}... (UPlanet member: $recipient_g1pubnostr)"
    if [[ -n "$zapped_event_id" ]]; then
        log_zap "ZAP: Event being zapped: ${zapped_event_id:0:8}..."
    fi
    if [[ -n "$amount" ]]; then
        log_zap "ZAP: Amount: ${amount} millisatoshis"
    fi
else
    log_zap "ZAP: ${pubkey:0:8}... zapped external user ${recipient_pubkey:0:8}..."
fi

echo ">>> (9735) ZAP: ${pubkey:0:8}... → ${recipient_pubkey:0:8}... (${amount:-unknown} msat)"

exit 0 