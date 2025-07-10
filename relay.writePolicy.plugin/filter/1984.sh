#!/bin/bash
# filter/1984.sh
# This script handles Nostr events of kind:1984 (reporting events)
#
# NIP-56 Overview:
# - kind:1984 is used for reporting events
# - Contains information about a report against another event or user
# - Must include 'p' tag with the reported user's pubkey
# - Must include 'e' tag with the reported event ID (optional)
# - Must include 'report-type' tag with the type of report
# - Can include 'content' with additional details about the report
# - Can include 'reason' tag with the reason for the report
#
# Example Event Structure:
# {
#   "kind": 1984,
#   "created_at": 1675642635,
#   "content": "Additional details about the report...",
#   "tags": [
#     ["p", "reported-user-pubkey"],
#     ["e", "reported-event-id"],
#     ["report-type", "spam"],
#     ["reason", "Excessive posting"],
#     ["t", "report"]
#   ],
#   "pubkey": "...",
#   "id": "..."
# }

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Define log file for kind 1984 events
LOG_FILE="$HOME/.zen/tmp/nostr_reports.1984.log"

# Ensure the log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function for kind 1984 events
log_report() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Extract necessary information from the JSON event passed as argument
event_json="$1"

event_id=$(echo "$event_json" | jq -r '.event.id')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
content=$(echo "$event_json" | jq -r '.event.content')
created_at=$(echo "$event_json" | jq -r '.event.created_at')

# Extract important tags
reported_pubkey=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "p") | .[1]' | head -n1)
reported_event_id=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "e") | .[1]' | head -n1)
report_type=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "report-type") | .[1]' | head -n1)
reason=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "reason") | .[1]' | head -n1)

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
    log_report "AUTHORIZED: Report sender ${pubkey:0:8}... found in local keys with email: $EMAIL"
fi

# If not found locally, check swarm
if [[ "$AUTHORIZED" == "false" ]]; then
    swarm_email=$(search_swarm_for_pubkey "$pubkey")
    if [[ -n "$swarm_email" ]]; then
        AUTHORIZED=true
        EMAIL="$swarm_email"
        SOURCE="swarm"
        log_report "AUTHORIZED: Report sender ${pubkey:0:8}... found in swarm with email: $EMAIL"
    fi
fi

# If still not found, check amisOfAmis.txt
if [[ "$AUTHORIZED" == "false" ]]; then
    if check_amis_of_amis "$pubkey"; then
        AUTHORIZED=true
        EMAIL="amisOfAmis"
        SOURCE="amisOfAmis"
        log_report "AUTHORIZED: Report sender ${pubkey:0:8}... found in amisOfAmis.txt"
    fi
fi

# Reject the event if the sender is not authorized
if [[ "$AUTHORIZED" == "false" ]]; then
    log_report "REJECTED: Report sender ${pubkey:0:8}... not found in local keys, swarm, or amisOfAmis"
    exit 1
fi

# Validate required tags
if [[ -z "$reported_pubkey" ]]; then
    log_report "REJECTED: Report missing required 'p' tag (reported user pubkey)"
    exit 1
fi

if [[ -z "$report_type" ]]; then
    log_report "REJECTED: Report missing required 'report-type' tag"
    exit 1
fi

# Check if reported user is part of UPlanet
reported_in_uplanet=false
reported_g1pubnostr=""

# Check if reported user is in local keys
reported_local_email=$(get_key_email "$reported_pubkey")
if [[ -n "$reported_local_email" ]]; then
    reported_in_uplanet=true
    reported_g1pubnostr="$reported_local_email"
fi

# If not found locally, check swarm
if [[ "$reported_in_uplanet" == "false" ]]; then
    reported_swarm_email=$(search_swarm_for_pubkey "$reported_pubkey")
    if [[ -n "$reported_swarm_email" ]]; then
        reported_in_uplanet=true
        reported_g1pubnostr="$reported_swarm_email"
    fi
fi

# If still not found, check amisOfAmis.txt
if [[ "$reported_in_uplanet" == "false" ]]; then
    if check_amis_of_amis "$reported_pubkey"; then
        reported_in_uplanet=true
        reported_g1pubnostr="amisOfAmis"
    fi
fi

# Log the report details
if [[ "$reported_in_uplanet" == "true" ]]; then
    log_report "REPORT: ${pubkey:0:8}... reported ${reported_pubkey:0:8}... (UPlanet member: $reported_g1pubnostr)"
    log_report "REPORT: Type: $report_type"
    if [[ -n "$reported_event_id" ]]; then
        log_report "REPORT: Event being reported: ${reported_event_id:0:8}..."
    fi
    if [[ -n "$reason" ]]; then
        log_report "REPORT: Reason: $reason"
    fi
    if [[ -n "$content" ]]; then
        log_report "REPORT: Additional details: $content"
    fi
else
    log_report "REPORT: ${pubkey:0:8}... reported external user ${reported_pubkey:0:8}..."
    log_report "REPORT: Type: $report_type"
    if [[ -n "$reason" ]]; then
        log_report "REPORT: Reason: $reason"
    fi
fi

# Check for specific report types that might require immediate action
case "$report_type" in
    "spam"|"impersonation"|"harassment"|"illegal")
        log_report "URGENT: High-priority report type detected: $report_type"
        # Could trigger additional moderation actions here
        ;;
    "fake"|"scam"|"phishing")
        log_report "WARNING: Security-related report type: $report_type"
        ;;
    *)
        log_report "INFO: Standard report type: $report_type"
        ;;
esac

echo ">>> (1984) REPORT: ${pubkey:0:8}... → ${reported_pubkey:0:8}... ($report_type)"

exit 0 