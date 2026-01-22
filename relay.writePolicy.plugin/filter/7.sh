#!/bin/bash
################################################################################
# filter/7.sh - Nostr Kind 7 Reactions Handler (NIP-25 + NIP-75 Extension)
#
# This script handles Nostr events of kind:7 (reactions/likes)
# Extended with UPlanet Crowdfunding support:
#
# FEATURES:
# - Standard LIKE/DISLIKE reactions (NIP-25)
# - +ZEN payments to UPlanet members
# - Crowdfunding contributions (NIP-75 Extension)
# - ASSETS vote system for cooperative governance
# - Automatic Bien wallet authorization
#
# REACTION TYPES:
# 1. Standard LIKE: content="+", "👍", etc. → Payment to author
# 2. Crowdfunding: tag ["t", "crowdfunding"] → Payment to Bien wallet
# 3. Vote ASSETS: tag ["t", "vote-assets"] → Record vote (no payment)
#
# TAGS SUPPORTED:
# - ["e", event_id] - Required: reacted event ID
# - ["p", pubkey] - Author pubkey (payment destination)
# - ["k", kind] - Kind of reacted event
# - ["t", "crowdfunding"] - Crowdfunding contribution marker
# - ["t", "vote-assets"] - ASSETS usage vote marker
# - ["project-id", "CF-XXX"] - Crowdfunding project identifier
# - ["target", "ZEN_CONVERTIBLE"] - Contribution type
#
################################################################################

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr_likes.log"
ensure_log_dir "$LOG_FILE"

# Logging function for reactions
log_like() {
    log_with_timestamp "$LOG_FILE" "$1"
}

################################################################################
# INITIALIZATION
################################################################################

# Sync all Crowdfunding Bien hex keys to amisOfAmis at startup
# This ensures all Biens can receive payments
sync_crowdfunding_biens_to_amis "log_like"

# Extract event data
event_json="$1"
extract_event_data "$event_json"

# Extract standard NIP-25 tags
extract_tags "$event_json" "e" "p" "k"
reacted_event_id="$e"
reacted_author_pubkey="$p"
reacted_event_kind="$k"

# Extract crowdfunding-specific tags
project_id=$(get_tag_value "$event_json" "project-id")
contribution_target=$(get_tag_value "$event_json" "target")

# Check for crowdfunding tag
is_crowdfunding=false
is_vote=false

if has_tag_value "$event_json" "t" "crowdfunding"; then
    is_crowdfunding=true
    # Check if this is a VOTE (contribution with target=VOTE)
    if [[ "$contribution_target" == "VOTE" ]]; then
        is_vote=true
    fi
fi

################################################################################
# AUTHORIZATION CHECK
################################################################################

if ! check_authorization "$pubkey" "log_like"; then
    exit 1
fi

################################################################################
# SELF-LIKE PREVENTION
################################################################################

if [[ -n "$reacted_author_pubkey" && "$pubkey" == "$reacted_author_pubkey" ]]; then
    log_like "REJECTED: Self-like detected - source ${pubkey:0:8}... cannot like their own event ${reacted_event_id:0:8}..."
    exit 1
fi

################################################################################
# PARSE ZEN AMOUNT
################################################################################

ZEN_AMOUNT=$(parse_zen_amount "$content")

################################################################################
# DETERMINE REACTION TYPE AND PROCESS
################################################################################

case "$content" in
    ""|"+"|"👍"|"❤️"|"♥️"|"♥"|"+[0-9]"*|"+[0-9][0-9]"*|"+[0-9][0-9][0-9]"*)
        
        #=======================================================================
        # CROWDFUNDING CONTRIBUTION OR VOTE (Payment to Bien wallet)
        # Votes are contributions with target=VOTE
        # They send ZEN AND record the vote
        #=======================================================================
        if [[ "$is_crowdfunding" == "true" ]]; then
            # Determine reaction type (vote or contribution)
            if [[ "$is_vote" == "true" ]]; then
                reaction_type="VOTE (${ZEN_AMOUNT}Ẑ)"
            else
                reaction_type="CROWDFUNDING (${ZEN_AMOUNT}Ẑ)"
            fi
            
            # Determine target Bien
            BIEN_G1PUB=""
            BIEN_PROJECT_ID=""
            
            # Method 1: Use project-id tag if provided
            if [[ -n "$project_id" ]]; then
                BIEN_PROJECT_ID="$project_id"
                wallet_info=$(get_bien_wallet_info "$project_id")
                if [[ -n "$wallet_info" ]]; then
                    BIEN_G1PUB=$(echo "$wallet_info" | cut -d'|' -f2)
                fi
            fi
            
            # Method 2: Check if reacted_author_pubkey is a Bien
            if [[ -z "$BIEN_G1PUB" && -n "$reacted_author_pubkey" ]]; then
                BIEN_PROJECT_ID=$(is_crowdfunding_bien "$reacted_author_pubkey")
                if [[ -n "$BIEN_PROJECT_ID" ]]; then
                    wallet_info=$(get_bien_wallet_info "$BIEN_PROJECT_ID")
                    if [[ -n "$wallet_info" ]]; then
                        BIEN_G1PUB=$(echo "$wallet_info" | cut -d'|' -f2)
                    fi
                fi
            fi
            
            if [[ -z "$BIEN_G1PUB" ]]; then
                log_like "CROWDFUNDING: Cannot find Bien wallet for project ${project_id:-UNKNOWN}"
                # Fall back to standard like if no Bien found
                is_crowdfunding=false
            else
                log_like "CROWDFUNDING: $reaction_type from ${pubkey:0:8}... to project $BIEN_PROJECT_ID (Bien wallet: ${BIEN_G1PUB:0:8}...)"
                
                # Only LOCAL users can send payments
                if [[ "$SOURCE" == "local" && "$EMAIL" != "amisOfAmis" ]]; then
                    PAYMENT_WALLET=""
                    PAYMENT_METHOD=""
                    
                    if [[ "$EMAIL" == "CAPTAIN" ]]; then
                        CAPTAIN_WALLET_DIR="$KEY_DIR/$CAPTAINEMAIL"
                        if [[ -s "${CAPTAIN_WALLET_DIR}/.secret.dunikey" ]]; then
                            PAYMENT_WALLET="${CAPTAIN_WALLET_DIR}/.secret.dunikey"
                            PAYMENT_METHOD="MULTIPASS:($CAPTAINEMAIL)"
                        else
                            log_like "CROWDFUNDING: Cannot send - missing wallet for CAPTAIN"
                        fi
                    else
                        PLAYER_DIR="$KEY_DIR/$EMAIL"
                        if [[ -s "${PLAYER_DIR}/.secret.dunikey" ]]; then
                            PAYMENT_WALLET="${PLAYER_DIR}/.secret.dunikey"
                            PAYMENT_METHOD="MULTIPASS:($EMAIL)"
                        else
                            log_like "CROWDFUNDING: Cannot send - missing wallet for ${EMAIL}"
                        fi
                    fi
                    
                    if [[ -n "$PAYMENT_WALLET" ]]; then
                        # Convert ZEN to G1
                        AMOUNT=$(echo "scale=2; $ZEN_AMOUNT * 0.1" | bc -l)
                        if (( $(echo "$AMOUNT < 1" | bc -l) )); then
                            AMOUNT="0$AMOUNT"
                        fi
                        
                        # Comment includes VOTE marker if it's a vote
                        if [[ "$is_vote" == "true" ]]; then
                            COMMENT="CF:${BIEN_PROJECT_ID}:VOTE:${ZEN_AMOUNT}:${pubkey:0:8}"
                        else
                            COMMENT="CF:${BIEN_PROJECT_ID}:ZEN:${ZEN_AMOUNT}:${pubkey:0:8}"
                        fi
                        
                        log_like "CROWDFUNDING: Sending ${ZEN_AMOUNT}Ẑ ($AMOUNT G1) to Bien $BIEN_PROJECT_ID via $PAYMENT_METHOD"
                        
                        ~/.zen/Astroport.ONE/tools/PAYforSURE.sh "$PAYMENT_WALLET" "$AMOUNT" "$BIEN_G1PUB" "$COMMENT" >> "$LOG_FILE" 2>&1
                        PAYMENT_RESULT=$?
                        
                        if [[ $PAYMENT_RESULT -eq 0 ]]; then
                            log_like "CROWDFUNDING: ✅ Successfully sent ${ZEN_AMOUNT}Ẑ to Bien $BIEN_PROJECT_ID"
                            
                            # Record contribution in project
                            record_crowdfunding_contribution "$BIEN_PROJECT_ID" "$pubkey" "$ZEN_AMOUNT" "ZEN" "$event_id"
                            
                            # If this is a vote, also record the vote
                            if [[ "$is_vote" == "true" ]]; then
                                log_like "VOTE: Recording vote from ${pubkey:0:8}... for project $BIEN_PROJECT_ID"
                                record_assets_vote "$BIEN_PROJECT_ID" "$pubkey" "$ZEN_AMOUNT" "$event_id"
                                
                                # Check if vote threshold reached
                                if check_vote_threshold "$BIEN_PROJECT_ID"; then
                                    log_like "VOTE: 🎉 Vote threshold reached for project $BIEN_PROJECT_ID - APPROVED!"
                                fi
                            fi
                        else
                            log_like "CROWDFUNDING: ❌ Payment failed (exit code: $PAYMENT_RESULT)"
                        fi
                    fi
                else
                    if [[ "$EMAIL" == "amisOfAmis" ]]; then
                        log_like "CROWDFUNDING: amisOfAmis cannot send payments"
                    else
                        log_like "CROWDFUNDING: Only local users can send (SOURCE: $SOURCE)"
                    fi
                fi
            fi
        fi
        
        #=======================================================================
        # STANDARD LIKE (Payment to author) - when not a crowdfunding contribution
        #=======================================================================
        if [[ "$is_crowdfunding" == "false" ]]; then
            reaction_type="LIKE (${ZEN_AMOUNT}Ẑ)"
            
            # Check if destination is a Bien (direct reaction to Bien profile)
            BIEN_PROJECT_ID=$(is_crowdfunding_bien "$reacted_author_pubkey")
            if [[ -n "$BIEN_PROJECT_ID" ]]; then
                # Redirect to Bien wallet instead of author
                log_like "REACTION: Standard LIKE to Bien $BIEN_PROJECT_ID - redirecting to Bien wallet"
                
                wallet_info=$(get_bien_wallet_info "$BIEN_PROJECT_ID")
                if [[ -n "$wallet_info" ]]; then
                    G1PUBNOSTR=$(echo "$wallet_info" | cut -d'|' -f2)
                fi
            else
                # Search if reacted_author_pubkey is part of UPlanet
                G1PUBNOSTR=$(~/.zen/Astroport.ONE/tools/search_for_this_hex_in_uplanet.sh "$reacted_author_pubkey" 2>/dev/null)
            fi
            
            if [[ $? -eq 0 && -n "$G1PUBNOSTR" ]]; then
                log_like "REACTION: $reaction_type from ${pubkey:0:8}... to ${reacted_author_pubkey:0:8}... (G1: ${G1PUBNOSTR:0:8}...)"

                # Only LOCAL users can send payments
                if [[ "$SOURCE" == "local" && "$EMAIL" != "amisOfAmis" ]]; then
                    PAYMENT_WALLET=""
                    PAYMENT_METHOD=""
                    
                    if [[ "$EMAIL" == "CAPTAIN" ]]; then
                        CAPTAIN_WALLET_DIR="$KEY_DIR/$CAPTAINEMAIL"
                        if [[ -s "${CAPTAIN_WALLET_DIR}/.secret.dunikey" ]]; then
                            PAYMENT_WALLET="${CAPTAIN_WALLET_DIR}/.secret.dunikey"
                            PAYMENT_METHOD="MULTIPASS:($CAPTAINEMAIL)"
                            log_like "PAYMENT: CAPTAIN using wallet from $CAPTAINEMAIL"
                        else
                            log_like "PAYMENT: Cannot send - missing wallet for CAPTAIN"
                        fi
                    else
                        PLAYER_DIR="$KEY_DIR/$EMAIL"
                        if [[ -s "${PLAYER_DIR}/.secret.dunikey" ]]; then
                            PAYMENT_WALLET="${PLAYER_DIR}/.secret.dunikey"
                            PAYMENT_METHOD="MULTIPASS:($EMAIL)"
                        else
                            log_like "PAYMENT: Cannot send - missing wallet for ${EMAIL}"
                        fi
                    fi
                    
                    if [[ -n "$PAYMENT_WALLET" ]]; then
                        AMOUNT=$(echo "scale=2; $ZEN_AMOUNT * 0.1" | bc -l)
                        if (( $(echo "$AMOUNT < 1" | bc -l) )); then
                            AMOUNT="0$AMOUNT"
                        fi
                        COMMENT="UPLANET:${UPLANETG1PUB:0:8}:$EMAIL:LIKE:${ZEN_AMOUNT}Z:${reacted_event_id}"
                        
                        log_like "PAYMENT: Sending ${ZEN_AMOUNT}Ẑ ($AMOUNT G1) to $G1PUBNOSTR via $PAYMENT_METHOD"
                        
                        ~/.zen/Astroport.ONE/tools/PAYforSURE.sh "$PAYMENT_WALLET" "$AMOUNT" "$G1PUBNOSTR" "$COMMENT" >> "$LOG_FILE" 2>&1
                        PAYMENT_RESULT=$?
                        
                        if [[ $PAYMENT_RESULT -eq 0 ]]; then
                            log_like "PAYMENT: ✅ Successfully sent ${ZEN_AMOUNT}Ẑ to $G1PUBNOSTR"
                        else
                            log_like "PAYMENT: ❌ Failed (exit code: $PAYMENT_RESULT)"
                        fi
                    fi
                else
                    if [[ "$EMAIL" == "amisOfAmis" ]]; then
                        log_like "PAYMENT: amisOfAmis can only RECEIVE payments"
                    else
                        log_like "PAYMENT: Only local users can send (SOURCE: $SOURCE)"
                    fi
                fi
            else
                log_like "REACTION: $reaction_type from ${pubkey:0:8}... - destination not in UPlanet"
            fi
        fi
        ;;
        
    #===========================================================================
    # DISLIKE REACTIONS
    #===========================================================================
    "-"|"👎"|"💔")
        reaction_type="DISLIKE"
        log_like "REACTION: DISLIKE from ${pubkey:0:8}... to event ${reacted_event_id:0:8}..."
        ;;
        
    #===========================================================================
    # CUSTOM REACTIONS
    #===========================================================================
    *)
        reaction_type="CUSTOM:$content"
        log_like "REACTION: CUSTOM ($content) from ${pubkey:0:8}... to event ${reacted_event_id:0:8}..."
        ;;
esac

################################################################################
# VALIDATION
################################################################################

# NIP-25 requires 'e' tag, but for crowdfunding contributions, 
# project-id can serve as alternative identifier
if [[ -z "$reacted_event_id" ]]; then
    if [[ "$is_crowdfunding" == "true" ]]; then
        if [[ -z "$project_id" ]]; then
            log_like "REJECTED: Crowdfunding requires either 'e' tag or 'project-id' tag"
            exit 1
        fi
        # Use project-id as event reference for crowdfunding
        reacted_event_id="$project_id"
    else
        log_like "REJECTED: Missing required 'e' tag (reacted event ID)"
        exit 1
    fi
fi

################################################################################
# FINAL LOG AND OUTPUT
################################################################################

log_like "ACCEPTED: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}... (Email: $EMAIL, Source: $SOURCE)"

# Display summary
if [[ "$is_vote" == "true" ]]; then
    echo ">>> (7) VOTE: $reaction_type from ${pubkey:0:8}... for project ${BIEN_PROJECT_ID:-$project_id}"
elif [[ "$is_crowdfunding" == "true" ]]; then
    echo ">>> (7) CROWDFUND: $reaction_type from ${pubkey:0:8}... to project ${BIEN_PROJECT_ID:-$project_id}"
else
    echo ">>> (7) REACTION: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}..."
fi

exit 0
