#!/bin/bash
# Astroport constellation backfill script
# This script requests and copies messages from the current day to ensure complete synchronization

## SET ASTROPORT ENVIRONNEMENT
[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "STRFRY CONSTELLATION BACKFILL NEEDS ~/.zen/Astroport.ONE" \
    && exit 1

source ~/.zen/Astroport.ONE/tools/my.sh

# Configuration
ROUTER_CONFIG="$HOME/.zen/strfry/strfry-router.conf"
BACKFILL_LOG="$HOME/.zen/strfry/constellation-backfill.log"
BACKFILL_PID="$HOME/.zen/strfry/constellation-backfill.pid"

# Parse command line arguments
DRYRUN=false
DAYS_BACK=1
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --DRYRUN)
            DRYRUN=true
            shift
            ;;
        --days)
            DAYS_BACK="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--DRYRUN] [--days N] [--verbose|-v] [--show-hex] [--stats]"
            echo ""
            echo "Options:"
            echo "  --DRYRUN     Show what would be done without executing"
            echo "  --days N     Backfill N days back (default: 1)"
            echo "  --verbose    Show detailed output"
            echo "  --show-hex   Display all HEX pubkeys found in constellation"
            echo "  --stats      Show database statistics and monitoring info"
            echo "  --help       Show this help message"
            exit 0
            ;;
        --show-hex)
            echo "🔍 Constellation HEX Pubkeys:"
            echo "=============================="
            
            # Use the enhanced function to get all HEX pubkeys
            hex_pubkeys_output=$(get_constellation_hex_pubkeys 2>&1)
            if [[ -n "$hex_pubkeys_output" ]]; then
                # Convert output to array
                mapfile -t hex_pubkeys <<< "$hex_pubkeys_output"
                
                if [[ ${#hex_pubkeys[@]} -gt 0 ]]; then
                    echo "Found ${#hex_pubkeys[@]} HEX pubkeys:"
                    for pubkey in "${hex_pubkeys[@]}"; do
                        echo "  - ${pubkey:0:8}...${pubkey: -8}"
                    done
                else
                    echo "No HEX pubkeys found"
                fi
            else
                echo "No HEX pubkeys found"
            fi
            exit 0
            ;;
        --stats)
            echo "📊 Constellation Database Statistics:"
            echo "===================================="
            
            # Get current event count directly
            db_path="$HOME/.zen/strfry/strfry-db/data.mdb"
            if [[ -f "$db_path" ]]; then
                cd "$HOME/.zen/strfry"
                current_count=$(./strfry scan --count '{}' 2>/dev/null | tail -1 | tr -d '[:space:]')
                echo "Current events in database: $current_count"
                
                # Show database size
                db_size=$(du -h "$db_path" | cut -f1)
                echo "Database size: $db_size"
            else
                echo "Current events in database: Database not found"
            fi
            
            # Get HEX pubkeys count directly
            nostr_dir="$HOME/.zen/game/nostr"
            swarm_dir="$HOME/.zen/tmp/swarm"
            
            hex_count=0
            if [[ -d "$nostr_dir" ]]; then
                hex_count=$(find "$nostr_dir" -name "HEX" -type f | wc -l)
            fi
            
            if [[ -d "$swarm_dir" ]]; then
                amis_count=$(find "$swarm_dir" -name "amisOfAmis.txt" -type f | wc -l)
                echo "HEX files found: $hex_count"
                echo "amisOfAmis.txt files found: $amis_count"
            fi
            
            echo "Total HEX pubkeys monitored: $hex_count"
            
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$VERBOSE" == "true" || "$level" == "ERROR" || "$level" == "WARN" ]]; then
        echo "[$timestamp] [$level] $message"
    fi
    
    # Always log to file
    echo "[$timestamp] [$level] $message" >> "$BACKFILL_LOG"
}

# Function to get all HEX pubkeys from nostr directory and amisOfAmis.txt files
get_constellation_hex_pubkeys() {
    local hex_pubkeys=()
    local nostr_dir="$HOME/.zen/game/nostr"
    local swarm_dir="$HOME/.zen/tmp/swarm"
    
    # First, get HEX pubkeys from nostr directory
    if [[ -d "$nostr_dir" ]]; then
        echo "INFO: Scanning ~/.zen/game/nostr/*/HEX for constellation members..." >&2
        while IFS= read -r -d '' hex_file; do
            if [[ -f "$hex_file" ]]; then
                local pubkey=$(cat "$hex_file" 2>/dev/null | tr -d '[:space:]')
                if [[ -n "$pubkey" && ${#pubkey} -eq 64 ]]; then
                    hex_pubkeys+=("$pubkey")
                    echo "DEBUG: Found HEX pubkey: ${pubkey:0:8}..." >&2
                fi
            fi
        done < <(find "$nostr_dir" -name "HEX" -type f -print0)
    else
        echo "WARN: Nostr directory not found: $nostr_dir" >&2
    fi
    
    # Then, get HEX pubkeys from amisOfAmis.txt files in swarm
    if [[ -d "$swarm_dir" ]]; then
        echo "INFO: Scanning ~/.zen/tmp/swarm/*/amisOfAmis.txt for extended network..." >&2
        while IFS= read -r -d '' amis_file; do
            if [[ -f "$amis_file" ]]; then
                local node_dir=$(dirname "$amis_file")
                local node_id=$(basename "$node_dir")
                echo "DEBUG: Processing amisOfAmis.txt from node: $node_id" >&2
                
                # Read each line from amisOfAmis.txt
                while IFS= read -r line; do
                    local pubkey=$(echo "$line" | tr -d '[:space:]')
                    if [[ -n "$pubkey" && ${#pubkey} -eq 64 ]]; then
                        hex_pubkeys+=("$pubkey")
                        echo "DEBUG: Found amisOfAmis pubkey: ${pubkey:0:8}..." >&2
                    fi
                done < "$amis_file"
            fi
        done < <(find "$swarm_dir" -name "amisOfAmis.txt" -type f -print0)
    else
        echo "WARN: Swarm directory not found: $swarm_dir" >&2
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${hex_pubkeys[@]}" | sort -u
}

# Function to get constellation peers from router config
get_constellation_peers() {
    local peers=()
    
    if [[ ! -f "$ROUTER_CONFIG" ]]; then
        log "ERROR" "Router configuration not found: $ROUTER_CONFIG"
        return 1
    fi
    
    # Extract peer URLs from router config
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*\"([^\"]+)\" ]]; then
            local peer="${BASH_REMATCH[1]}"
            # Filter out non-peer entries
            if [[ "$peer" != "kinds" && "$peer" != "limit" && "$peer" != "constellation" && "$peer" != "both" ]]; then
                peers+=("$peer")
            fi
        fi
    done < "$ROUTER_CONFIG"
    
    echo "${peers[@]}"
}

# Function to discover constellation peers from IPNS swarm
discover_constellation_peers() {
    local peers=()
    local swarm_dir="$HOME/.zen/tmp/swarm"
    
    if [[ ! -d "$swarm_dir" ]]; then
        log "WARN" "Swarm directory not found: $swarm_dir"
        return 1
    fi
    
    echo "INFO: Scanning IPNS swarm for constellation peers..." >&2
    
    # Find all 12345.json files in swarm directory
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            # Extract myRELAY and ipfsnodeid values from JSON using simple grep
            local relay_url=$(grep '"myRELAY"' "$file" | sed 's/.*"myRELAY"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            local ipfsnodeid=$(grep '"ipfsnodeid"' "$file" | sed 's/.*"ipfsnodeid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            
            if [[ -n "$relay_url" && -n "$ipfsnodeid" ]]; then
                echo "DEBUG: Found relay: $relay_url for node: $ipfsnodeid" >&2
                
                # Check if this is a localhost relay (non-routable)
                if [[ "$relay_url" =~ ws://127\.0\.0\.1:7777 ]]; then
                    # Look for x_strfry.sh in the same directory
                    local x_strfry_script="$swarm_dir/$ipfsnodeid/x_strfry.sh"
                    if [[ -f "$x_strfry_script" ]]; then
                        echo "INFO: Found localhost relay with P2P tunnel: $ipfsnodeid" >&2
                        peers+=("localhost:$ipfsnodeid:$x_strfry_script")
                    else
                        echo "WARN: Localhost relay without P2P tunnel: $ipfsnodeid" >&2
                    fi
                else
                    # External routable relay
                    echo "INFO: Found routable relay: $relay_url" >&2
                    peers+=("routable:$relay_url")
                fi
            else
                echo "DEBUG: Skipping file $file - missing myRELAY or ipfsnodeid" >&2
            fi
        fi
    done < <(find "$swarm_dir" -name "12345.json" -print0)
    
    # Return peers as array
    printf '%s\n' "${peers[@]}"
}

# Function to create P2P tunnel for localhost relay
create_p2p_tunnel() {
    local ipfsnodeid="$1"
    local x_strfry_script="$2"
    
    log "INFO" "Creating P2P tunnel for localhost relay: $ipfsnodeid"
    
    # Make script executable
    chmod +x "$x_strfry_script"
    
    # Execute the tunnel script
    local tunnel_output
    tunnel_output=$(cd "$(dirname "$x_strfry_script")" && "$x_strfry_script" 2>&1)
    local tunnel_exit_code=$?
    
    if [[ $tunnel_exit_code -eq 0 ]]; then
        log "INFO" "P2P tunnel created successfully for $ipfsnodeid"
        log "INFO" "Tunnel output: $tunnel_output"
        return 0
    else
        log "ERROR" "Failed to create P2P tunnel for $ipfsnodeid"
        log "ERROR" "Tunnel output: $tunnel_output"
        return 1
    fi
}

# Function to close P2P tunnel for localhost relay
close_p2p_tunnel() {
    local ipfsnodeid="$1"
    
    log "INFO" "Closing P2P tunnel for localhost relay: $ipfsnodeid"
    
    # Close the tunnel using ipfs p2p close
    if ipfs p2p close -p "/x/strfry-$ipfsnodeid" 2>/dev/null; then
        log "INFO" "P2P tunnel closed successfully for $ipfsnodeid"
        return 0
    else
        log "WARN" "Failed to close P2P tunnel for $ipfsnodeid (may already be closed)"
        return 0
    fi
}

# Function to calculate timestamp for N days ago
get_timestamp_days_ago() {
    local days="$1"
    local timestamp=$(date -d "$days days ago" +%s)
    echo "$timestamp"
}



# Function to create backfill request
create_backfill_request() {
    local since_timestamp="$1"
    local peer="$2"
    
    log "INFO" "Creating backfill request for peer: $peer"
    log "INFO" "Requesting events since: $(date -d "@$since_timestamp" '+%Y-%m-%d %H:%M:%S')"
    
    # Get all HEX pubkeys from constellation
    local hex_pubkeys
    hex_pubkeys=$(get_constellation_hex_pubkeys)
    if [[ -z "$hex_pubkeys" ]]; then
        log "WARN" "No HEX pubkeys found, falling back to general backfill"
        # Fallback to general backfill without author filtering
        local temp_config="$HOME/.zen/strfry/backfill-temp.conf"
        cat > "$temp_config" <<EOF
# Temporary backfill configuration for $peer (general)
connectionTimeout = 30

streams {
    backfill_${RANDOM} {
        dir = "down"
        
        # Request events from the last N days
        filter = { 
            "kinds": [0, 1, 3, 22242],  # Profiles, text notes, contacts, auth events
            "since": $since_timestamp,
            "limit": 10000
        }
        
        urls = [
            "$peer"
        ]
    }
}
EOF
        echo "$temp_config"
        return
    fi
    
    # Convert hex pubkeys to array and create author filter
    local pubkeys_array=($(echo "$hex_pubkeys"))
    local authors_filter=""
    for pubkey in "${pubkeys_array[@]}"; do
        if [[ -n "$authors_filter" ]]; then
            authors_filter="${authors_filter}, \"$pubkey\""
        else
            authors_filter="\"$pubkey\""
        fi
    done
    
    log "INFO" "Targeting ${#pubkeys_array[@]} constellation members for backfill"
    
    # Create a temporary backfill configuration with author filtering
    local temp_config="$HOME/.zen/strfry/backfill-temp.conf"
    
    cat > "$temp_config" <<EOF
# Temporary backfill configuration for $peer (targeted)
connectionTimeout = 30

streams {
    backfill_${RANDOM} {
        dir = "down"
        
        # Request events from constellation members in the last N days
        filter = { 
            "kinds": [0, 1, 3, 22242],  # Profiles, text notes, contacts, auth events
            "authors": [$authors_filter],
            "since": $since_timestamp,
            "limit": 10000
        }
        
        urls = [
            "$peer"
        ]
    }
}
EOF
    
    echo "$temp_config"
}

# Function to create backfill request for P2P tunnel
create_p2p_backfill_request() {
    local since_timestamp="$1"
    local ipfsnodeid="$2"
    
    log "INFO" "Creating P2P backfill request for localhost relay: $ipfsnodeid"
    log "INFO" "Requesting events since: $(date -d "@$since_timestamp" '+%Y-%m-%d %H:%M:%S')"
    
    # Get all HEX pubkeys from constellation
    local hex_pubkeys
    hex_pubkeys=$(get_constellation_hex_pubkeys)
    if [[ -z "$hex_pubkeys" ]]; then
        log "WARN" "No HEX pubkeys found, falling back to general P2P backfill"
        # Fallback to general backfill without author filtering
        local temp_config="$HOME/.zen/strfry/backfill-p2p-temp.conf"
        cat > "$temp_config" <<EOF
# Temporary P2P backfill configuration for $ipfsnodeid (general)
connectionTimeout = 30

streams {
    backfill_p2p_${RANDOM} {
        dir = "down"
        
        # Request events from the last N days via P2P tunnel
        filter = { 
            "kinds": [0, 1, 3, 22242],  # Profiles, text notes, contacts, auth events
            "since": $since_timestamp,
            "limit": 10000
        }
        
        urls = [
            "ws://127.0.0.1:9999"
        ]
    }
}
EOF
        echo "$temp_config"
        return
    fi
    
    # Convert hex pubkeys to array and create author filter
    local pubkeys_array=($(echo "$hex_pubkeys"))
    local authors_filter=""
    for pubkey in "${pubkeys_array[@]}"; do
        if [[ -n "$authors_filter" ]]; then
            authors_filter="${authors_filter}, \"$pubkey\""
        else
            authors_filter="\"$pubkey\""
        fi
    done
    
    log "INFO" "Targeting ${#pubkeys_array[@]} constellation members for P2P backfill"
    
    # Create a temporary P2P backfill configuration with author filtering
    local temp_config="$HOME/.zen/strfry/backfill-p2p-temp.conf"
    
    cat > "$temp_config" <<EOF
# Temporary P2P backfill configuration for $ipfsnodeid (targeted)
connectionTimeout = 30

streams {
    backfill_p2p_${RANDOM} {
        dir = "down"
        
        # Request events from constellation members via P2P tunnel
        filter = { 
            "kinds": [0, 1, 3, 22242],  # Profiles, text notes, contacts, auth events
            "authors": [$authors_filter],
            "since": $since_timestamp,
            "limit": 10000
        }
        
        urls = [
            "ws://127.0.0.1:9999"
        ]
    }
}
EOF
    
    echo "$temp_config"
}

# Function to get event count from strfry database
get_event_count() {
    local db_path="$HOME/.zen/strfry/strfry-db/data.mdb"
    if [[ -f "$db_path" ]]; then
        # Use strfry scan with count option to get event count
        cd "$HOME/.zen/strfry"
        local count=$(./strfry scan --count '{}' 2>/dev/null | tail -1 | tr -d '[:space:]')
        if [[ -n "$count" && "$count" =~ ^[0-9]+$ ]]; then
            echo "$count"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Function to execute backfill
execute_backfill() {
    local temp_config="$1"
    local peer="$2"
    
    log "INFO" "Executing backfill from peer: $peer"
    
    if [[ "$DRYRUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would execute: strfry router $temp_config"
        return 0
    fi
    
    # Get event count before backfill
    local events_before=$(get_event_count)
    log "INFO" "Events in database before backfill: $events_before"
    
    # Execute backfill
    cd "$HOME/.zen/strfry"
    timeout 300 ./strfry router "$temp_config" >> "$BACKFILL_LOG" 2>&1 &
    local backfill_pid=$!
    
    # Wait for completion or timeout
    local elapsed=0
    while kill -0 "$backfill_pid" 2>/dev/null && [[ $elapsed -lt 300 ]]; do
        sleep 5
        elapsed=$((elapsed + 5))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log "INFO" "Backfill in progress... (${elapsed}s elapsed)"
        fi
    done
    
    # Check if process is still running
    if kill -0 "$backfill_pid" 2>/dev/null; then
        log "WARN" "Backfill timeout after 5 minutes, force killing"
        kill -9 "$backfill_pid" 2>/dev/null
        return 1
    else
        # Get event count after backfill
        local events_after=$(get_event_count)
        local events_added=$((events_after - events_before))
        
        if [[ $events_added -gt 0 ]]; then
            log "INFO" "Backfill completed successfully - Added $events_added new events"
            log "INFO" "Database: $events_before → $events_after events"
        else
            log "INFO" "Backfill completed successfully - No new events added"
        fi
        
        return 0
    fi
}

# Function to execute P2P backfill
execute_p2p_backfill() {
    local temp_config="$1"
    local ipfsnodeid="$2"
    
    log "INFO" "Executing P2P backfill from localhost relay: $ipfsnodeid"
    
    if [[ "$DRYRUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would execute: strfry router $temp_config via P2P tunnel"
        return 0
    fi
    
    # Get event count before backfill
    local events_before=$(get_event_count)
    log "INFO" "Events in database before P2P backfill: $events_before"
    
    # Execute backfill via P2P tunnel (localhost:9999)
    cd "$HOME/.zen/strfry"
    timeout 300 ./strfry router "$temp_config" >> "$BACKFILL_LOG" 2>&1 &
    local backfill_pid=$!
    
    # Wait for completion or timeout
    local elapsed=0
    while kill -0 "$backfill_pid" 2>/dev/null && [[ $elapsed -lt 300 ]]; do
        sleep 5
        elapsed=$((elapsed + 5))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log "INFO" "P2P backfill in progress... (${elapsed}s elapsed)"
        fi
    done
    
    # Check if process is still running
    if kill -0 "$backfill_pid" 2>/dev/null; then
        log "WARN" "P2P backfill timeout after 5 minutes, force killing"
        kill -9 "$backfill_pid" 2>/dev/null
        return 1
    else
        # Get event count after backfill
        local events_after=$(get_event_count)
        local events_added=$((events_after - events_before))
        
        if [[ $events_added -gt 0 ]]; then
            log "INFO" "P2P backfill completed successfully - Added $events_added new events"
            log "INFO" "Database: $events_before → $events_after events"
        else
            log "INFO" "P2P backfill completed successfully - No new events added"
        fi
        
        return 0
    fi
}

# Main execution
main() {
    log "INFO" "Starting Astroport constellation backfill process"
    log "INFO" "Backfilling $DAYS_BACK day(s) of events"
    
    # Check if strfry binary exists
    if [[ ! -x "$HOME/.zen/strfry/strfry" ]]; then
        log "ERROR" "strfry binary not found or not executable"
        exit 1
    fi
    
    # Get constellation peers directly from IPNS swarm discovery
    log "INFO" "Discovering constellation peers from IPNS swarm..."
    local discovered_peers
    discovered_peers=$(discover_constellation_peers 2>/dev/null)
    log "DEBUG" "discover_constellation_peers returned: '$discovered_peers'"
    
    local peers=()
    if [[ -n "$discovered_peers" ]]; then
        mapfile -t peers <<< "$discovered_peers"
        log "INFO" "Successfully discovered ${#peers[@]} peers from swarm"
    else
        log "WARN" "No peers discovered from swarm"
    fi
    
    if [[ ${#peers[@]} -eq 0 ]]; then
        log "ERROR" "No constellation peers found"
        exit 1
    fi
    
    log "INFO" "Found ${#peers[@]} constellation peers"
    for peer in "${peers[@]}"; do
        log "INFO" "  - $peer"
    done
    
    # Calculate timestamp for N days ago
    local since_timestamp=$(get_timestamp_days_ago "$DAYS_BACK")
    log "INFO" "Backfill timestamp: $since_timestamp ($(date -d "@$since_timestamp" '+%Y-%m-%d %H:%M:%S'))"
    
    if [[ "$DRYRUN" == "true" ]]; then
        log "INFO" "DRY RUN MODE - No actual backfill will be performed"
        log "INFO" "Would backfill from peers: ${peers[*]}"
        log "INFO" "Would request events since: $(date -d "@$since_timestamp" '+%Y-%m-%d %H:%M:%S')"
        exit 0
    fi
    
    # Process each peer
    local success_count=0
    local total_peers=${#peers[@]}
    
    for peer in "${peers[@]}"; do
        log "INFO" "Processing peer: $peer"
        
        local temp_config=""
        local is_p2p=false
        local ipfsnodeid=""
        
        # Check if this is a P2P localhost relay
        if [[ "$peer" =~ ^localhost:([^:]+):(.+)$ ]]; then
            ipfsnodeid="${BASH_REMATCH[1]}"
            local x_strfry_script="${BASH_REMATCH[2]}"
            is_p2p=true
            
            log "INFO" "Processing localhost relay via P2P tunnel: $ipfsnodeid"
            
            # Create P2P tunnel
            if create_p2p_tunnel "$ipfsnodeid" "$x_strfry_script"; then
                # Wait a moment for tunnel to be ready
                sleep 3
                
                # Create P2P backfill request
                temp_config=$(create_p2p_backfill_request "$since_timestamp" "$ipfsnodeid")
                if [[ -z "$temp_config" ]]; then
                    log "ERROR" "Failed to create P2P backfill request for $ipfsnodeid"
                    close_p2p_tunnel "$ipfsnodeid"
                    continue
                fi
            else
                log "ERROR" "Failed to create P2P tunnel for $ipfsnodeid"
                continue
            fi
        else
            # Regular routable relay
            log "INFO" "Processing routable relay: $peer"
            temp_config=$(create_backfill_request "$since_timestamp" "$peer")
            if [[ -z "$temp_config" ]]; then
                log "ERROR" "Failed to create backfill request for $peer"
                continue
            fi
        fi
        
        # Execute backfill
        local backfill_success=false
        if [[ "$is_p2p" == "true" ]]; then
            if execute_p2p_backfill "$temp_config" "$ipfsnodeid"; then
                log "INFO" "✅ P2P backfill successful for $ipfsnodeid"
                backfill_success=true
            else
                log "ERROR" "❌ P2P backfill failed for $ipfsnodeid"
            fi
        else
            if execute_backfill "$temp_config" "$peer"; then
                log "INFO" "✅ Backfill successful for $peer"
                backfill_success=true
            else
                log "ERROR" "❌ Backfill failed for $peer"
            fi
        fi
        
        if [[ "$backfill_success" == "true" ]]; then
            ((success_count++))
        fi
        
        # Clean up temporary config
        rm -f "$temp_config"
        
        # Close P2P tunnel if it was created
        if [[ "$is_p2p" == "true" ]]; then
            log "INFO" "Closing P2P tunnel for $ipfsnodeid"
            close_p2p_tunnel "$ipfsnodeid"
        fi
        
        # Small delay between peers to avoid overwhelming
        sleep 2
    done
    
    # Summary
    log "INFO" "Backfill process completed"
    log "INFO" "Success: $success_count/$total_peers peers"
    
    if [[ $success_count -eq $total_peers ]]; then
        log "INFO" "🎉 All peers backfilled successfully!"
        exit 0
    else
        log "WARN" "⚠️  Some peers failed to backfill"
        exit 1
    fi
}

# Run main function
main "$@"
