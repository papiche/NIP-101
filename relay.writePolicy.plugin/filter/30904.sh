#!/bin/bash
################################################################################
# filter/30904.sh - Crowdfunding Campaign Events (NIP-75 Extension)
#
# This script handles Nostr events of kind:30904 (crowdfunding campaigns)
# These are addressable events that define multi-currency crowdfunding goals
# for property acquisition (forest gardens, shared spaces, etc.)
#
# FEATURES:
# - Validates campaign structure
# - Registers Bien hex keys to amisOfAmis for payment authorization
# - Creates/updates local crowdfunding project files
# - Syncs campaign state with local database
#
# REQUIRED TAGS:
# - ["d", "crowdfund-{lat}-{lon}-{slug}"] - Unique identifier
# - ["title", "Campaign Name"] - Campaign title
# - ["t", "crowdfunding"] - Type marker
# - ["g", "{lat},{lon}"] - Geographic coordinates
# - ["project-id", "CF-YYYYMMDD-XXXX"] - Project identifier
#
# OPTIONAL TAGS:
# - ["owner", pubkey, mode, amount, currency] - Owner details
# - ["goal", type, target, collected] - Funding goals
# - ["wallet", type, g1pubkey] - Wallet destinations
# - ["status", "crowdfunding"|"funded"|"completed"] - Campaign status
#
################################################################################

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Log file for crowdfunding events
LOG_FILE="$HOME/.zen/tmp/nostr_crowdfunding.log"
ensure_log_dir "$LOG_FILE"

# Logging function
log_cf() {
    log_with_timestamp "$LOG_FILE" "$1"
}

################################################################################
# EXTRACT EVENT DATA
################################################################################

event_json="$1"
extract_event_data "$event_json"

# Extract required tags
extract_tags "$event_json" "d" "title" "project-id" "g" "status"
campaign_d="$d"
campaign_title="$title"
project_id="${project_id:-}"
geo_coords="$g"
campaign_status="${status:-draft}"

# Get project-id from d tag if not explicitly set
if [[ -z "$project_id" && -n "$campaign_d" ]]; then
    # Extract project ID from d tag pattern: crowdfund-{lat}-{lon}-{slug}
    # Or use d tag as fallback identifier
    project_id="CF-$(echo "$campaign_d" | md5sum | cut -c1-8 | tr 'a-f' 'A-F')"
fi

################################################################################
# AUTHORIZATION CHECK
################################################################################

# Check if publisher is authorized
local_email=$(get_key_email "$pubkey")

# Allow if:
# 1. Local user (has MULTIPASS)
# 2. Swarm user
# 3. In amisOfAmis
# 4. Is a known Bien pubkey (can self-update)

is_authorized=false

if [[ -n "$local_email" ]]; then
    is_authorized=true
    log_cf "AUTHORIZED: Campaign from local user $local_email"
elif check_amis_of_amis "$pubkey"; then
    is_authorized=true
    log_cf "AUTHORIZED: Campaign from amisOfAmis ${pubkey:0:8}..."
else
    # Check if this pubkey is a registered Bien
    bien_project=$(is_crowdfunding_bien "$pubkey")
    if [[ -n "$bien_project" ]]; then
        is_authorized=true
        log_cf "AUTHORIZED: Campaign update from Bien $bien_project"
    fi
fi

if [[ "$is_authorized" == "false" ]]; then
    log_cf "REJECTED: Crowdfunding campaign from unauthorized ${pubkey:0:8}..."
    echo ">>> (30904) REJECTED: Campaign from unauthorized user ${pubkey:0:8}..."
    exit 1
fi

################################################################################
# VALIDATE REQUIRED FIELDS
################################################################################

if [[ -z "$campaign_title" ]]; then
    log_cf "REJECTED: Missing title tag"
    exit 1
fi

# Check for crowdfunding tag
if ! has_tag_value "$event_json" "t" "crowdfunding"; then
    log_cf "REJECTED: Missing ['t', 'crowdfunding'] tag"
    exit 1
fi

################################################################################
# EXTRACT BIEN IDENTITY (if present in content)
################################################################################

# Try to extract bien_identity from content JSON
bien_hex=""
bien_g1pub=""
bien_npub=""

# Check if content is JSON with bien_identity
if echo "$content" | jq -e '.bien_identity' >/dev/null 2>&1; then
    bien_hex=$(echo "$content" | jq -r '.bien_identity.hex // empty')
    bien_g1pub=$(echo "$content" | jq -r '.bien_identity.g1pub // empty')
    bien_npub=$(echo "$content" | jq -r '.bien_identity.npub // empty')
fi

# Also check for i tag with g1pub
g1pub_from_tag=$(get_tag_value "$event_json" "i")
if [[ "$g1pub_from_tag" == g1pub:* ]]; then
    bien_g1pub="${g1pub_from_tag#g1pub:}"
fi

################################################################################
# REGISTER BIEN HEX TO AMISOFAMIS
################################################################################

# If we have a Bien hex key, register it for payment authorization
if [[ -n "$bien_hex" ]]; then
    if add_to_amis_of_amis "$bien_hex" "Crowdfunding Bien: $project_id"; then
        log_cf "REGISTERED: Added Bien $project_id hex ($bien_hex) to amisOfAmis"
    fi
fi

# Also register the event publisher if it's a Bien
if [[ -n "$pubkey" ]]; then
    bien_check=$(is_crowdfunding_bien "$pubkey")
    if [[ -z "$bien_check" && -n "$project_id" ]]; then
        # This might be a new Bien - check if this pubkey matches Bien hex
        if [[ "$pubkey" == "$bien_hex" ]]; then
            add_to_amis_of_amis "$pubkey" "Crowdfunding Bien (self): $project_id"
            log_cf "REGISTERED: Added publisher as Bien hex to amisOfAmis"
        fi
    fi
fi

################################################################################
# SYNC WITH LOCAL PROJECT DATABASE (optional)
################################################################################

# If project_id is provided and we have a local crowdfunding directory, update it
if [[ -n "$project_id" && -d "$CROWDFUNDING_DIR" ]]; then
    project_dir="$CROWDFUNDING_DIR/$project_id"
    
    # Create project directory if it doesn't exist
    if [[ ! -d "$project_dir" ]]; then
        mkdir -p "$project_dir"
        log_cf "CREATED: New project directory for $project_id"
    fi
    
    # Update or create nostr_event.json with the event data
    nostr_event_file="$project_dir/nostr_event.json"
    echo "$event_json" | jq '.event' > "$nostr_event_file"
    
    # If we have bien keys, save them
    if [[ -n "$bien_hex" || -n "$bien_g1pub" ]]; then
        pubkeys_file="$project_dir/bien.pubkeys"
        if [[ ! -f "$pubkeys_file" ]]; then
            cat > "$pubkeys_file" << EOF
# Bien Identity for ${project_id}
# Synced from Nostr event: $(date -u +%Y-%m-%dT%H:%M:%SZ)
BIEN_NPUB=${bien_npub}
BIEN_HEX=${bien_hex}
BIEN_G1PUB=${bien_g1pub}
EOF
            log_cf "SYNCED: Created bien.pubkeys from Nostr event"
        fi
    fi
    
    # Update project status if project.json exists
    project_file="$project_dir/project.json"
    if [[ -f "$project_file" && -n "$campaign_status" ]]; then
        # Update status from Nostr event
        temp_file=$(mktemp)
        jq --arg status "$campaign_status" \
           --arg nostr_event "$event_id" \
           '.status = $status | .last_nostr_event = $nostr_event | .last_sync = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' \
           "$project_file" > "$temp_file" 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            mv "$temp_file" "$project_file"
            log_cf "SYNCED: Updated project status to $campaign_status"
        else
            rm -f "$temp_file"
        fi
    fi
fi

################################################################################
# EXTRACT AND LOG GOALS
################################################################################

# Extract goal information for logging
zen_target=$(echo "$event_json" | jq -r '(.event.tags[] | select(.[0] == "goal" and .[1] == "ZEN_CONVERTIBLE") | .[2]) // "0"')
g1_target=$(echo "$event_json" | jq -r '(.event.tags[] | select(.[0] == "goal" and .[1] == "G1") | .[2]) // "0"')

log_cf "ACCEPTED: Campaign '$campaign_title' (ID: $project_id)"
log_cf "  Status: $campaign_status"
log_cf "  Geo: $geo_coords"
log_cf "  Goals: ZEN=$zen_target, G1=$g1_target"
if [[ -n "$bien_hex" ]]; then
    log_cf "  Bien HEX: ${bien_hex:0:16}..."
fi

################################################################################
# OUTPUT
################################################################################

echo ">>> (30904) CROWDFUND: '${campaign_title}' (${project_id:-$campaign_d}) Status: $campaign_status"

exit 0
