#!/bin/bash
# filter/7.sh (OPTIMIZED)
# This script handles Nostr events of kind:7 (reactions/likes)

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr_likes.log"
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
    ""|"+"|"👍"|"❤️"|"♥️"|"♥")
        reaction_type="LIKE"

        # Search if reacted_author_pubkey is part of UPlanet
        G1PUBNOSTR=$(~/.zen/Astroport.ONE/tools/search_for_this_hex_in_uplanet.sh "$reacted_author_pubkey" 2>/dev/null)
        if [[ $? -eq 0 && -n "$G1PUBNOSTR" ]]; then
            log_like "REACTION: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}... is part of UPlanet (G1PUBNOSTR: ${G1PUBNOSTR:0:8}...)"

            # Only LOCAL users can send payments (amisOfAmis can only RECEIVE payments)
            if [[ "$SOURCE" == "local" && "$EMAIL" != "amisOfAmis" ]]; then
                PAYMENT_WALLET=""
                PAYMENT_METHOD=""
                
                if [[ "$EMAIL" == "CAPTAIN" ]]; then
                    # CAPTAIN uses the wallet in ~/.zen/game/nostr/$CAPTAINEMAIL
                    CAPTAIN_WALLET_DIR="$KEY_DIR/$CAPTAINEMAIL"
                    if [[ -s "${CAPTAIN_WALLET_DIR}/.secret.dunikey" ]]; then
                        PAYMENT_WALLET="${CAPTAIN_WALLET_DIR}/.secret.dunikey"
                        PAYMENT_METHOD="captain_wallet ($CAPTAINEMAIL)"
                        log_like "PAYMENT: CAPTAIN using wallet from $CAPTAINEMAIL"
                    else
                        log_like "PAYMENT: Cannot send payment - missing .secret.dunikey for CAPTAIN in $CAPTAINEMAIL"
                    fi
                else
                    # Regular local user uses their own wallet
                    PLAYER_DIR="$KEY_DIR/$EMAIL"
                    if [[ -s "${PLAYER_DIR}/.secret.dunikey" ]]; then
                        PAYMENT_WALLET="${PLAYER_DIR}/.secret.dunikey"
                        PAYMENT_METHOD="own_wallet ($EMAIL)"
                    else
                        log_like "PAYMENT: Cannot send payment - missing .secret.dunikey for ${EMAIL}"
                    fi
                fi
                
                # Execute payment if wallet is available
                if [[ -n "$PAYMENT_WALLET" ]]; then
                    AMOUNT="0.1"
                    COMMENT="UPLANET:${UPLANETG1PUB:0:8}:$EMAIL:LIKE:${reacted_event_id}"
                    
                    log_like "PAYMENT: Attempting to send $AMOUNT G1 to $G1PUBNOSTR using $PAYMENT_METHOD"
                    
                    ~/.zen/Astroport.ONE/tools/PAYforSURE.sh "$PAYMENT_WALLET" "$AMOUNT" "$G1PUBNOSTR" "$COMMENT"
                    PAYMENT_RESULT=$?
                    
                    if [[ $PAYMENT_RESULT -eq 0 ]]; then
                        log_like "PAYMENT: Successfully sent $AMOUNT G1 to $G1PUBNOSTR for LIKE reaction via $PAYMENT_METHOD"
                    else
                        log_like "PAYMENT: Failed to send $AMOUNT G1 to $G1PUBNOSTR (exit code: $PAYMENT_RESULT) via $PAYMENT_METHOD"
                    fi
                fi
            else
                if [[ "$EMAIL" == "amisOfAmis" ]]; then
                    log_like "PAYMENT: amisOfAmis users can only RECEIVE payments, not send them"
                else
                    log_like "PAYMENT: Only local users can send payments (SOURCE: $SOURCE, EMAIL: $EMAIL)"
                fi
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