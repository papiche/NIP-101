#!/bin/bash
# Constellation Sync Trigger for _12345.sh
# This script is called by _12345.sh to trigger constellation synchronization
# every hour to ensure N² synchronization (friends of friends are friends)
# The 1-day backfill window catches any missed events, and strfry handles duplicates automatically

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
    # Synchronize every hour (at the rhythm of _12345.sh)
    # No time restriction - sync whenever triggered
    # The 1-day window ensures we catch any missed events
    # strfry automatically handles duplicates, so it's safe to sync frequently
    return 0  # Always should sync when triggered
}

# Function to mark sync as completed
mark_sync_completed() {
    local timestamp=$(date +%s)
    echo "$timestamp" > "$HOME/.zen/strfry/last_constellation_sync"
    log "INFO" "Marked sync as completed at: $(date '+%Y-%m-%d %H:%M:%S')"
}

# Function to generate HTML email report from log
generate_email_report() {
    local log_content="$1"
    local status="$2"
    local sync_date=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Extract statistics from log
    local total_peers=$(echo "$log_content" | grep -c "Processing peer:" || echo "0")
    local successful_backfills=$(echo "$log_content" | grep -c "backfill successful" || echo "0")
    local failed_backfills=$(echo "$log_content" | grep -c "backfill failed" || echo "0")
    local total_events=$(echo "$log_content" | grep -oP "Collected \K[0-9]+" | awk '{s+=$1} END {print s}' || echo "0")
    local hex_count=$(echo "$log_content" | grep -oP "Targeting \K[0-9]+" | head -1 || echo "0")
    
    # Status icon and color
    local status_icon="✅"
    local status_color="#28a745"
    local status_text="SUCCESS"
    
    if [[ "$status" != "success" ]]; then
        status_icon="❌"
        status_color="#dc3545"
        status_text="FAILED"
    fi
    
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Constellation Sync Report - $sync_date</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f5f5f5;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: white;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 28px;
        }
        .header p {
            margin: 10px 0 0;
            opacity: 0.9;
        }
        .status {
            background-color: ${status_color};
            color: white;
            padding: 20px;
            text-align: center;
            font-size: 24px;
            font-weight: bold;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            padding: 30px;
        }
        .stat-card {
            background-color: #f8f9fa;
            border-left: 4px solid #667eea;
            padding: 15px;
            border-radius: 5px;
        }
        .stat-card h3 {
            margin: 0 0 10px;
            color: #495057;
            font-size: 14px;
            text-transform: uppercase;
        }
        .stat-card p {
            margin: 0;
            font-size: 28px;
            font-weight: bold;
            color: #212529;
        }
        .log-section {
            padding: 30px;
            border-top: 1px solid #dee2e6;
        }
        .log-section h2 {
            margin-top: 0;
            color: #495057;
        }
        .log-content {
            background-color: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 5px;
            padding: 15px;
            max-height: 400px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            line-height: 1.6;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        .footer {
            background-color: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #6c757d;
            border-top: 1px solid #dee2e6;
        }
        .footer a {
            color: #667eea;
            text-decoration: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 Constellation Sync Report</h1>
            <p>N² Nostr Relay Synchronization</p>
            <p>${sync_date}</p>
        </div>
        
        <div class="status">
            ${status_icon} ${status_text}
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <h3>Total Peers</h3>
                <p>${total_peers}</p>
            </div>
            <div class="stat-card">
                <h3>Successful</h3>
                <p style="color: #28a745;">${successful_backfills}</p>
            </div>
            <div class="stat-card">
                <h3>Failed</h3>
                <p style="color: #dc3545;">${failed_backfills}</p>
            </div>
            <div class="stat-card">
                <h3>Events Collected</h3>
                <p>${total_events}</p>
            </div>
            <div class="stat-card">
                <h3>HEX Pubkeys</h3>
                <p>${hex_count}</p>
            </div>
        </div>
        
        <div class="log-section">
            <h2>📋 Detailed Log</h2>
            <div class="log-content">$(echo "$log_content" | tail -n 200)</div>
        </div>
        
        <div class="footer">
            <p>🚀 Astroport.ONE - UPlanet Constellation</p>
            <p><a href="https://github.com/papiche/Astroport.ONE">Learn more about the constellation network</a></p>
        </div>
    </div>
</body>
</html>
EOF
}

# Function to send email report via mailjet
send_email_report() {
    local status="$1"
    local log_file="$LOG_FILE"
    
    # Check if CAPTAINEMAIL is defined
    if [[ -z "$CAPTAINEMAIL" ]]; then
        log "WARN" "CAPTAINEMAIL not defined, skipping email report"
        return 1
    fi
    
    # Check if mailjet.sh exists
    local mailjet_script="$HOME/.zen/Astroport.ONE/tools/mailjet.sh"
    if [[ ! -x "$mailjet_script" ]]; then
        log "WARN" "mailjet.sh not found or not executable, skipping email report"
        return 1
    fi
    
    # Generate HTML report
    local report_file="$HOME/.zen/tmp/constellation_sync_report_$(date +%Y%m%d_%H%M%S).html"
    local log_content=$(tail -n 500 "$log_file" 2>/dev/null || echo "No log content available")
    
    generate_email_report "$log_content" "$status" > "$report_file"
    
    # Email subject based on status
    local subject
    if [[ "$status" == "success" ]]; then
        subject="✅ Constellation Sync Report - $(date '+%H:%M')"
    else
        subject="❌ Constellation Sync Failed - $(date '+%H:%M')"
    fi
    
    # Send email
    log "INFO" "Sending email report to $CAPTAINEMAIL"
    if "$mailjet_script" "$CAPTAINEMAIL" "$report_file" "$subject" 2>/dev/null; then
        log "INFO" "Email report sent successfully to $CAPTAINEMAIL"
        # Clean up report file after sending
        rm -f "$report_file"
        return 0
    else
        log "ERROR" "Failed to send email report to $CAPTAINEMAIL"
        return 1
    fi
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
    
    # Always backfill 1 day to ensure we catch any missed events
    # strfry handles duplicates automatically, so it's safe to overlap
    local days_diff=1
    
    log "INFO" "Starting hourly backfill for $days_diff day(s) - N² constellation sync"
    
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
        
        # Send failure email report
        send_email_report "failed"
        
        return 1
    else
        log "INFO" "Backfill completed successfully"
        mark_sync_completed
        
        # Send success email report
        send_email_report "success"
        
        return 0
    fi
}

# Main execution
main() {
    log "INFO" "Constellation sync trigger started"
    
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
        # Email report already sent by trigger_constellation_sync
        exit 1
    fi
}

# Run main function
main "$@"
