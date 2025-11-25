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
BACKFILL_ERROR_LOG="$HOME/.zen/strfry/constellation-backfill.error.log"
BACKFILL_PID="$HOME/.zen/strfry/constellation-backfill.pid"
LOCK_FILE="$HOME/.zen/strfry/constellation-backfill.lock"

# Log rotation settings (for error log only)
MAX_LOG_SIZE_MB=10  # Rotate when log exceeds 10MB
MAX_LOG_FILES=5     # Keep 5 rotated log files

# Parse command line arguments
DRYRUN=false
DAYS_BACK=1
VERBOSE=false
INCLUDE_DMS=true
NO_VERIFY=true
EXTRACT_PROFILES=true

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
        --no-profiles)
            EXTRACT_PROFILES=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--DRYRUN] [--days N] [--verbose|-v] [--no-dms] [--verify] [--no-profiles] [--show-hex] [--stats]"
            echo ""
            echo "Options:"
            echo "  --DRYRUN     Show what would be done without executing"
            echo "  --days N     Backfill N days back (default: 1)"
            echo "  --verbose    Show detailed output"
            echo "  --no-dms     Exclude direct messages (DMs) from synchronization"
            echo "  --verify     Enable signature verification (slower but more secure)"
            echo "  --no-profiles Skip profile extraction from HEX pubkeys"
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

# Function to rotate logs if they exceed size limit
rotate_logs() {
    local log_file="$1"
    local max_size_mb="$2"
    local max_files="$3"
    
    if [[ ! -f "$log_file" ]]; then
        return 0
    fi
    
    # Check if log file exceeds size limit
    local file_size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)
    
    if [[ -z "$file_size_mb" ]]; then
        file_size_mb=0
    fi
    
    if [[ $file_size_mb -gt $max_size_mb ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Rotating log file: $log_file (${file_size_mb}MB > ${max_size_mb}MB)" >> "$log_file"
        
        # Rotate existing files
        for ((i=max_files-1; i>=1; i--)); do
            if [[ -f "${log_file}.${i}" ]]; then
                mv "${log_file}.${i}" "${log_file}.$((i+1))"
            fi
        done
        
        # Move current log to .1
        mv "$log_file" "${log_file}.1"
        
        # Create new empty log file
        touch "$log_file"
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Log rotation completed: $log_file -> ${log_file}.1" >> "$log_file"
        
        # Remove old log files beyond max_files
        for ((i=max_files+1; i<=10; i++)); do
            if [[ -f "${log_file}.${i}" ]]; then
                rm -f "${log_file}.${i}"
            fi
        done
    fi
}

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$VERBOSE" == "true" || "$level" == "ERROR" || "$level" == "WARN" ]]; then
        echo "[$timestamp] [$level] $message"
    fi
    
    # Always log to main file
    echo "[$timestamp] [$level] $message" >> "$BACKFILL_LOG"
    
    # Also log errors and warnings to error log
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        echo "[$timestamp] [$level] $message" >> "$BACKFILL_ERROR_LOG"
    fi
}

# Function to check if backfill is already running
is_backfill_running() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$pid" && -d "/proc/$pid" ]]; then
            log "INFO" "Backfill already running with PID: $pid"
            return 0  # Backfill is running
        else
            # Remove stale lock file
            log "WARN" "Removing stale lock file (PID $pid not running)"
            rm -f "$LOCK_FILE"
        fi
    fi
    return 1  # No backfill running
}

# Function to create lock file atomically (prevent race conditions)
create_lock() {
    # Try to create lock file atomically using mkdir (atomic operation)
    local lock_dir="${LOCK_FILE}.dir"
    
    # Try to create directory (atomic operation)
    if mkdir "$lock_dir" 2>/dev/null; then
        # Successfully created directory, write PID
        echo $$ > "$LOCK_FILE"
        rmdir "$lock_dir" 2>/dev/null
        log "INFO" "Created lock file with PID $$"
        return 0
    else
        # Directory already exists, another process is creating lock
        log "WARN" "Lock directory already exists, another process may be starting"
        # Wait a moment and check again
        sleep 1
        if [[ -f "$LOCK_FILE" ]]; then
            local pid=$(cat "$LOCK_FILE" 2>/dev/null)
            if [[ -n "$pid" && -d "/proc/$pid" ]]; then
                log "INFO" "Backfill already running with PID: $pid (confirmed after wait)"
                return 1  # Lock is valid
            fi
        fi
        # Lock file doesn't exist or PID is invalid, try again
        rm -rf "$lock_dir" "$LOCK_FILE" 2>/dev/null
        if mkdir "$lock_dir" 2>/dev/null; then
            echo $$ > "$LOCK_FILE"
            rmdir "$lock_dir" 2>/dev/null
            log "INFO" "Created lock file with PID $$ (after retry)"
            return 0
        else
            log "ERROR" "Failed to create lock file (race condition)"
            return 1
        fi
    fi
}

# Function to remove lock file
remove_lock() {
    rm -f "$LOCK_FILE"
    log "INFO" "Removed lock file"
}

# Trap to ensure lock file is removed on exit
trap remove_lock EXIT INT TERM

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
                # Strict validation: exactly 64 hex characters
                if [[ -n "$pubkey" && ${#pubkey} -eq 64 && "$pubkey" =~ ^[0-9a-fA-F]{64}$ ]]; then
                    hex_pubkeys+=("$pubkey")
                    echo "DEBUG: Found HEX pubkey: ${pubkey:0:8}..." >&2
                elif [[ -n "$pubkey" ]]; then
                    echo "WARN: Invalid HEX pubkey (length=${#pubkey}): ${pubkey:0:16}..." >&2
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
                # Strict validation: exactly 64 hex characters
                # Also reject lines that look like log messages (contain brackets or "INFO", "DEBUG", "Connected", etc.)
                if [[ -n "$pubkey" && ${#pubkey} -eq 64 && "$pubkey" =~ ^[0-9a-fA-F]{64}$ && ! "$line" =~ \[|INFO|DEBUG|Connected|Sent|Received|Found ]]; then
                    hex_pubkeys+=("$pubkey")
                    echo "DEBUG: Found amisOfAmis pubkey: ${pubkey:0:8}..." >&2
                elif [[ -n "$pubkey" && ${#pubkey} -ne 64 ]]; then
                    echo "DEBUG: Skipping non-hex line (length=${#pubkey}): ${line:0:50}..." >&2
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
            "kinds": [0, 1, 3, 4, 5, 6, 7, 8, 21, 22, 40, 41, 42, 44, 1063, 1111, 1222, 1244, 1985, 1986, 30001, 30005, 30008, 30009, 10001, 30023, 30024, 30312, 30313, 30315, 30500, 30501, 30502, 30503, 30800, 31900, 31901, 31902, 10000],  # Profiles, text notes, contacts, DMs, deletions, reposts, reactions, badge awards (8 - NIP-58), videos (short/long), channel creation/metadata/messages/mute (40-44 - NIP-28), file metadata (1063 - NIP-94), comments (1111 - NIP-22), voice messages (1222, 1244 - NIP-A0), user tags (1985 - NIP-32), TMDB enrichments (1986, 30001 - NIP-71 extension), playlists (30005, 10001 - NIP-51), profile badges (30008 - NIP-58), badge definitions (30009 - NIP-58), blog, calendar, user statuses (30315 - NIP-38), DID documents (30800 - NIP-101), ORE spaces/meetings (30312-30313), Oracle permits (30500-30503), cookie workflows (31900-31902 - NIP-101 extension), analytics (10000 - NIP-10000, encrypted/non-encrypted determined by content)
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
    local kinds_array="[0, 1, 3, 5, 6, 7, 8, 21, 22, 40, 41, 42, 44, 1063, 1111, 1222, 1244, 1985, 1986, 30001, 30005, 30008, 30009, 10001, 30023, 30024, 30312, 30313, 30315, 30500, 30501, 30502, 30503, 30800, 31900, 31901, 31902, 10000]"  # Base kinds + badge awards (8 - NIP-58) + videos + files + comments + voice messages + user tags + channels + mute + TMDB enrichments + playlists (30005/10001 - NIP-51) + profile badges (30008 - NIP-58) + badge definitions (30009 - NIP-58) + user statuses + DID + ORE + Oracle + workflows + analytics (10000 - NIP-10000, encrypted/non-encrypted determined by content)
    if [[ "$INCLUDE_DMS" == "true" ]]; then
        kinds_array="[0, 1, 3, 4, 5, 6, 7, 8, 21, 22, 40, 41, 42, 44, 1063, 1111, 1222, 1244, 1985, 1986, 30001, 30005, 30008, 30009, 10001, 30023, 30024, 30312, 30313, 30315, 30500, 30501, 30502, 30503, 30800, 31900, 31901, 31902, 10000]"  # Include DMs + badge awards (8 - NIP-58) + videos + files + comments + voice messages + user tags + channels + mute + TMDB enrichments + playlists (30005/10001 - NIP-51) + profile badges (30008 - NIP-58) + badge definitions (30009 - NIP-58) + user statuses + DID + ORE + Oracle + workflows + analytics (10000 - NIP-10000, encrypted/non-encrypted determined by content)
        log "INFO" "Including direct messages (DMs), video events (kind 21/22), file metadata (kind 1063), comments (kind 1111), voice messages (kind 1222/1244 - NIP-A0), user tags (kind 1985 - NIP-32), TMDB enrichments (kind 1986/30001 - NIP-71 extension), channel messages/mute (kind 40-44 - NIP-28), playlists (kind 30005/10001 - NIP-51), user statuses (kind 30315 - NIP-38), and cookie workflows (kind 31900-31902 - NIP-101 extension) in synchronization"
    else
        log "INFO" "Excluding direct messages (DMs) but including video events (kind 21/22), file metadata (kind 1063), comments (kind 1111), voice messages (kind 1222/1244 - NIP-A0), user tags (kind 1985 - NIP-32), TMDB enrichments (kind 1986/30001 - NIP-71 extension), channel messages/mute (kind 40-44 - NIP-28), playlists (kind 30005/10001 - NIP-51), user statuses (kind 30315 - NIP-38), and cookie workflows (kind 31900-31902 - NIP-101 extension) in synchronization"
    fi
    log "INFO" "Including kind 1063 (file metadata - NIP-94) in synchronization"
    log "INFO" "Including kind 1111 (video comments - NIP-22) in synchronization"
    log "INFO" "Including kind 1222/1244 (voice messages - NIP-A0) in synchronization"
    log "INFO" "Including kind 1985 (user tags - NIP-32) in synchronization"
    log "INFO" "Including kind 1986/30001 (TMDB metadata enrichments - NIP-71 extension) in synchronization"
    log "INFO" "Including kind 40-44 (channel creation/metadata/messages/mute - NIP-28) in synchronization"
    log "INFO" "Including kind 30005/10001 (playlists - NIP-51) in synchronization"
    log "INFO" "Including kind 30315 (user statuses - NIP-38) in synchronization"
    log "INFO" "Including kind 30800 (DID documents - NIP-101) in synchronization"
    log "INFO" "Including kind 30312-30313 (ORE Meeting Spaces and Verification Meetings) in synchronization"
    log "INFO" "Including kind 21/22 (video events from process_youtube.sh) in synchronization"
    log "INFO" "Including kind 8 (badge awards - NIP-58) in synchronization"
    log "INFO" "Including kind 30008 (profile badges - NIP-58) in synchronization"
    log "INFO" "Including kind 30009 (badge definitions - NIP-58) in synchronization"
    log "INFO" "Including kind 30500-30503 (Oracle permit system) in synchronization"
    log "INFO" "Including kind 31900-31902 (cookie workflows - NIP-101 extension) in synchronization"
    log "INFO" "Including kind 10000 (analytics events - NIP-10000, encrypted/non-encrypted determined by content) in synchronization"
    
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
    
    # Convert to array for proper counting with strict validation
    local authors_array=()
    while IFS= read -r pubkey; do
        # Clean and validate each pubkey
        pubkey=$(echo "$pubkey" | tr -d '[:space:]')
        # Strict validation: exactly 64 hex characters AND not a log line
        if [[ -n "$pubkey" && ${#pubkey} -eq 64 && "$pubkey" =~ ^[0-9a-fA-F]{64}$ ]]; then
            # Additional check: reject if it looks like a timestamp or log pattern
            if [[ ! "$pubkey" =~ ^[0-9]{8}[0-9a-fA-F]{56}$ ]] && [[ ! "$pubkey" =~ 202[0-9] ]]; then
                authors_array+=("$pubkey")
            else
                log "DEBUG" "Rejecting timestamp-like hex (length=${#pubkey}): ${pubkey:0:16}..."
            fi
        elif [[ -n "$pubkey" && ${#pubkey} -gt 20 ]]; then
            log "DEBUG" "Rejecting invalid hex in batch split (length=${#pubkey}): ${pubkey:0:16}..."
        fi
    done <<< "$hex_pubkeys"
    
    local total_authors=${#authors_array[@]}
    
    if [[ $total_authors -eq 0 ]]; then
        log "ERROR" "No valid hex pubkeys to split into batches"
        return 1
    fi
    
    local batches=()
    
    log "INFO" "Splitting $total_authors valid HEX pubkeys into batches of $batch_size"
    
    for ((i=0; i<total_authors; i+=batch_size)); do
        local batch=()
        for ((j=i; j<i+batch_size && j<total_authors; j++)); do
            batch+=("${authors_array[$j]}")
        done
        
        # Convert batch array to newline-separated string (better than space-separated)
        local batch_string=$(printf '%s\n' "${batch[@]}")
        batches+=("$batch_string")
        
        log "DEBUG" "Created batch $((i/batch_size + 1)) with ${#batch[@]} pubkeys"
    done
    
    # Return batches as array (newline-separated)
    printf '%s\n---BATCH_SEPARATOR---\n' "${batches[@]}"
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
    
    # OPT #6: Batch size adaptatif selon le nombre de HEX
    local total_hex=$(echo "$hex_pubkeys" | wc -l)
    local batch_size=50  # Default
    
    if [[ $total_hex -lt 50 ]]; then
        batch_size=$total_hex  # 1 seul batch
        log "INFO" "Small constellation: using single batch of $batch_size HEX pubkeys"
    elif [[ $total_hex -gt 200 ]]; then
        batch_size=100  # Batches plus gros si beaucoup de HEX
        log "INFO" "Large constellation: using batch size of $batch_size HEX pubkeys"
    fi
    
    # Split hex_pubkeys into batches
    local batches
    batches=$(split_hex_pubkeys_into_batches "$hex_pubkeys" "$batch_size")
    
    if [[ -z "$batches" ]]; then
        log "WARN" "No batches created, skipping backfill"
        return 1
    fi
    
    # Convert to array (split on ---BATCH_SEPARATOR---)
    local batches_array=()
    local current_batch=""
    while IFS= read -r line; do
        if [[ "$line" == "---BATCH_SEPARATOR---" ]]; then
            if [[ -n "$current_batch" ]]; then
                batches_array+=("$current_batch")
                current_batch=""
            fi
        else
            if [[ -n "$current_batch" ]]; then
                current_batch+=$'\n'
            fi
            current_batch+="$line"
        fi
    done <<< "$batches"
    
    # Add the last batch if it exists
    if [[ -n "$current_batch" ]]; then
        batches_array+=("$current_batch")
    fi
    
    log "INFO" "Executing backfill in ${#batches_array[@]} batches"
    
    # Process each batch with retry logic
    local total_events=0
    local batch_number=1
    local MAX_RETRIES=3  # Maximum retry attempts per batch
    
    for batch in "${batches_array[@]}"; do
        log "INFO" "Processing batch $batch_number/${#batches_array[@]}"
        
        local batch_success=false
        local retry_count=0
        
        # Retry logic for failed batches
        while [[ $retry_count -lt $MAX_RETRIES && "$batch_success" == "false" ]]; do
            if [[ $retry_count -gt 0 ]]; then
                log "INFO" "Retry attempt $retry_count/$MAX_RETRIES for batch $batch_number"
                sleep $((retry_count * 2))  # Exponential backoff: 2s, 4s, 6s
            fi
            
            # Store result in a variable to check exit code properly
            if execute_backfill_websocket_batch "$peer" "$since_timestamp" "$batch"; then
                local batch_exit_code=$?
                batch_success=true
                # Exit code 0 means success, even if no events collected
                if [[ $retry_count -gt 0 ]]; then
                    log "INFO" "✅ Batch $batch_number succeeded on retry $retry_count"
                else
                    log "INFO" "✅ Batch $batch_number completed successfully"
                fi
            else
                ((retry_count++))
                if [[ $retry_count -lt $MAX_RETRIES ]]; then
                    log "WARN" "❌ Batch $batch_number failed (attempt $retry_count/$MAX_RETRIES), retrying..."
                else
                    log "ERROR" "❌ Batch $batch_number failed after $MAX_RETRIES attempts, giving up"
                fi
            fi
        done
        
        ((batch_number++))
        
        # OPT #7: Sleep conditionnel - ne sleep que s'il reste des batches
        if [[ $batch_number -le ${#batches_array[@]} ]]; then
            sleep 1
        fi
    done
    
    log "INFO" "Completed processing ${#batches_array[@]} batches"
    return 0
}

# Function to execute backfill for a single HEX pubkey (all messages, no time limit)
execute_backfill_websocket_single_hex() {
    local peer="$1"
    local since_timestamp="$2"  # Use 0 for all messages
    local hex_pubkey="$3"
    
    log "INFO" "Executing FULL WebSocket backfill for single HEX: ${hex_pubkey:0:8}..."
    
    # Create the Nostr REQ message for single HEX
    local req_message='["REQ", "backfill_full", {'
    
    # Build kinds array based on INCLUDE_DMS setting
    if [[ "$INCLUDE_DMS" == "true" ]]; then
        req_message+='"kinds": [0, 1, 3, 4, 5, 6, 7, 8, 21, 22, 40, 41, 42, 44, 1063, 1111, 1222, 1244, 1985, 1986, 30001, 30005, 30008, 30009, 10001, 30023, 30024, 30312, 30313, 30315, 30500, 30501, 30502, 30503, 30800, 31900, 31901, 31902, 10000], '  # Include DMs + badge awards (8 - NIP-58) + videos + files + comments + voice messages + user tags + channels + mute + TMDB enrichments + playlists (30005/10001 - NIP-51) + profile badges (30008 - NIP-58) + badge definitions (30009 - NIP-58) + user statuses + DID + ORE + Oracle + workflows + analytics (10000 - NIP-10000, encrypted/non-encrypted determined by content)
    else
        req_message+='"kinds": [0, 1, 3, 5, 6, 7, 8, 21, 22, 40, 41, 42, 44, 1063, 1111, 1222, 1244, 1985, 1986, 30001, 30005, 30008, 30009, 10001, 30023, 30024, 30312, 30313, 30315, 30500, 30501, 30502, 30503, 30800, 31900, 31901, 31902, 10000], '  # Exclude DMs but include badge awards (8 - NIP-58) + videos + files + comments + voice messages + user tags + channels + mute + TMDB enrichments + playlists (30005/10001 - NIP-51) + profile badges (30008 - NIP-58) + badge definitions (30009 - NIP-58) + user statuses + DID + ORE + Oracle + workflows + analytics (10000 - NIP-10000, encrypted/non-encrypted determined by content)
    fi
    
    req_message+="\"since\": $since_timestamp, "
    req_message+='"limit": 50000, '  # Higher limit for full sync
    req_message+="\"authors\": [\"$hex_pubkey\"]"
    req_message+='}]'
    
    log "INFO" "Connecting to WebSocket: $peer for full sync"
    log "DEBUG" "Request: single HEX ${hex_pubkey:0:8}, since=$since_timestamp (0=all messages)"
    
    # OPT #2: Use permanent Python script instead of creating/destroying temp scripts
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local python_script="$SCRIPT_DIR/nostr_websocket_backfill.py"
    local response_file="$HOME/.zen/strfry/backfill-full-response-${RANDOM}.json"
    
    # Execute the Python WebSocket script and capture the number of events
    # Use 60s timeout for full sync
    local python_output
    python_output=$(python3 "$python_script" "$peer" "$req_message" "$response_file" 60 2>/dev/null)
    local python_exit_code=$?
    
    if [[ $python_exit_code -eq 0 ]]; then
        # Extract the number of events from the output
        local events_count=$(echo "$python_output" | grep -o "Collected [0-9]* events" | grep -o "[0-9]*" || echo "0")
        
        log "INFO" "Full sync completed: collected $events_count events for ${hex_pubkey:0:8}"
        
        # Process the response and import events to local strfry
        process_and_import_events "$response_file"
        
        # Clean up response file only (keep script)
        rm -f "$response_file"
        
        # Return success if we got any events
        if [[ $events_count -gt 0 ]]; then
            return 0
        else
            return 1
        fi
    else
        log "ERROR" "Full sync WebSocket backfill failed for ${hex_pubkey:0:8}"
        rm -f "$response_file"
        return 1
    fi
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
        req_message+='"kinds": [0, 1, 3, 4, 5, 6, 7, 8, 21, 22, 40, 41, 42, 44, 1063, 1111, 1222, 1244, 1985, 1986, 30001, 30005, 30008, 30009, 10001, 30023, 30024, 30312, 30313, 30315, 30500, 30501, 30502, 30503, 30800, 31900, 31901, 31902, 10000], '  # Include DMs + badge awards (8 - NIP-58) + videos + files + comments + voice messages + user tags + channels + mute + TMDB enrichments + playlists (30005/10001 - NIP-51) + profile badges (30008 - NIP-58) + badge definitions (30009 - NIP-58) + user statuses + DID + ORE + Oracle + workflows + analytics (10000 - NIP-10000, encrypted/non-encrypted determined by content)
    else
        req_message+='"kinds": [0, 1, 3, 5, 6, 7, 8, 21, 22, 40, 41, 42, 44, 1063, 1111, 1222, 1244, 1985, 1986, 30001, 30005, 30008, 30009, 10001, 30023, 30024, 30312, 30313, 30315, 30500, 30501, 30502, 30503, 30800, 31900, 31901, 31902, 10000], '  # Exclude DMs but include badge awards (8 - NIP-58) + videos + files + comments + voice messages + user tags + channels + mute + TMDB enrichments + playlists (30005/10001 - NIP-51) + profile badges (30008 - NIP-58) + badge definitions (30009 - NIP-58) + user statuses + DID + ORE + Oracle + workflows + analytics (10000 - NIP-10000, encrypted/non-encrypted determined by content)
    fi
    
    req_message+="\"since\": $since_timestamp, "
    req_message+='"limit": 10000'
    
    # Add authors filter if hex_pubkeys are provided
    if [[ -n "$hex_pubkeys_batch" ]]; then
        # Parse authors array from newline-separated batch string with strict validation
        local authors_array=()
        while IFS= read -r author; do
            # Clean whitespace and validate
            author=$(echo "$author" | tr -d '[:space:]')
            # Only add if exactly 64 hex characters (strict validation)
            if [[ -n "$author" && ${#author} -eq 64 && "$author" =~ ^[0-9a-fA-F]{64}$ ]]; then
                authors_array+=("$author")
            elif [[ -n "$author" ]]; then
                log "WARN" "Invalid hex pubkey in batch (length=${#author}): ${author:0:16}... - SKIPPING"
            fi
        done <<< "$hex_pubkeys_batch"
        
        if [[ ${#authors_array[@]} -eq 0 ]]; then
            log "ERROR" "No valid authors in batch after validation"
            return 1
        fi
        
        local authors_json="["
        for i in "${!authors_array[@]}"; do
            if [[ $i -gt 0 ]]; then
                authors_json+=", "
            fi
            authors_json+="\"${authors_array[$i]}\""
        done
        authors_json+="]"
        req_message+=", \"authors\": $authors_json"
        
        log "DEBUG" "Batch contains ${#authors_array[@]} valid authors (filtered from input)"
    fi
    
    req_message+='}]'
    
    log "INFO" "Connecting to WebSocket: $peer"
    log "DEBUG" "Request size: ${#req_message} characters"
    
    # Log a sample of the request for debugging (first 200 chars + last 100 chars)
    if [[ "$VERBOSE" == "true" ]]; then
        log "DEBUG" "Request preview: ${req_message:0:200}...${req_message: -100}"
    fi
    
    # OPT #2: Use permanent Python script instead of creating/destroying temp scripts
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local python_script="$SCRIPT_DIR/nostr_websocket_backfill.py"
    local response_file="$HOME/.zen/strfry/backfill-response-${RANDOM}.json"
    
    # Execute the Python WebSocket script with retry logic
    local python_output
    local python_exit_code=1
    local websocket_retry_count=0
    local MAX_WEBSOCKET_RETRIES=2  # Maximum retry attempts for WebSocket connection
    
    while [[ $websocket_retry_count -le $MAX_WEBSOCKET_RETRIES && $python_exit_code -ne 0 ]]; do
        if [[ $websocket_retry_count -gt 0 ]]; then
            log "INFO" "WebSocket retry attempt $websocket_retry_count/$MAX_WEBSOCKET_RETRIES for $peer"
            sleep $((websocket_retry_count * 3))  # Exponential backoff: 3s, 6s
        fi
        
        python_output=$(python3 "$python_script" "$peer" "$req_message" "$response_file" 30 2>/dev/null)
        python_exit_code=$?
        
        if [[ $python_exit_code -eq 0 ]]; then
            # Extract the number of events from the output
            local events_count=$(echo "$python_output" | grep -o "Collected [0-9]* events" | grep -o "[0-9]*" || echo "0")
            
            if [[ $websocket_retry_count -gt 0 ]]; then
                log "INFO" "✅ WebSocket backfill succeeded on retry $websocket_retry_count"
            else
                log "INFO" "WebSocket backfill completed successfully"
            fi
            log "INFO" "Response saved to: $response_file"
            log "INFO" "Collected $events_count events in this batch"
            
            # Process the response and import events to local strfry
            if process_and_import_events "$response_file"; then
                # Clean up response file only (keep script)
                rm -f "$response_file"
                
                # Return 0 for success (not event count)
                return 0
            else
                log "ERROR" "Failed to process and import events"
                rm -f "$response_file"
                return 1
            fi
        else
            ((websocket_retry_count++))
            if [[ $websocket_retry_count -le $MAX_WEBSOCKET_RETRIES ]]; then
                log "WARN" "❌ WebSocket connection failed (attempt $websocket_retry_count/$MAX_WEBSOCKET_RETRIES), retrying..."
            else
                log "ERROR" "❌ WebSocket backfill failed after $MAX_WEBSOCKET_RETRIES attempts"
            fi
        fi
    done
    
    # If we reach here, all retries failed
    rm -f "$response_file"
    return 1
}

# Function to process video events and extract video metadata
process_video_events() {
    local response_file="$1"
    local video_events_file="${response_file%.json}_videos.json"
    
    if [[ ! -s "$response_file" ]]; then
        return 0
    fi
    
    # Extract video events (kind 21 and 22) to process them separately
    jq -c '.[] | select(.kind == 21 or .kind == 22)' "$response_file" > "$video_events_file" 2>/dev/null
    
    if [[ -s "$video_events_file" ]]; then
        local video_count=$(wc -l < "$video_events_file")
        log "INFO" "Found $video_count video events (kind 21/22) from process_youtube.sh"
        
        # Log sample video events for debugging
        if [[ "$VERBOSE" == "true" && $video_count -gt 0 ]]; then
            log "DEBUG" "Sample video events:"
            head -3 "$video_events_file" | while IFS= read -r video_event; do
                local video_title=$(echo "$video_event" | jq -r '.content // "No title"' 2>/dev/null | head -c 50)
                local video_kind=$(echo "$video_event" | jq -r '.kind' 2>/dev/null)
                local video_url=$(echo "$video_event" | jq -r '.tags[]? | select(.[0] == "url") | .[1]' 2>/dev/null | head -1)
                log "DEBUG" "  Kind $video_kind: $video_title... (URL: ${video_url:0:30}...)"
            done
        fi
    fi
    
    echo "$video_events_file"
}

# Function to process deletion events and extract deleted message IDs
process_deletion_events() {
    local deletion_events_file="$1"
    local deleted_message_ids=()
    
    if [[ ! -s "$deletion_events_file" ]]; then
        echo "${deleted_message_ids[@]}"
        return 0
    fi
    
    log "INFO" "Processing deletion events to identify deleted message IDs..."
    
    # Extract all deleted message IDs from deletion events
    while IFS= read -r deletion_event; do
        if [[ -n "$deletion_event" && "$deletion_event" != "null" ]]; then
            # Extract event IDs from tags (e.g., ["e", "event_id"])
            local deleted_ids=$(echo "$deletion_event" | jq -r '.tags[]? | select(.[0] == "e") | .[1]' 2>/dev/null)
            if [[ -n "$deleted_ids" ]]; then
                while IFS= read -r deleted_id; do
                    if [[ -n "$deleted_id" && "$deleted_id" != "null" ]]; then
                        deleted_message_ids+=("$deleted_id")
                        log "DEBUG" "Marked for deletion: ${deleted_id:0:16}..."
                    fi
                done <<< "$deleted_ids"
            fi
        fi
    done < "$deletion_events_file"
    
    log "INFO" "Identified ${#deleted_message_ids[@]} messages to exclude from import"
    echo "${deleted_message_ids[@]}"
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
    
    # OPT #4: Fusionner appels jq - 1 seul appel au lieu de 3
    read total_events dm_events public_events deletion_events video_events file_events comment_events voice_events tag_events tmdb_events channel_events playlist_events status_events did_events ore_space_events ore_meeting_events oracle_events workflow_events profile_events text_events contact_events repost_events reaction_events blog_events calendar_events analytics_events encrypted_analytics_events badge_award_events profile_badge_events badge_definition_events < <(
        jq -r '[length, ([.[] | select(.kind == 4)] | length), ([.[] | select(.kind != 4)] | length), ([.[] | select(.kind == 5)] | length), ([.[] | select(.kind == 21 or .kind == 22)] | length), ([.[] | select(.kind == 1063)] | length), ([.[] | select(.kind == 1111)] | length), ([.[] | select(.kind == 1222 or .kind == 1244)] | length), ([.[] | select(.kind == 1985)] | length), ([.[] | select(.kind == 1986 or .kind == 30001)] | length), ([.[] | select(.kind == 40 or .kind == 41 or .kind == 42 or .kind == 44)] | length), ([.[] | select(.kind == 30005 or (.kind == 10001 and (.tags[]?[0] == "a" or .tags[]?[0] == "d")))] | length), ([.[] | select(.kind == 30315)] | length), ([.[] | select(.kind == 30800)] | length), ([.[] | select(.kind == 30312)] | length), ([.[] | select(.kind == 30313)] | length), ([.[] | select(.kind >= 30500 and .kind <= 30503)] | length), ([.[] | select(.kind == 31900 or .kind == 31901 or .kind == 31902)] | length), ([.[] | select(.kind == 0)] | length), ([.[] | select(.kind == 1)] | length), ([.[] | select(.kind == 3)] | length), ([.[] | select(.kind == 6)] | length), ([.[] | select(.kind == 7)] | length), ([.[] | select(.kind == 30023)] | length), ([.[] | select(.kind == 30024)] | length), ([.[] | select(.kind == 10000 and (.tags[]? | select(.[0] == "t" and .[1] == "analytics") | length > 0) and (.tags[]? | select(.[0] == "t" and .[1] == "encrypted") | length == 0) and (.content | test("^nip44") | not))] | length), ([.[] | select(.kind == 10000 and ((.tags[]? | select(.[0] == "t" and .[1] == "encrypted") | length > 0) or (.content | test("^nip44"))))] | length), ([.[] | select(.kind == 8)] | length), ([.[] | select(.kind == 30008)] | length), ([.[] | select(.kind == 30009)] | length)] | @tsv' \
        "$response_file" 2>/dev/null || echo "0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0"
    )
    
    log "INFO" "SYNC_STATS: events=$total_events dms=$dm_events public=$public_events deletions=$deletion_events videos=$video_events files=$file_events comments=$comment_events voice=$voice_events tags=$tag_events tmdb=$tmdb_events channels=$channel_events playlists=$playlist_events status=$status_events did=$did_events ore_spaces=$ore_space_events ore_meetings=$ore_meeting_events oracle=$oracle_events workflows=$workflow_events profiles=$profile_events text=$text_events contacts=$contact_events reposts=$repost_events reactions=$reaction_events blog=$blog_events calendar=$calendar_events analytics=$analytics_events encrypted_analytics=$encrypted_analytics_events badge_awards=$badge_award_events profile_badges=$profile_badge_events badge_definitions=$badge_definition_events"
    
    # Create a filtered file without "Hello NOSTR visitor." messages and process deletion events
    local filtered_file="${response_file%.json}_filtered.json"
    local deletion_events_file="${response_file%.json}_deletions.json"
    
    log "INFO" "Processing video events (kind 21/22) from process_youtube.sh..."
    
    # Process video events first (kind 21 and 22)
    local video_events_file
    video_events_file=$(process_video_events "$response_file")
    
    log "INFO" "Processing deletion events (kind 5) to prevent re-importing deleted messages..."
    
    # Extract deletion events (kind 5) to process them separately
    # NOSTR kind 5 events contain tags with "e" entries that reference deleted message IDs
    jq -c '.[] | select(.kind == 5)' "$response_file" > "$deletion_events_file" 2>/dev/null
    
    # Process deletion events to identify deleted message IDs
    local deleted_message_ids=()
    if [[ -s "$deletion_events_file" ]]; then
        log "INFO" "Found $deletion_events deletion events, processing..."
        mapfile -t deleted_message_ids < <(process_deletion_events "$deletion_events_file")
    fi
    
    log "INFO" "Filtering out 'Hello NOSTR visitor.' messages and deleted messages..."
    
    # Filter out events containing "Hello NOSTR visitor." in their content AND deleted messages
    # Use -c for compact output (one JSON object per line)
    if [[ ${#deleted_message_ids[@]} -gt 0 ]]; then
        # Create a jq filter to exclude deleted message IDs
        # This prevents re-importing messages that have been marked for deletion
        local deletion_filter=""
        for deleted_id in "${deleted_message_ids[@]}"; do
            if [[ -n "$deletion_filter" ]]; then
                deletion_filter+=" and .id != \"$deleted_id\""
            else
                deletion_filter=".id != \"$deleted_id\""
            fi
        done
        
        # Apply both filters: exclude "Hello NOSTR visitor." and deleted messages
        # This ensures we don't re-import messages that users have explicitly deleted
        jq -c ".[] | select((.content | test(\"Hello NOSTR visitor.\") | not) and ($deletion_filter))" "$response_file" > "$filtered_file" 2>/dev/null
    else
        # Only filter out "Hello NOSTR visitor." messages
        jq -c '.[] | select(.content | test("Hello NOSTR visitor.") | not)' "$response_file" > "$filtered_file" 2>/dev/null
    fi
    
    # Count events after filtering using jq (more reliable than wc -l)
    local filtered_events=$(jq -s 'length' "$filtered_file" 2>/dev/null || echo "0")
    local removed_events=$((total_events - filtered_events))
    
    log "INFO" "Total events: $total_events"
    log "INFO" "Events after filtering: $filtered_events"
    log "INFO" "Removed events: $removed_events (including 'Hello NOSTR visitor.' messages and deleted messages)"
    
    # Check if we have events to import
    if [[ ! -s "$filtered_file" ]]; then
        log "WARN" "No events remaining after filtering"
        rm -f "$filtered_file" "$deletion_events_file" "$video_events_file"
        return 0
    fi
    
    # Convert filtered events to strfry import format (one event per line)
    local import_file="${response_file%.json}_import.ndjson"
    
    log "INFO" "Converting to strfry import format..."
    # Filtered file is already NDJSON (one JSON object per line), just copy it
    cp "$filtered_file" "$import_file"
    
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
            log "INFO" "SYNC_IMPORT: events=$filtered_events mode=no-verify"
        else
            log "INFO" "SYNC_IMPORT: events=$filtered_events mode=verified"
        fi
    else
        log "ERROR" "❌ Failed to import events to strfry"
        rm -f "$filtered_file" "$import_file" "$deletion_events_file" "$video_events_file"
        return 1
    fi
    
    # Clean up temporary files
    rm -f "$filtered_file" "$import_file" "$deletion_events_file" "$video_events_file"
    
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
    # Reset main log for this run (keep only current sync data)
    echo "# Constellation Backfill Log - $(date '+%Y-%m-%d %H:%M:%S')" > "$BACKFILL_LOG"
    echo "# This log contains only the latest synchronization run" >> "$BACKFILL_LOG"
    echo "" >> "$BACKFILL_LOG"
    
    # Rotate error log before starting (keep historical errors)
    rotate_logs "$BACKFILL_ERROR_LOG" "$MAX_LOG_SIZE_MB" "$MAX_LOG_FILES"
    
    log "INFO" "Starting Astroport constellation backfill process"
    
    # Check if backfill is already running
    if is_backfill_running; then
        log "INFO" "Backfill already running, skipping this execution"
        exit 0
    fi
    
    # Create lock file atomically (prevent race conditions)
    if ! create_lock; then
        log "ERROR" "Failed to acquire lock, another process may be starting"
        exit 1
    fi
    
    log "INFO" "Backfilling $DAYS_BACK day(s) of events"
    
    # OPT #1: Cache HEX pubkeys (appelé 3+ fois dans le script)
    local start_hex_cache=$(date +%s%3N)
    CONSTELLATION_HEX_CACHE=$(get_constellation_hex_pubkeys)
    local end_hex_cache=$(date +%s%3N)
    log "PERF" "get_constellation_hex_pubkeys cached: $((end_hex_cache - start_hex_cache))ms"
    
    # Check if strfry binary exists
    if [[ ! -x "$HOME/.zen/strfry/strfry" ]]; then
        log "ERROR" "strfry binary not found or not executable"
        exit 1
    fi

    # OPT #9: Cache peers discovery (valide 1h)
    local PEERS_CACHE_FILE="$HOME/.zen/tmp/constellation_peers_cache.txt"
    local PEERS_CACHE_AGE=$((60 * 60))  # 1 heure
    local discovered_peers=""
    
    if [[ -f "$PEERS_CACHE_FILE" ]]; then
        cache_age=$(( $(date +%s) - $(stat -c %Y "$PEERS_CACHE_FILE" 2>/dev/null || echo 0) ))
        if [[ $cache_age -lt $PEERS_CACHE_AGE ]]; then
            discovered_peers=$(cat "$PEERS_CACHE_FILE")
            log "INFO" "Using cached peers (${cache_age}s old, valid for $((PEERS_CACHE_AGE - cache_age))s more)"
        fi
    fi
    
    if [[ -z "$discovered_peers" ]]; then
    # Get constellation peers directly from IPNS swarm discovery
    log "INFO" "Discovering constellation peers from IPNS swarm..."
        local start_peers=$(date +%s%3N)
    discovered_peers=$(discover_constellation_peers 2>/dev/null)
        local end_peers=$(date +%s%3N)
        log "PERF" "discover_constellation_peers: $((end_peers - start_peers))ms"
    log "DEBUG" "discover_constellation_peers returned: '$discovered_peers'"
        
        # Save to cache
        mkdir -p "$HOME/.zen/tmp"
        echo "$discovered_peers" > "$PEERS_CACHE_FILE"
        log "INFO" "Saved peers to cache (valid for ${PEERS_CACHE_AGE}s)"
    fi
    
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
        # OPT #1: Use cached HEX pubkeys
        local hex_pubkeys="$CONSTELLATION_HEX_CACHE"
        
        # Check if this is a P2P localhost relay
        if [[ "$peer" =~ ^localhost:([^:]+):(.+)$ ]]; then
            ipfsnodeid="${BASH_REMATCH[1]}"
            local x_strfry_script="${BASH_REMATCH[2]}"
            is_p2p=true
            
            log "INFO" "Processing localhost relay via P2P tunnel: $ipfsnodeid"
            
            # Create P2P tunnel with retry logic
            local tunnel_success=false
            local tunnel_retry_count=0
            local MAX_TUNNEL_RETRIES=2
            
            while [[ $tunnel_retry_count -le $MAX_TUNNEL_RETRIES && "$tunnel_success" == "false" ]]; do
                if [[ $tunnel_retry_count -gt 0 ]]; then
                    log "INFO" "P2P tunnel retry attempt $tunnel_retry_count/$MAX_TUNNEL_RETRIES for $ipfsnodeid"
                    sleep $((tunnel_retry_count * 5))  # Exponential backoff: 5s, 10s
                fi
                
                if create_p2p_tunnel "$ipfsnodeid" "$x_strfry_script"; then
                    # Wait a moment for tunnel to be ready
                    sleep 3
                    
                    # Execute WebSocket backfill via P2P tunnel
                    if execute_p2p_websocket_backfill "$ipfsnodeid" "$since_timestamp" "$hex_pubkeys"; then
                        log "INFO" "✅ P2P WebSocket backfill successful for $ipfsnodeid"
                        backfill_success=true
                        tunnel_success=true
                    else
                        log "ERROR" "❌ P2P WebSocket backfill failed for $ipfsnodeid"
                        ((tunnel_retry_count++))
                        if [[ $tunnel_retry_count -le $MAX_TUNNEL_RETRIES ]]; then
                            log "WARN" "Retrying P2P tunnel for $ipfsnodeid..."
                        fi
                    fi
                else
                    ((tunnel_retry_count++))
                    if [[ $tunnel_retry_count -le $MAX_TUNNEL_RETRIES ]]; then
                        log "WARN" "❌ Failed to create P2P tunnel for $ipfsnodeid (attempt $tunnel_retry_count/$MAX_TUNNEL_RETRIES), retrying..."
                    else
                        log "ERROR" "❌ Failed to create P2P tunnel for $ipfsnodeid after $MAX_TUNNEL_RETRIES attempts"
                    fi
                fi
            done
            
            if [[ "$tunnel_success" == "false" ]]; then
                log "ERROR" "❌ All P2P tunnel attempts failed for $ipfsnodeid, skipping this peer"
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
    log "INFO" "SYNC_PEERS: success=$success_count total=$total_peers"
    
    # Extract profiles from constellation HEX pubkeys if backfill was successful and profiles extraction is enabled
    if [[ $success_count -gt 0 && "$EXTRACT_PROFILES" == "true" ]]; then
        log "INFO" "🔍 Extracting profiles from constellation HEX pubkeys..."
        
        # Get constellation HEX pubkeys
        # OPT #1: Use cached HEX pubkeys
        local hex_pubkeys="$CONSTELLATION_HEX_CACHE"
        
        if [[ -n "$hex_pubkeys" ]]; then
            local hex_count=$(echo "$hex_pubkeys" | wc -l)
            log "INFO" "SYNC_HEX: count=$hex_count"
            
            # Create temporary HEX file
            local hex_file="$HOME/.zen/tmp/constellation_hex_$(date +%s).txt"
            echo "$hex_pubkeys" > "$hex_file"
            
            # Extract profiles using hex_to_profile.sh
            local hex_to_profile_script="$HOME/.zen/Astroport.ONE/tools/nostr_hex_to_profile.sh"
            if [[ -x "$hex_to_profile_script" ]]; then
                log "INFO" "Converting HEX pubkeys to profiles..."
                
                # Run profile extraction with minimal output
                if "$hex_to_profile_script" --file "$hex_file" --format json --no-relays >> "$BACKFILL_LOG" 2>&1; then
                    log "INFO" "✅ Profile extraction completed successfully"
                    
                    # Display profile summary
                    local profiles_file="$HOME/.zen/tmp/coucou/_NIP101.profiles.json"
                    if [[ -f "$profiles_file" ]]; then
                        local total_profiles=$(jq -r 'length' "$profiles_file" 2>/dev/null || echo "0")
                        local profiles_with_names=$(jq -r '[.[] | select(.profile.name != null and .profile.name != "")] | length' "$profiles_file" 2>/dev/null || echo "0")
                        
                        log "INFO" "📊 Constellation Profiles: $total_profiles total, $profiles_with_names with names"
                        
                        # Log sample profiles with names
                        log "INFO" "👥 Sample Constellation Members:"
                        jq -r '.[] | select(.profile.name != null and .profile.name != "") | "  \(.hex[0:8])... - \(.profile.name) (\(.profile.display_name // "no display name"))"' "$profiles_file" 2>/dev/null | head -5 | while read -r profile_line; do
                            log "INFO" "$profile_line"
                        done
                        
                        # Log profiles without names
                        local unnamed_count=$(jq -r '[.[] | select(.profile.name == null or .profile.name == "")] | length' "$profiles_file" 2>/dev/null || echo "0")
                        if [[ $unnamed_count -gt 0 ]]; then
                            log "INFO" "📝 $unnamed_count profiles without names (HEX only)"
                        fi
                        
                        # Show all HEX pubkeys that were processed (even without profiles)
                        log "INFO" "🔑 Processed HEX Pubkeys:"
                        jq -r '.[] | "  \(.hex[0:8])...\(.hex[-8:]) - \(.profile.name // "no name")"' "$profiles_file" 2>/dev/null | head -10 | while read -r hex_line; do
                            log "INFO" "$hex_line"
                        done
                        
                        # OPT #3: Batch strfry scan - 1 seul scan pour tous les HEX au lieu de N scans
                        log "INFO" "🔍 Checking for HEX pubkeys with events in strfry (batch scan)..."
                        local recent_hex_count=0
                        local missing_profiles=()
                        
                        local start_batch_scan=$(date +%s%3N)
                        
                        # Build authors array for single scan
                        local authors_json=$(cat "$hex_file" | jq -R . | jq -s .)
                        
                        # 1 SEUL scan pour tous les HEX (énorme gain de performance)
                        local all_profiles=$(cd "$HOME/.zen/strfry" && ./strfry scan "{
                            \"kinds\": [0],
                            \"authors\": $authors_json
                        }" 2>/dev/null)
                        
                        local end_batch_scan=$(date +%s%3N)
                        log "PERF" "Batch strfry scan for all HEX: $((end_batch_scan - start_batch_scan))ms"
                        
                        # Parse results in memory (much faster than N separate scans)
                        while IFS= read -r hex_pubkey; do
                            if [[ -n "$hex_pubkey" && ${#hex_pubkey} -eq 64 ]]; then
                                # Check if this HEX has a profile in the batch results
                                local profile_event=$(echo "$all_profiles" | jq -c "select(.pubkey == \"$hex_pubkey\")" 2>/dev/null | head -1)
                                
                                if [[ -n "$profile_event" && "$profile_event" != "null" && "$profile_event" != "" ]]; then
                                    # Profile found
                                    ((recent_hex_count++))
                                    
                                    # Try to get profile name
                                    local profile_name=$(echo "$profile_event" | jq -r '.content | fromjson | .name // empty' 2>/dev/null)
                                    local profile_display=$(echo "$profile_event" | jq -r '.content | fromjson | .display_name // empty' 2>/dev/null)
                                    local profile_nip05=$(echo "$profile_event" | jq -r '.content | fromjson | .nip05 // empty' 2>/dev/null)
                                    
                                    if [[ -n "$profile_name" && "$profile_name" != "null" && "$profile_name" != "" ]]; then
                                        log "INFO" "  ✅ ${hex_pubkey:0:8}... Profile: $profile_name"
                                        if [[ -n "$profile_display" && "$profile_display" != "null" ]]; then
                                            log "INFO" "      Display: $profile_display"
                                        fi
                                        if [[ -n "$profile_nip05" && "$profile_nip05" != "null" ]]; then
                                            log "INFO" "      NIP-05: $profile_nip05"
                                        fi
                                    else
                                        log "INFO" "  ✅ ${hex_pubkey:0:8}... Profile event found (no name)"
                                    fi
                                else
                                    # No profile found - need full sync
                                    log "WARN" "  ❌ ${hex_pubkey:0:8}... NO PROFILE FOUND - scheduling full sync"
                                    missing_profiles+=("$hex_pubkey")
                                fi
                            fi
                        done < "$hex_file"
                        
                        log "INFO" "SYNC_PROFILES: found=$recent_hex_count missing=${#missing_profiles[@]}"
                        
                        # OPT #5: Paralléliser full sync - 3 en parallèle au lieu de séquentiel
                        if [[ ${#missing_profiles[@]} -gt 0 ]]; then
                            log "INFO" "🔄 Triggering PARALLEL FULL SYNC (no time limit) for ${#missing_profiles[@]} HEX pubkeys without profiles..."
                            
                            # Get all peers for full sync (reuse cache if available)
                            local discovered_peers
                            if [[ -f "$PEERS_CACHE_FILE" ]]; then
                                discovered_peers=$(cat "$PEERS_CACHE_FILE")
                                log "INFO" "Using cached peers for full sync"
                            else
                            discovered_peers=$(discover_constellation_peers 2>/dev/null)
                            fi
                            
                            if [[ -n "$discovered_peers" ]]; then
                                local peers_array=()
                                mapfile -t peers_array <<< "$discovered_peers"
                                log "INFO" "Found ${#peers_array[@]} peers for full sync"
                                
                                # Extract only routable peers (skip P2P for parallel sync)
                                local routable_peers=()
                                for peer in "${peers_array[@]}"; do
                                    if [[ "$peer" =~ ^routable:(.+)$ ]]; then
                                        routable_peers+=("${BASH_REMATCH[1]}")
                                    fi
                                done
                                
                                if [[ ${#routable_peers[@]} -eq 0 ]]; then
                                    log "WARN" "No routable peers available for parallel full sync"
                                else
                                    log "INFO" "Using ${#routable_peers[@]} routable peers for parallel sync"
                                    
                                    # Parallel sync with max 3 concurrent
                                    local MAX_PARALLEL=3
                                    local parallel_count=0
                                    local sync_success_count=0
                                    
                                    local start_parallel=$(date +%s%3N)
                                    
                                for missing_hex in "${missing_profiles[@]}"; do
                                    log "INFO" "  🔄 FULL SYNC for ${missing_hex:0:8}... (all messages, no time limit)"
                                    
                                        # Launch in background if < MAX_PARALLEL
                                        (
                                    local sync_success=false
                                    
                                            # Try each routable peer until successful
                                            for relay_url in "${routable_peers[@]}"; do
                                                log "INFO" "    📡 Syncing ${missing_hex:0:8} from: $relay_url"
                                        
                                        # Execute full backfill for this HEX (since=0 means all messages)
                                        if execute_backfill_websocket_single_hex "$relay_url" "0" "$missing_hex"; then
                                            log "INFO" "    ✅ Full sync successful for ${missing_hex:0:8}"
                                            sync_success=true
                                            break  # Move to next HEX after successful sync
                                        else
                                            log "WARN" "    ❌ Full sync failed for ${missing_hex:0:8} from $relay_url"
                                        fi
                                    done
                                    
                                    if [[ "$sync_success" == "false" ]]; then
                                        log "ERROR" "  ❌ Failed to sync ${missing_hex:0:8} from all peers"
                                                exit 1
                                            fi
                                            exit 0
                                        ) &
                                        
                                        ((parallel_count++))
                                        
                                        # Wait if we reached MAX_PARALLEL
                                        if [[ $parallel_count -ge $MAX_PARALLEL ]]; then
                                            wait -n  # Wait for one process to finish
                                            [[ $? -eq 0 ]] && ((sync_success_count++))
                                            ((parallel_count--))
                                        fi
                                    done
                                    
                                    # Wait for remaining processes
                                    while [[ $parallel_count -gt 0 ]]; do
                                        wait -n
                                        [[ $? -eq 0 ]] && ((sync_success_count++))
                                        ((parallel_count--))
                                    done
                                    
                                    local end_parallel=$(date +%s%3N)
                                    log "PERF" "Parallel full sync: $((end_parallel - start_parallel))ms for ${#missing_profiles[@]} HEX"
                                    log "INFO" "✅ Parallel full sync completed: $sync_success_count/${#missing_profiles[@]} successful"
                                fi
                            else
                                log "WARN" "No peers available for full sync"
                            fi
                        fi
                    fi
                else
                    log "WARN" "❌ Profile extraction failed, but backfill succeeded"
                fi
            else
                log "WARN" "hex_to_profile.sh not found or not executable, skipping profile extraction"
            fi
            
            # Clean up temporary HEX file
            rm -f "$hex_file"
        else
            log "WARN" "No HEX pubkeys found in constellation"
        fi
    fi
    
    # Send synchronization report to CAPTAINEMAIL
    if [[ -n "$CAPTAINEMAIL" ]]; then
        log "INFO" "📧 Sending synchronization report to $CAPTAINEMAIL..."
        
        # Get the directory of this script
        local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local sync_report_script="$SCRIPT_DIR/sync_report.sh"
        
        if [[ -x "$sync_report_script" ]]; then
            # Run the sync report script in background to avoid blocking
            "$sync_report_script" &
            log "INFO" "📤 Synchronization report queued for delivery"
        else
            log "WARN" "❌ sync_report.sh not found or not executable"
        fi
    else
        log "WARN" "❌ CAPTAINEMAIL not set, skipping report"
    fi
    
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
