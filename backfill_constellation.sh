#!/bin/bash
# Astroport constellation backfill script
# This script requests and copies messages from the current day to ensure complete synchronization

## SET ASTROPORT ENVIRONNEMENT
[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "STRFRY CONSTELLATION BACKFILL NEEDS ~/.zen/Astroport.ONE" \
    && exit 1

source ~/.zen/Astroport.ONE/tools/my.sh

# Configuration
BACKFILL_LOG="$HOME/.zen/strfry/constellation-backfill.log"
BACKFILL_PID="$HOME/.zen/strfry/constellation-backfill.pid"

# Parse command line arguments
DRYRUN=false
DAYS_BACK=1
VERBOSE=false
INCLUDE_DMS=true
NO_VERIFY=true

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
        --no-dms)
            INCLUDE_DMS=false
            shift
            ;;
        --verify)
            NO_VERIFY=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--DRYRUN] [--days N] [--verbose|-v] [--no-dms] [--verify] [--show-hex] [--stats]"
            echo ""
            echo "Options:"
            echo "  --DRYRUN     Show what would be done without executing"
            echo "  --days N     Backfill N days back (default: 1)"
            echo "  --verbose    Show detailed output"
            echo "  --no-dms     Exclude direct messages (DMs) from synchronization"
            echo "  --verify     Enable signature verification (slower but more secure)"
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
                hex_count=$(cat $nostr_dir/*/HEX | wc -l)
            fi
            
            if [[ -d "$swarm_dir" ]]; then
                amis_count=$(cat $swarm_dir/*/amisOfAmis.txt | wc -l)
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
    
    # First, get HEX pubkeys from nostr directory using cat (optimized)
    if [[ -d "$nostr_dir" ]]; then
        echo "INFO: Scanning ~/.zen/game/nostr/*/HEX for constellation members..." >&2
        # Use cat directly on all HEX files (faster than find + cat)
        if ls "$nostr_dir"/*/HEX >/dev/null 2>&1; then
            while IFS= read -r pubkey; do
                pubkey=$(echo "$pubkey" | tr -d '[:space:]')
                if [[ -n "$pubkey" && ${#pubkey} -eq 64 ]]; then
                    hex_pubkeys+=("$pubkey")
                    echo "DEBUG: Found HEX pubkey: ${pubkey:0:8}..." >&2
                fi
            done < <(cat "$nostr_dir"/*/HEX 2>/dev/null)
        fi
    else
        echo "WARN: Nostr directory not found: $nostr_dir" >&2
    fi
    
    # Then, get HEX pubkeys from amisOfAmis.txt files in swarm using cat (optimized)
    if [[ -d "$swarm_dir" ]]; then
        echo "INFO: Scanning ~/.zen/tmp/swarm/*/amisOfAmis.txt for extended network..." >&2
        # Use cat directly on all amisOfAmis.txt files (faster than find + cat)
        if ls "$swarm_dir"/*/amisOfAmis.txt >/dev/null 2>&1; then
            while IFS= read -r line; do
                local pubkey=$(echo "$line" | tr -d '[:space:]')
                if [[ -n "$pubkey" && ${#pubkey} -eq 64 ]]; then
                    hex_pubkeys+=("$pubkey")
                    echo "DEBUG: Found amisOfAmis pubkey: ${pubkey:0:8}..." >&2
                fi
            done < <(cat "$swarm_dir"/*/amisOfAmis.txt 2>/dev/null)
        fi
    else
        echo "WARN: Swarm directory not found: $swarm_dir" >&2
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${hex_pubkeys[@]}" | sort -u
}



# Function to discover constellation peers from IPNS swarm
discover_constellation_peers() {
    local peers=()
    local swarm_dir="$HOME/.zen/tmp/swarm"
    
    # Get local IPFSNODEID to exclude self from synchronization
    local local_ipfsnodeid="$IPFSNODEID"
    if [[ -z "$local_ipfsnodeid" ]]; then
        # Try to get IPFSNODEID from environment or config
        if [[ -f "$HOME/.zen/Astroport.ONE/tools/my.sh" ]]; then
            source "$HOME/.zen/Astroport.ONE/tools/my.sh"
            local_ipfsnodeid="$IPFSNODEID"
        fi
    fi
        
    if [[ ! -d "$swarm_dir" ]]; then
        log "WARN" "Swarm directory not found: $swarm_dir"
        return 1
    fi
    
    echo "INFO: Scanning IPNS swarm for constellation peers..." >&2
    if [[ -n "$local_ipfsnodeid" ]]; then
        echo "INFO: Excluding local node: $local_ipfsnodeid" >&2
    fi
    
    # Find all 12345.json files in swarm directory
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            # Extract myRELAY and ipfsnodeid values from JSON using jq (more robust)
            local relay_url=$(jq -r '.myRELAY // empty' "$file" 2>/dev/null)
            local ipfsnodeid=$(jq -r '.ipfsnodeid // empty' "$file" 2>/dev/null)
            
            if [[ -n "$relay_url" && -n "$ipfsnodeid" ]]; then
                # Skip if this is our own node
                if [[ "$ipfsnodeid" == "$local_ipfsnodeid" ]]; then
                    echo "INFO: Skipping local node: $ipfsnodeid" >&2
                    continue
                fi
                
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

# Function to create backfill request using HTTP API
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
            "kinds": [0, 1, 3, 4, 5, 6, 7, 30023, 30024],  # Profiles, text notes, contacts, DMs, deletions, reposts, reactions, blog, calendar
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
    
    # Build kinds array based on INCLUDE_DMS setting
    local kinds_array="[0, 1, 3, 5, 6, 7, 30023, 30024]"  # Base kinds
    if [[ "$INCLUDE_DMS" == "true" ]]; then
        kinds_array="[0, 1, 3, 4, 5, 6, 7, 30023, 30024]"  # Include DMs
        log "INFO" "Including direct messages (DMs) in synchronization"
    else
        log "INFO" "Excluding direct messages (DMs) from synchronization"
    fi
    
    cat > "$temp_config" <<EOF
# Temporary backfill configuration for $peer (targeted)
connectionTimeout = 30

streams {
    backfill_${RANDOM} {
        dir = "down"
        
        # Request events from constellation members in the last N days
        filter = { 
            "kinds": $kinds_array,  # Dynamic kinds based on --no-dms option
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

# Function to split HEX pubkeys into batches
split_hex_pubkeys_into_batches() {
    local hex_pubkeys="$1"
    local batch_size="${2:-100}"  # Default batch size of 100
    
    local authors_array=($(echo "$hex_pubkeys"))
    local total_authors=${#authors_array[@]}
    local batches=()
    
    log "INFO" "Splitting $total_authors HEX pubkeys into batches of $batch_size"
    
    for ((i=0; i<total_authors; i+=batch_size)); do
        local batch=()
        for ((j=i; j<i+batch_size && j<total_authors; j++)); do
            batch+=("${authors_array[$j]}")
        done
        
        # Convert batch array to space-separated string
        local batch_string="${batch[*]}"
        batches+=("$batch_string")
        
        log "DEBUG" "Created batch $((i/batch_size + 1)) with ${#batch[@]} pubkeys"
    done
    
    # Return batches as array
    printf '%s\n' "${batches[@]}"
}

# Function to execute backfill using WebSocket connection with batching
execute_backfill_websocket() {
    local peer="$1"
    local since_timestamp="$2"
    local hex_pubkeys="$3"
    
    log "INFO" "Executing WebSocket backfill from peer: $peer"
    
    # If no hex_pubkeys, do a general backfill
    if [[ -z "$hex_pubkeys" ]]; then
        log "INFO" "No HEX pubkeys provided, performing general backfill"
        execute_backfill_websocket_batch "$peer" "$since_timestamp" ""
        return $?
    fi
    
    # Split hex_pubkeys into batches
    local batches
    batches=$(split_hex_pubkeys_into_batches "$hex_pubkeys" 50)
    
    if [[ -z "$batches" ]]; then
        log "WARN" "No batches created, skipping backfill"
        return 1
    fi
    
    # Convert to array
    local batches_array=()
    mapfile -t batches_array <<< "$batches"
    
    log "INFO" "Executing backfill in ${#batches_array[@]} batches"
    
    # Process each batch
    local total_events=0
    local batch_number=1
    
    for batch in "${batches_array[@]}"; do
        log "INFO" "Processing batch $batch_number/${#batches_array[@]}"
        
        if execute_backfill_websocket_batch "$peer" "$since_timestamp" "$batch"; then
            local batch_events=$?
            total_events=$((total_events + batch_events))
            log "INFO" "Batch $batch_number completed with $batch_events events"
        else
            log "WARN" "Batch $batch_number failed"
        fi
        
        ((batch_number++))
        
        # Small delay between batches to avoid overwhelming the relay
        sleep 1
    done
    
    log "INFO" "Total events collected across all batches: $total_events"
    return 0
}

# Function to execute a single batch backfill using WebSocket connection
execute_backfill_websocket_batch() {
    local peer="$1"
    local since_timestamp="$2"
    local hex_pubkeys_batch="$3"
    
    # Create the Nostr REQ message
    local req_message='["REQ", "backfill", {'
    
    # Build kinds array based on INCLUDE_DMS setting
    if [[ "$INCLUDE_DMS" == "true" ]]; then
        req_message+='"kinds": [0, 1, 3, 4, 5, 6, 7, 30023, 30024], '  # Include DMs
    else
        req_message+='"kinds": [0, 1, 3, 5, 6, 7, 30023, 30024], '  # Exclude DMs
    fi
    
    req_message+="\"since\": $since_timestamp, "
    req_message+='"limit": 10000'
    
    # Add authors filter if hex_pubkeys are provided
    if [[ -n "$hex_pubkeys_batch" ]]; then
        local authors_array=($(echo "$hex_pubkeys_batch"))
        local authors_json="["
        for i in "${!authors_array[@]}"; do
            if [[ $i -gt 0 ]]; then
                authors_json+=", "
            fi
            authors_json+="\"${authors_array[$i]}\""
        done
        authors_json+="]"
        req_message+=", \"authors\": $authors_json"
        
        log "DEBUG" "Batch contains ${#authors_array[@]} authors"
    fi
    
    req_message+='}]'
    
    log "INFO" "Connecting to WebSocket: $peer"
    log "DEBUG" "Request size: ${#req_message} characters"
    
    # Create a temporary Python script for WebSocket connection
    local python_script="$HOME/.zen/strfry/websocket_backfill_${RANDOM}.py"
    local response_file="$HOME/.zen/strfry/backfill-response-${RANDOM}.json"
    
    cat > "$python_script" <<EOF
#!/usr/bin/env python3
import asyncio
import websockets
import json
import sys
import signal
import time

async def backfill_websocket(websocket_url, req_message, response_file):
    try:
        async with websockets.connect(websocket_url, ping_interval=None, ping_timeout=None) as websocket:
            print(f"Connected to {websocket_url}")
            
            # Send the REQ message
            await websocket.send(req_message)
            print(f"Sent request: {req_message}")
            
            # Collect events for 30 seconds
            events = []
            start_time = time.time()
            timeout = 30
            
            while time.time() - start_time < timeout:
                try:
                    message = await asyncio.wait_for(websocket.recv(), timeout=5)
                    data = json.loads(message)
                    
                    if isinstance(data, list) and len(data) > 0:
                        if data[0] == "EVENT":
                            events.append(data[2])  # The event object
                        elif data[0] == "EOSE":
                            print("Received EOSE, ending collection")
                            break
                        elif data[0] == "NOTICE":
                            print(f"Notice: {data[1]}")
                        elif data[0] == "OK":
                            print(f"OK: {data[1]} - {data[2]}")
                except asyncio.TimeoutError:
                    continue
                except Exception as e:
                    print(f"Error processing message: {e}")
                    break
            
            # Save events to file
            with open(response_file, 'w') as f:
                json.dump(events, f, indent=2)
            
            print(f"Collected {len(events)} events")
            return len(events)
            
    except Exception as e:
        print(f"WebSocket error: {e}")
        return 0

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 script.py <websocket_url> <req_message> <response_file>")
        sys.exit(1)
    
    websocket_url = sys.argv[1]
    req_message = sys.argv[2]
    response_file = sys.argv[3]
    
    result = asyncio.run(backfill_websocket(websocket_url, req_message, response_file))
    sys.exit(0 if result > 0 else 1)
EOF
    
    # Make Python script executable
    chmod +x "$python_script"
    
    # Execute the Python WebSocket script and capture the number of events
    local python_output
    python_output=$(python3 "$python_script" "$peer" "$req_message" "$response_file" 2>/dev/null)
    local python_exit_code=$?
    
    if [[ $python_exit_code -eq 0 ]]; then
        # Extract the number of events from the output
        local events_count=$(echo "$python_output" | grep -o "Collected [0-9]* events" | grep -o "[0-9]*" || echo "0")
        
        log "INFO" "WebSocket backfill completed successfully"
        log "INFO" "Response saved to: $response_file"
        log "INFO" "Collected $events_count events in this batch"
        
        # Process the response and import events to local strfry
        process_and_import_events "$response_file"
        
        # Clean up
        rm -f "$response_file" "$python_script"
        
        # Return the number of events collected
        return "$events_count"
    else
        log "ERROR" "WebSocket backfill failed"
        rm -f "$response_file" "$python_script"
        return 0
    fi
}

# Function to process and import events from WebSocket response
process_and_import_events() {
    local response_file="$1"
    
    log "INFO" "Processing and importing events from: $response_file"
    
    # Check if response file exists and has content
    if [[ ! -f "$response_file" || ! -s "$response_file" ]]; then
        log "WARN" "Response file is empty or does not exist: $response_file"
        return 0
    fi
    
    # Count different event types for logging
    local total_events=$(jq -r 'length' "$response_file" 2>/dev/null | head -1 || echo "0")
    local dm_events=$(jq -r '[.[] | select(.kind == 4)] | length' "$response_file" 2>/dev/null || echo "0")
    local public_events=$(jq -r '[.[] | select(.kind != 4)] | length' "$response_file" 2>/dev/null || echo "0")
    
    log "INFO" "Event breakdown: $total_events total ($dm_events DMs, $public_events public)"
    
    # Create a filtered file without "Hello NOSTR visitor." messages
    local filtered_file="${response_file%.json}_filtered.json"
    
    log "INFO" "Filtering out 'Hello NOSTR visitor.' messages..."
    
    # Filter out events containing "Hello NOSTR visitor." in their content
    jq -r '.[] | select(.content | test("Hello NOSTR visitor.") | not)' "$response_file" > "$filtered_file" 2>/dev/null
    
    # Count events before and after filtering
    local total_events=$(jq -r 'length' "$response_file" 2>/dev/null | head -1 || echo "0")
    local filtered_events=$(jq -r 'length' "$filtered_file" 2>/dev/null | head -1 || echo "0")
    local removed_events=$((total_events - filtered_events))
    
    log "INFO" "Total events: $total_events"
    log "INFO" "Events after filtering: $filtered_events"
    log "INFO" "Removed 'Hello NOSTR visitor.' messages: $removed_events"
    
    # Check if we have events to import
    if [[ ! -s "$filtered_file" ]]; then
        log "WARN" "No events remaining after filtering"
        rm -f "$filtered_file"
        return 0
    fi
    
    # Convert filtered events to strfry import format (one event per line)
    local import_file="${response_file%.json}_import.ndjson"
    
    log "INFO" "Converting to strfry import format..."
    jq -c '.[]' "$filtered_file" > "$import_file" 2>/dev/null
    
    # Import events to strfry with optional verification
    local import_cmd="./strfry import"
    if [[ "$NO_VERIFY" == "true" ]]; then
        import_cmd="./strfry import --no-verify"
        log "INFO" "Importing $filtered_events events to strfry (no-verify mode for speed)..."
    else
        log "INFO" "Importing $filtered_events events to strfry (with signature verification)..."
    fi
    
    cd ~/.zen/strfry
    if $import_cmd < "$import_file" 2>/dev/null; then
        if [[ "$NO_VERIFY" == "true" ]]; then
            log "INFO" "✅ Successfully imported $filtered_events events to strfry (no-verify mode)"
        else
            log "INFO" "✅ Successfully imported $filtered_events events to strfry (verified mode)"
        fi
    else
        log "ERROR" "❌ Failed to import events to strfry"
        rm -f "$filtered_file" "$import_file"
        return 1
    fi
    
    # Clean up temporary files
    rm -f "$filtered_file" "$import_file"
    
    log "INFO" "Import process completed successfully"
}

# Function to execute WebSocket backfill via P2P tunnel for localhost relays
execute_p2p_websocket_backfill() {
    local ipfsnodeid="$1"
    local since_timestamp="$2"
    local hex_pubkeys="$3"
    
    log "INFO" "Executing WebSocket backfill via P2P tunnel for localhost relay: $ipfsnodeid"
    
    # Use the same WebSocket approach but connect to localhost:9999 (P2P tunnel)
    if execute_backfill_websocket "ws://127.0.0.1:9999" "$since_timestamp" "$hex_pubkeys"; then
        log "INFO" "✅ P2P WebSocket backfill successful for $ipfsnodeid"
        return 0
    else
        log "ERROR" "❌ P2P WebSocket backfill failed for $ipfsnodeid"
        return 1
    fi
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
        
        # Show DM configuration in dry run
        if [[ "$INCLUDE_DMS" == "true" ]]; then
            log "INFO" "Would include direct messages (DMs) in synchronization"
        else
            log "INFO" "Would exclude direct messages (DMs) from synchronization"
        fi
        
        # Show verification mode in dry run
        if [[ "$NO_VERIFY" == "true" ]]; then
            log "INFO" "Would use --no-verify mode for faster import (trusted constellation sources)"
        else
            log "INFO" "Would use signature verification mode for secure import"
        fi
        
        exit 0
    fi
    
    # Process each peer
    local success_count=0
    local total_peers=${#peers[@]}
    
    for peer in "${peers[@]}"; do
        log "INFO" "Processing peer: $peer"
        
        local is_p2p=false
        local ipfsnodeid=""
        
        # Get HEX pubkeys for targeted backfill (same for all relay types)
        local hex_pubkeys=$(get_constellation_hex_pubkeys)
        
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
                
                # Execute WebSocket backfill via P2P tunnel
                if execute_p2p_websocket_backfill "$ipfsnodeid" "$since_timestamp" "$hex_pubkeys"; then
                    log "INFO" "✅ P2P WebSocket backfill successful for $ipfsnodeid"
                    backfill_success=true
                else
                    log "ERROR" "❌ P2P WebSocket backfill failed for $ipfsnodeid"
                fi
            else
                log "ERROR" "Failed to create P2P tunnel for $ipfsnodeid"
                continue
            fi
        else
            # Regular routable relay - extract URL from routable: prefix
            local relay_url=$(echo "$peer" | sed 's/^routable://')
            log "INFO" "Processing routable relay: $relay_url"
            
            # Execute WebSocket backfill for routable relay
            if execute_backfill_websocket "$relay_url" "$since_timestamp" "$hex_pubkeys"; then
                log "INFO" "✅ WebSocket backfill successful for $relay_url"
                backfill_success=true
            else
                log "ERROR" "❌ WebSocket backfill failed for $relay_url"
            fi
        fi
        
        if [[ "$backfill_success" == "true" ]]; then
            ((success_count++))
        fi
        
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
