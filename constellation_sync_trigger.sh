#!/bin/bash
# Constellation Sync Trigger for _12345.sh
# This script is called by _12345.sh to trigger constellation synchronization
# after 12:00 (noon) to sync messages since yesterday noon

## SET ASTROPORT ENVIRONNEMENT
[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "CONSTELLATION SYNC TRIGGER NEEDS ~/.zen/Astroport.ONE" \
    && exit 1

source ~/.zen/Astroport.ONE/tools/my.sh

# Configuration
SCRIPT_DIR="$HOME/.zen/workspace/NIP-101"
BACKFILL_SCRIPT="$SCRIPT_DIR/backfill_constellation.sh"
LOG_FILE="$HOME/.zen/strfry/constellation-trigger.log"
LOCK_FILE="$HOME/.zen/strfry/constellation-sync.lock"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Also log to console if running interactively
    if [[ -t 0 ]]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# Function to check if sync is already running
is_sync_running() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$pid" && -d "/proc/$pid" ]]; then
            return 0  # Sync is running
        else
            # Remove stale lock file
            rm -f "$LOCK_FILE"
        fi
    fi
    return 1  # No sync running
}

# Function to create lock file
create_lock() {
    echo $$ > "$LOCK_FILE"
    log "INFO" "Created lock file with PID $$"
}

# Function to remove lock file
remove_lock() {
    rm -f "$LOCK_FILE"
    log "INFO" "Removed lock file"
}

# Function to check if it's time to sync
should_sync() {
    local current_hour=$(date +%H)
    local current_minute=$(date +%M)
    
    # Sync after 12:00 (noon)
    if [[ $current_hour -ge 12 ]]; then
        # Check if we already synced today
        local last_sync_file="$HOME/.zen/strfry/last_constellation_sync"
        local today=$(date +%Y%m%d)
        
        if [[ ! -f "$last_sync_file" ]] || [[ "$(cat "$last_sync_file")" != "$today" ]]; then
            return 0  # Should sync
        fi
    fi
    
    return 1  # Should not sync
}

# Function to mark sync as completed
mark_sync_completed() {
    local today=$(date +%Y%m%d)
    echo "$today" > "$HOME/.zen/strfry/last_constellation_sync"
    log "INFO" "Marked sync as completed for today: $today"
}

# Function to trigger constellation sync
trigger_constellation_sync() {
    log "INFO" "Triggering constellation synchronization..."
    
    # Check if backfill script exists
    if [[ ! -x "$BACKFILL_SCRIPT" ]]; then
        log "ERROR" "Backfill script not found or not executable: $BACKFILL_SCRIPT"
        return 1
    fi
    
    # Create lock file
    create_lock
    
    # Trap to ensure lock file is removed on exit
    trap remove_lock EXIT
    
    # Calculate days since yesterday noon
    local current_time=$(date +%s)
    local yesterday_noon=$(date -d "yesterday 12:00:00" +%s)
    local days_diff=$(( (current_time - yesterday_noon) / 86400 ))
    
    # Ensure at least 1 day
    [[ $days_diff -lt 1 ]] && days_diff=1
    
    log "INFO" "Starting backfill for $days_diff day(s) since yesterday noon"
    
    # Execute backfill in background
    cd "$SCRIPT_DIR"
    "$BACKFILL_SCRIPT" --days "$days_diff" --verbose >> "$LOG_FILE" 2>&1 &
    local backfill_pid=$!
    
    log "INFO" "Backfill started with PID: $backfill_pid"
    
    # Wait for completion with timeout (30 minutes)
    local elapsed=0
    local timeout=1800  # 30 minutes
    
    while kill -0 "$backfill_pid" 2>/dev/null && [[ $elapsed -lt $timeout ]]; do
        sleep 30
        elapsed=$((elapsed + 30))
        
        if [[ $((elapsed % 300)) -eq 0 ]]; then
            log "INFO" "Backfill in progress... (${elapsed}s elapsed)"
        fi
    done
    
    # Check if process completed
    if kill -0 "$backfill_pid" 2>/dev/null; then
        log "WARN" "Backfill timeout after 30 minutes, force killing"
        kill -9 "$backfill_pid" 2>/dev/null
        return 1
    else
        log "INFO" "Backfill completed successfully"
        mark_sync_completed
        return 0
    fi
}

# Main execution
main() {
    log "INFO" "Constellation sync trigger started"
    
    # Check if we should sync
    if ! should_sync; then
        log "INFO" "Not time to sync yet or already synced today"
        exit 0
    fi
    
    # Check if sync is already running
    if is_sync_running; then
        log "INFO" "Constellation sync already running, skipping"
        exit 0
    fi
    
    # Trigger the sync
    if trigger_constellation_sync; then
        log "INFO" "Constellation sync completed successfully"
        exit 0
    else
        log "ERROR" "Constellation sync failed"
        exit 1
    fi
}

# Run main function
main "$@"
