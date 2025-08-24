#!/bin/bash
# filter/common.sh
# Common functions for Nostr event filtering
# Sourced by all filter scripts to eliminate code duplication

# Source my.sh to get all necessary constants and functions
source "$HOME/.zen/Astroport.ONE/tools/my.sh"

# Global variables
KEY_DIR="$HOME/.zen/game/nostr"
AMISOFAMIS_FILE="${HOME}/.zen/strfry/amisOfAmis.txt"

# Optimized function to extract multiple values from event JSON in one jq call
extract_event_data() {
    local event_json="$1"
    
    # Extract common fields in a single jq call
    eval $(echo "$event_json" | jq -r '
        "event_id=" + .event.id + ";" +
        "pubkey=" + .event.pubkey + ";" +
        "content=" + (.event.content | @sh) + ";" +
        "created_at=" + (.event.created_at | tostring)
    ')
}

# Optimized function to check if a key is authorized and get the associated email
get_key_email() {
    local pubkey="$1"
    
    if cat "$KEY_DIR"/*/HEX 2>/dev/null | grep -q "^$pubkey$"; then
        # Find the specific directory
        local key_dir=$(grep -l "^$pubkey$" "$KEY_DIR"/*/HEX 2>/dev/null | head -1 | xargs dirname)
        if [[ -n "$key_dir" ]]; then
            basename "$key_dir"
            return 0
        fi
    fi
    echo ""
    return 1
}

# Optimized function to search for pubkey in swarm
search_swarm_for_pubkey() {
    local pubkey="$1"
    
    # First, try swarm directories
    if cat ${HOME}/.zen/tmp/swarm/*/TW/*/HEX 2>/dev/null | grep -q "^$pubkey$"; then
        local found_file=$(grep -l "^$pubkey$" ${HOME}/.zen/tmp/swarm/*/TW/*/HEX 2>/dev/null | head -1)
        if [[ -n "$found_file" ]]; then
            basename "$(dirname "$found_file")"
            return 0
        fi
    fi
    
    # If not found in swarm, try local IPFSNODEID
    if cat ${HOME}/.zen/tmp/${IPFSNODEID}/TW/*/HEX 2>/dev/null | grep -q "^$pubkey$"; then
        local found_file=$(grep -l "^$pubkey$" ${HOME}/.zen/tmp/${IPFSNODEID}/TW/*/HEX 2>/dev/null | head -1)
        if [[ -n "$found_file" ]]; then
            basename "$(dirname "$found_file")"
            return 0
        fi
    fi
    
    echo ""
    return 1
}

# Optimized function to check amisOfAmis.txt
check_amis_of_amis() {
    local pubkey="$1"
    
    [[ -f "$AMISOFAMIS_FILE" && -n "$pubkey" ]] && grep -q "^$pubkey$" "$AMISOFAMIS_FILE"
}

# Main authorization function - consolidates all checks
check_authorization() {
    local pubkey="$1"
    local log_func="$2"  # Function name for logging
    
    local authorized=false
    local email=""
    local source=""
    
    # Check local HEX keys first
    local local_email=$(get_key_email "$pubkey")
    if [[ -n "$local_email" ]]; then
        authorized=true
        email="$local_email"
        source="local"
        $log_func "AUTHORIZED: Pubkey ${pubkey:0:8}... found in local keys with email: $email"
    fi
    
    # If not found locally, check swarm
    if [[ "$authorized" == "false" ]]; then
        local swarm_email=$(search_swarm_for_pubkey "$pubkey")
        if [[ -n "$swarm_email" ]]; then
            authorized=true
            email="$swarm_email"
            source="swarm"
            $log_func "AUTHORIZED: Pubkey ${pubkey:0:8}... found in swarm with email: $email"
        fi
    fi
    
    # If still not found, check amisOfAmis.txt
    if [[ "$authorized" == "false" ]]; then
        if check_amis_of_amis "$pubkey"; then
            authorized=true
            email="amisOfAmis"
            source="amisOfAmis"
            $log_func "AUTHORIZED: Pubkey ${pubkey:0:8}... found in amisOfAmis.txt"
        fi
    fi
    
    # Return results via global variables
    AUTHORIZED="$authorized"
    EMAIL="$email"
    SOURCE="$source"
    
    if [[ "$authorized" == "false" ]]; then
        $log_func "REJECTED: Pubkey ${pubkey:0:8}... not found in local keys, swarm, or amisOfAmis"
        return 1
    fi
    
    return 0
}

# Function to extract specific tags from event JSON
extract_tags() {
    local event_json="$1"
    shift  # Remove first argument
    local tag_names=("$@")  # Remaining arguments are tag names
    
    # Build jq query dynamically
    local jq_query=""
    for tag_name in "${tag_names[@]}"; do
        if [[ -n "$jq_query" ]]; then
            jq_query="$jq_query + \";\" + "
        fi
        jq_query="$jq_query\"${tag_name}=\" + ((.event.tags[] | select(.[0] == \"${tag_name}\") | .[1]) // \"\")"
    done
    
    # Execute single jq call and eval the results
    eval $(echo "$event_json" | jq -r "$jq_query")
}

# Utility function for logging with timestamp
log_with_timestamp() {
    local log_file="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
}

# Function to create log directory if it doesn't exist
ensure_log_dir() {
    local log_file="$1"
    mkdir -p "$(dirname "$log_file")"
}

# Function to parse ẐEN amount from reaction content
parse_zen_amount() {
    local content="$1"
    local amount="1"  # Default amount for simple "+" or like emojis
    
    case "$content" in
        ""|"+"|"👍"|"❤️"|"♥️"|"♥")
            amount="1"
            ;;
        "+[0-9]"*|"+[0-9][0-9]"*|"+[0-9][0-9][0-9]"*)
            # Extract number after +
            amount=$(echo "$content" | sed 's/^+\([0-9]\+\).*/\1/')
            # Validate it's a reasonable number (1-1000 ẐEN max)
            if [[ "$amount" -gt 1000 ]]; then
                amount="1000"
            elif [[ "$amount" -lt 1 ]]; then
                amount="1"
            fi
            ;;
        *)
            # For other content, default to 1
            amount="1"
            ;;
    esac
    
    echo "$amount"
} 