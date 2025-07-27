#!/bin/bash
# filter/9735.sh (OPTIMIZED)
# This script handles Nostr events of kind:9735 (Zap receipts)

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr_zaps.9735.log"
ensure_log_dir "$LOG_FILE"

# Logging function for zaps
log_zap() {
    log_with_timestamp "$LOG_FILE" "$1"
}

# Extract event data in one optimized call
event_json="$1"
extract_event_data "$event_json"

# Extract specific tags for kind 9735 events
extract_tags "$event_json" "p" "e" "bolt11" "description" "preimage" "amount"
recipient_pubkey="$p"
zapped_event_id="$e"
bolt11_invoice="$bolt11"
description="$description"
preimage="$preimage"
amount="$amount"

# Check authorization using common function
if ! check_authorization "$pubkey" "log_zap"; then
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

# Check if recipient is part of UPlanet using common function
if check_authorization "$recipient_pubkey" "log_zap" 2>/dev/null; then
    recipient_in_uplanet=true
    recipient_email="$EMAIL"
    recipient_source="$SOURCE"
    log_zap "ZAP: ${pubkey:0:8}... zapped ${recipient_pubkey:0:8}... (UPlanet member: $recipient_email from $recipient_source)"
else
    recipient_in_uplanet=false
    log_zap "ZAP: ${pubkey:0:8}... zapped external user ${recipient_pubkey:0:8}..."
fi

# Log zap details
[[ -n "$zapped_event_id" ]] && log_zap "ZAP: Event being zapped: ${zapped_event_id:0:8}..."
[[ -n "$amount" ]] && log_zap "ZAP: Amount: ${amount} millisatoshis"

log_zap "ACCEPTED: Zap from ${pubkey:0:8}... to ${recipient_pubkey:0:8}... (Email: $EMAIL, Source: $SOURCE)"
echo ">>> (9735) ZAP: ${pubkey:0:8}... → ${recipient_pubkey:0:8}... (${amount:-unknown} msat)"

exit 0 