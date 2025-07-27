#!/bin/bash
# filter/7.sh (OPTIMIZED)
# This script handles Nostr events of kind:7 (reactions/likes)

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr_likes.7.log"
ensure_log_dir "$LOG_FILE"

# Logging function for likes
log_like() {
    log_with_timestamp "$LOG_FILE" "$1"
}

# Extract event data in one optimized call
event_json="$1"
extract_event_data "$event_json"

# Extract specific tags for kind 7 events
extract_tags "$event_json" "e" "p" "k"
reacted_event_id="$e"
reacted_author_pubkey="$p"
reacted_event_kind="$k"

# Check authorization using common function
if ! check_authorization "$pubkey" "log_like"; then
    exit 1
fi

# Determine reaction type and handle payment logic
case "$content" in
    ""|"+"|"👍"|"❤️"|"♥️")
        reaction_type="LIKE"

        # Search if reacted_author_pubkey is part of UPlanet
        G1PUBNOSTR=$(~/.zen/Astroport.ONE/tools/search_for_this_hex_in_uplanet.sh "$reacted_author_pubkey" 2>/dev/null)
        if [[ $? -eq 0 && -n "$G1PUBNOSTR" ]]; then
            log_like "REACTION: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}... is part of UPlanet (G1PUBNOSTR: ${G1PUBNOSTR:0:8}...)"

            # Find the player directory using optimized approach
            if [[ "$SOURCE" == "local" && "$EMAIL" != "amisOfAmis" ]]; then
                PLAYER_DIR="$KEY_DIR/$EMAIL"
                
                # Check if player has a secret.dunikey
                if [[ -s "${PLAYER_DIR}/.secret.dunikey" ]]; then
                    # Send 0.1 G1 payment
                    AMOUNT="0.1"
                    COMMENT="_like_${reacted_event_id}_from_${pubkey}"
                    
                    log_like "PAYMENT: Attempting to send $AMOUNT G1 to $G1PUBNOSTR using ${PLAYER_DIR}/.secret.dunikey"
                    
                    ~/.zen/Astroport.ONE/tools/PAYforSURE.sh "${PLAYER_DIR}/.secret.dunikey" "$AMOUNT" "$G1PUBNOSTR" "$COMMENT"
                    PAYMENT_RESULT=$?
                    
                    if [[ $PAYMENT_RESULT -eq 0 ]]; then
                        log_like "PAYMENT: Successfully sent $AMOUNT G1 to $G1PUBNOSTR for LIKE reaction"
                    else
                        log_like "PAYMENT: Failed to send $AMOUNT G1 to $G1PUBNOSTR (exit code: $PAYMENT_RESULT)"
                    fi
                else
                    log_like "PAYMENT: Cannot send payment - missing .secret.dunikey for ${EMAIL}"
                fi
            else
                log_like "PAYMENT: Cannot send payment - player not in local keys or is amisOfAmis"
            fi
        fi
        ;;
    "-"|"👎"|"💔")
        reaction_type="DISLIKE"
        ;;
    *)
        reaction_type="CUSTOM:$content"
        ;;
esac

# Validate required tags
if [[ -z "$reacted_event_id" ]]; then
    log_like "REJECTED: Missing required 'e' tag (reacted event ID)"
    exit 1
fi

log_like "ACCEPTED: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}... (Email: $EMAIL, Source: $SOURCE)"
echo ">>> (7) REACTION: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}..."

exit 0 