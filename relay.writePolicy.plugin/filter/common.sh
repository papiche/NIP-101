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
# Uses a single grep call to find both existence and location
get_key_email() {
    local pubkey="$1"
    
    # Single grep call that finds the file containing the pubkey and extracts directory in one pass
    local found_file=$(grep -l "^$pubkey$" "$KEY_DIR"/*/HEX 2>/dev/null | head -1)
    if [[ -n "$found_file" ]]; then
        basename "$(dirname "$found_file")"
        return 0
    fi
    echo ""
    return 1
}

# Optimized function to search for pubkey in swarm
# Uses single grep call instead of cat|grep then grep -l
search_swarm_for_pubkey() {
    local pubkey="$1"
    
    # First, try swarm directories - single grep call to find file directly
    local found_file=$(grep -l "^$pubkey$" ${HOME}/.zen/tmp/swarm/*/TW/*/HEX 2>/dev/null | head -1)
    if [[ -n "$found_file" ]]; then
        basename "$(dirname "$found_file")"
        return 0
    fi
    
    # If not found in swarm, try local IPFSNODEID - single grep call
    if [[ -n "$IPFSNODEID" ]]; then
        found_file=$(grep -l "^$pubkey$" ${HOME}/.zen/tmp/${IPFSNODEID}/TW/*/HEX 2>/dev/null | head -1)
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
        jq_query="$jq_query\"${tag_name}=\" + (((.event.tags[] | select(.[0] == \"${tag_name}\") | .[1]) // \"\") | @sh)"
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

################################################################################
# CROWDFUNDING SUPPORT FUNCTIONS (NIP-75 Extension)
################################################################################

CROWDFUNDING_DIR="$HOME/.zen/game/crowdfunding"

# Extract all values of a specific tag type (e.g., all "t" tags)
# Returns newline-separated list
extract_all_tags_of_type() {
    local event_json="$1"
    local tag_type="$2"
    
    echo "$event_json" | jq -r --arg type "$tag_type" '.event.tags[] | select(.[0] == $type) | .[1]' 2>/dev/null
}

# Check if event has a specific tag value
# Usage: has_tag_value "$event_json" "t" "crowdfunding"
has_tag_value() {
    local event_json="$1"
    local tag_type="$2"
    local tag_value="$3"
    
    echo "$event_json" | jq -e --arg type "$tag_type" --arg value "$tag_value" \
        '.event.tags[] | select(.[0] == $type and .[1] == $value)' >/dev/null 2>&1
}

# Get specific tag value by type
# Usage: get_tag_value "$event_json" "project-id"
get_tag_value() {
    local event_json="$1"
    local tag_type="$2"
    
    echo "$event_json" | jq -r --arg type "$tag_type" '(.event.tags[] | select(.[0] == $type) | .[1]) // ""' 2>/dev/null | head -1
}

# Check if pubkey is a Bien (crowdfunding project)
# Returns: project_id if found, empty string otherwise
is_crowdfunding_bien() {
    local hex_pubkey="$1"
    
    if [[ ! -d "$CROWDFUNDING_DIR" ]]; then
        echo ""
        return 1
    fi
    
    # Search for this hex in all project's bien.pubkeys files
    for project_dir in "$CROWDFUNDING_DIR"/*/; do
        if [[ -d "$project_dir" ]]; then
            local pubkeys_file="$project_dir/bien.pubkeys"
            if [[ -f "$pubkeys_file" ]]; then
                if grep -q "^BIEN_HEX=$hex_pubkey$" "$pubkeys_file" 2>/dev/null; then
                    # Return project ID (directory name)
                    basename "$project_dir"
                    return 0
                fi
            fi
        fi
    done
    
    echo ""
    return 1
}

# Get Bien wallet info by project ID
# Returns: BIEN_HEX|BIEN_G1PUB|BIEN_NPUB
get_bien_wallet_info() {
    local project_id="$1"
    local project_dir="$CROWDFUNDING_DIR/$project_id"
    local pubkeys_file="$project_dir/bien.pubkeys"
    
    if [[ -f "$pubkeys_file" ]]; then
        source "$pubkeys_file"
        echo "${BIEN_HEX}|${BIEN_G1PUB}|${BIEN_NPUB}"
        return 0
    fi
    
    echo ""
    return 1
}

# Get project info from project.json
# Returns: name|status|zen_target|zen_collected|vote_active
get_project_info() {
    local project_id="$1"
    local project_file="$CROWDFUNDING_DIR/$project_id/project.json"
    
    if [[ -f "$project_file" ]]; then
        jq -r '[.name, .status, (.totals.zen_convertible_target // 0), (.totals.zen_convertible_collected // 0), (.vote.assets_vote_active // false)] | join("|")' "$project_file" 2>/dev/null
        return 0
    fi
    
    echo ""
    return 1
}

# Add hex pubkey to amisOfAmis.txt for authorization
add_to_amis_of_amis() {
    local hex_pubkey="$1"
    local comment="$2"
    
    if [[ -z "$hex_pubkey" ]]; then
        return 1
    fi
    
    # Ensure directory exists
    mkdir -p "$(dirname "$AMISOFAMIS_FILE")"
    
    # Check if already present
    if ! grep -q "^$hex_pubkey$" "$AMISOFAMIS_FILE" 2>/dev/null; then
        # Add with optional comment
        if [[ -n "$comment" ]]; then
            echo "# $comment" >> "$AMISOFAMIS_FILE"
        fi
        echo "$hex_pubkey" >> "$AMISOFAMIS_FILE"
        return 0
    fi
    
    return 1  # Already present
}

# Sync all Bien hex keys to amisOfAmis.txt
sync_crowdfunding_biens_to_amis() {
    local log_func="$1"
    local added_count=0
    
    if [[ ! -d "$CROWDFUNDING_DIR" ]]; then
        return 0
    fi
    
    for project_dir in "$CROWDFUNDING_DIR"/*/; do
        if [[ -d "$project_dir" ]]; then
            local pubkeys_file="$project_dir/bien.pubkeys"
            local project_id=$(basename "$project_dir")
            
            if [[ -f "$pubkeys_file" ]]; then
                source "$pubkeys_file"
                if [[ -n "$BIEN_HEX" ]]; then
                    if add_to_amis_of_amis "$BIEN_HEX" "Crowdfunding Bien: $project_id"; then
                        added_count=$((added_count + 1))
                        [[ -n "$log_func" ]] && $log_func "CROWDFUNDING: Added Bien $project_id hex to amisOfAmis"
                    fi
                fi
            fi
        fi
    done
    
    return $added_count
}

# Record contribution to crowdfunding project
# Updates project.json with new contribution
record_crowdfunding_contribution() {
    local project_id="$1"
    local contributor_hex="$2"
    local amount="$3"
    local currency="${4:-ZEN}"
    local tx_event_id="$5"
    
    local project_file="$CROWDFUNDING_DIR/$project_id/project.json"
    
    if [[ ! -f "$project_file" ]]; then
        return 1
    fi
    
    # Create contribution record
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local temp_file=$(mktemp)
    
    jq --arg hex "$contributor_hex" \
       --argjson amount "$amount" \
       --arg currency "$currency" \
       --arg ts "$timestamp" \
       --arg event_id "$tx_event_id" \
       '.contributions += [{
           "contributor_hex": $hex,
           "amount": $amount,
           "currency": $currency,
           "timestamp": $ts,
           "event_id": $event_id
       }] | .totals.zen_convertible_collected += $amount' \
       "$project_file" > "$temp_file" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$project_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Record vote for ASSETS usage
record_assets_vote() {
    local project_id="$1"
    local voter_hex="$2"
    local vote_amount="$3"
    local vote_event_id="$4"
    
    local project_file="$CROWDFUNDING_DIR/$project_id/project.json"
    
    if [[ ! -f "$project_file" ]]; then
        return 1
    fi
    
    # Check if vote is active
    local vote_active=$(jq -r '.vote.assets_vote_active // false' "$project_file")
    if [[ "$vote_active" != "true" ]]; then
        return 2  # Vote not active
    fi
    
    # Check if already voted
    local already_voted=$(jq -r --arg hex "$voter_hex" '.vote.voters[] | select(. == $hex)' "$project_file" 2>/dev/null)
    if [[ -n "$already_voted" ]]; then
        return 3  # Already voted
    fi
    
    # Record vote
    local temp_file=$(mktemp)
    jq --arg hex "$voter_hex" \
       --argjson amount "$vote_amount" \
       --arg event_id "$vote_event_id" \
       '.vote.voters += [$hex] |
        .vote.voters_count = (.vote.voters | length) |
        .vote.votes_zen_total += $amount |
        .vote.vote_events += [{hex: $hex, amount: $amount, event_id: $event_id}]' \
       "$project_file" > "$temp_file" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$project_file"
        
        # Check if vote threshold reached
        check_vote_threshold "$project_id"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Check if vote threshold is reached and update status
check_vote_threshold() {
    local project_id="$1"
    local project_file="$CROWDFUNDING_DIR/$project_id/project.json"
    
    if [[ ! -f "$project_file" ]]; then
        return 1
    fi
    
    local votes_total=$(jq -r '.vote.votes_zen_total // 0' "$project_file")
    local voters_count=$(jq -r '.vote.voters_count // 0' "$project_file")
    local threshold=$(jq -r '.vote.vote_threshold // 100' "$project_file")
    local quorum=$(jq -r '.vote.vote_quorum // 10' "$project_file")
    
    # Check both conditions
    if [[ $(echo "$votes_total >= $threshold" | bc -l) -eq 1 ]] && \
       [[ $(echo "$voters_count >= $quorum" | bc -l) -eq 1 ]]; then
        
        # Update vote status to approved
        local temp_file=$(mktemp)
        jq '.vote.vote_status = "approved" | 
            .vote.approved_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'" | 
            .status = "funded"' "$project_file" > "$temp_file"
        mv "$temp_file" "$project_file"
        
        return 0  # Vote approved
    fi
    
    return 1  # Vote not yet approved
}

# Search for Bien G1PUB by hex (extends search_for_this_hex_in_uplanet.sh)
search_bien_g1pub() {
    local hex_pubkey="$1"
    
    # First check if this is a crowdfunding Bien
    local project_id=$(is_crowdfunding_bien "$hex_pubkey")
    if [[ -n "$project_id" ]]; then
        local wallet_info=$(get_bien_wallet_info "$project_id")
        if [[ -n "$wallet_info" ]]; then
            # Return G1PUB (second field)
            echo "$wallet_info" | cut -d'|' -f2
            return 0
        fi
    fi
    
    # Fall back to standard search
    return 1
} 