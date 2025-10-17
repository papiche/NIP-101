#!/bin/bash
# Constellation Synchronization Report Script
# Sends detailed synchronization reports via email to CAPTAINEMAIL

## SET ASTROPORT ENVIRONNEMENT
[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "SYNC REPORT NEEDS ~/.zen/Astroport.ONE" \
    && exit 1

source ~/.zen/Astroport.ONE/tools/my.sh

# Configuration
REPORT_LOG="$HOME/.zen/strfry/constellation-backfill.log"
REPORT_ERROR_LOG="$HOME/.zen/strfry/constellation-backfill.error.log"
SYNC_PID_FILE="$HOME/.zen/strfry/constellation-backfill.pid"
LOCK_FILE="$HOME/.zen/strfry/constellation-backfill.lock"

# Function to extract sync statistics from log
extract_sync_stats() {
    local log_file="$1"
    
    if [[ ! -f "$log_file" ]]; then
        echo "❌ Log file not found: $log_file"
        return 1
    fi
    
    # Note: Main log contains ONLY the latest sync run (reset at each execution)
    # Extract key statistics from the log (no need for tail -1 since we have a clean log)
    local start_time=$(grep "Starting Astroport constellation backfill process" "$log_file" | head -1 | sed 's/.*\[\([0-9-]* [0-9:]*\)\].*/\1/')
    local end_time=$(grep "Backfill process completed" "$log_file" | head -1 | sed 's/.*\[\([0-9-]* [0-9:]*\)\].*/\1/')
    
    # Count peers processed
    local total_peers=$(grep "Found.*peers from swarm" "$log_file" | head -1 | grep -o '[0-9]*' | head -1)
    local success_peers=$(grep "Success:" "$log_file" | head -1 | grep -o '[0-9]*' | head -1)
    
    # Count events processed
    local total_events=$(grep "Total events collected across all batches:" "$log_file" | head -1 | grep -o '[0-9]*' | head -1)
    local imported_events=$(grep "Successfully imported.*events to strfry" "$log_file" | tail -1 | grep -o '[0-9]*' | head -1)
    
    # Count HEX pubkeys processed
    local hex_count=$(grep "Found.*HEX pubkeys in constellation" "$log_file" | head -1 | grep -o '[0-9]*' | head -1)
    
    # Count profiles extracted
    local profiles_found=$(grep "Found.*HEX pubkeys with profiles" "$log_file" | head -1 | grep -o '[0-9]*' | head -1)
    local profiles_missing=$(grep "Found.*HEX pubkeys WITHOUT profiles" "$log_file" | head -1 | grep -o '[0-9]*' | head -1)
    
    # Count retry attempts
    local batch_retries=$(grep "Retry attempt.*for batch" "$log_file" | wc -l)
    local websocket_retries=$(grep "WebSocket retry attempt" "$log_file" | wc -l)
    local tunnel_retries=$(grep "P2P tunnel retry attempt" "$log_file" | wc -l)
    
    # Count errors
    local batch_failures=$(grep "Batch.*failed" "$log_file" | wc -l)
    local websocket_failures=$(grep "WebSocket.*failed" "$log_file" | wc -l)
    local tunnel_failures=$(grep "Failed to create P2P tunnel" "$log_file" | wc -l)
    
    # Performance metrics
    local hex_cache_time=$(grep "get_constellation_hex_pubkeys cached:" "$log_file" | head -1 | grep -o '[0-9]*ms' | head -1)
    local peers_time=$(grep "discover_constellation_peers:" "$log_file" | head -1 | grep -o '[0-9]*ms' | head -1)
    local batch_scan_time=$(grep "Batch strfry scan for all HEX:" "$log_file" | head -1 | grep -o '[0-9]*ms' | head -1)
    local parallel_sync_time=$(grep "Parallel full sync:" "$log_file" | head -1 | grep -o '[0-9]*ms' | head -1)
    
    # Output statistics
    cat << EOF
SYNC_START_TIME="$start_time"
SYNC_END_TIME="$end_time"
TOTAL_PEERS="$total_peers"
SUCCESS_PEERS="$success_peers"
TOTAL_EVENTS="$total_events"
IMPORTED_EVENTS="$imported_events"
HEX_PUBKEYS="$hex_count"
PROFILES_FOUND="$profiles_found"
PROFILES_MISSING="$profiles_missing"
BATCH_RETRIES="$batch_retries"
WEBSOCKET_RETRIES="$websocket_retries"
TUNNEL_RETRIES="$tunnel_retries"
BATCH_FAILURES="$batch_failures"
WEBSOCKET_FAILURES="$websocket_failures"
TUNNEL_FAILURES="$tunnel_failures"
HEX_CACHE_TIME="$hex_cache_time"
PEERS_TIME="$peers_time"
BATCH_SCAN_TIME="$batch_scan_time"
PARALLEL_SYNC_TIME="$parallel_sync_time"
EOF
}

# Function to generate HTML report
generate_html_report() {
    local stats="$1"
    local node_info="$2"
    
    # Source the statistics
    eval "$stats"
    
    # Calculate success rate
    local success_rate="0"
    if [[ -n "$TOTAL_PEERS" && "$TOTAL_PEERS" -gt 0 ]]; then
        success_rate=$(echo "scale=1; $SUCCESS_PEERS * 100 / $TOTAL_PEERS" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Calculate duration
    local duration="Unknown"
    if [[ -n "$SYNC_START_TIME" && -n "$SYNC_END_TIME" ]]; then
        local start_epoch=$(date -d "$SYNC_START_TIME" +%s 2>/dev/null || echo "0")
        local end_epoch=$(date -d "$SYNC_END_TIME" +%s 2>/dev/null || echo "0")
        if [[ $start_epoch -gt 0 && $end_epoch -gt 0 ]]; then
            local duration_seconds=$((end_epoch - start_epoch))
            duration="${duration_seconds}s"
        fi
    fi
    
    # Generate HTML report
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>UPlanet Constellation Sync Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; margin-bottom: 20px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .stat-card { background: #ecf0f1; padding: 15px; border-radius: 8px; text-align: center; }
        .stat-value { font-size: 24px; font-weight: bold; color: #2c3e50; }
        .stat-label { font-size: 12px; color: #7f8c8d; text-transform: uppercase; }
        .success { color: #27ae60; }
        .warning { color: #f39c12; }
        .error { color: #e74c3c; }
        .performance { background: #e8f5e8; }
        .retry-info { background: #fff3cd; }
        .error-info { background: #f8d7da; }
        .footer { text-align: center; margin-top: 20px; color: #7f8c8d; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌍 UPlanet Constellation Sync Report</h1>
            <p>Node: $node_info</p>
            <p>Sync Time: $SYNC_START_TIME → $SYNC_END_TIME ($duration)</p>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-value success">$SUCCESS_PEERS/$TOTAL_PEERS</div>
                <div class="stat-label">Peers Success Rate</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$TOTAL_EVENTS</div>
                <div class="stat-label">Events Collected</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$IMPORTED_EVENTS</div>
                <div class="stat-label">Events Imported</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$HEX_PUBKEYS</div>
                <div class="stat-label">HEX Pubkeys</div>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card performance">
                <div class="stat-value">$PROFILES_FOUND</div>
                <div class="stat-label">Profiles Found</div>
            </div>
            <div class="stat-card performance">
                <div class="stat-value">$PROFILES_MISSING</div>
                <div class="stat-label">Profiles Missing</div>
            </div>
            <div class="stat-card retry-info">
                <div class="stat-value">$BATCH_RETRIES</div>
                <div class="stat-label">Batch Retries</div>
            </div>
            <div class="stat-card retry-info">
                <div class="stat-value">$WEBSOCKET_RETRIES</div>
                <div class="stat-label">WebSocket Retries</div>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card performance">
                <div class="stat-value">$HEX_CACHE_TIME</div>
                <div class="stat-label">HEX Cache Time</div>
            </div>
            <div class="stat-card performance">
                <div class="stat-value">$PEERS_TIME</div>
                <div class="stat-label">Peers Discovery</div>
            </div>
            <div class="stat-card performance">
                <div class="stat-value">$BATCH_SCAN_TIME</div>
                <div class="stat-label">Batch Scan Time</div>
            </div>
            <div class="stat-card performance">
                <div class="stat-value">$PARALLEL_SYNC_TIME</div>
                <div class="stat-label">Parallel Sync Time</div>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card error-info">
                <div class="stat-value error">$BATCH_FAILURES</div>
                <div class="stat-label">Batch Failures</div>
            </div>
            <div class="stat-card error-info">
                <div class="stat-value error">$WEBSOCKET_FAILURES</div>
                <div class="stat-label">WebSocket Failures</div>
            </div>
            <div class="stat-card error-info">
                <div class="stat-value error">$TUNNEL_FAILURES</div>
                <div class="stat-label">Tunnel Failures</div>
            </div>
            <div class="stat-card retry-info">
                <div class="stat-value">$TUNNEL_RETRIES</div>
                <div class="stat-label">Tunnel Retries</div>
            </div>
        </div>
        
        <div class="footer">
            <p>Generated by UPlanet Constellation Sync System</p>
            <p>Timestamp: $(date '+%Y-%m-%d %H:%M:%S')</p>
            <p style="font-size: 10px; color: #95a5a6; margin-top: 10px;">
                Main log contains only latest run data • Error log keeps historical errors with rotation
            </p>
        </div>
    </div>
</body>
</html>
EOF
}

# Function to send email report
send_sync_report() {
    local captain_email="$1"
    
    if [[ -z "$captain_email" ]]; then
        echo "❌ CAPTAINEMAIL not set"
        return 1
    fi
    
    echo "📧 Generating synchronization report for $captain_email..."
    
    # Extract statistics from log
    local stats=$(extract_sync_stats "$REPORT_LOG")
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to extract sync statistics"
        return 1
    fi
    
    # Get node information
    local node_info="Node: $IPFSNODEID"
    if [[ -n "$CAPTAINEMAIL" ]]; then
        node_info="Captain: $CAPTAINEMAIL | Node: $IPFSNODEID"
    fi
    
    # Generate HTML report
    local html_report=$(generate_html_report "$stats" "$node_info")
    
    # Create temporary HTML file
    local temp_html="/tmp/sync_report_$(date +%s).html"
    echo "$html_report" > "$temp_html"
    
    # Send email using mailjet.sh
    echo "📤 Sending synchronization report..."
    
    # Create a meaningful title for the report
    local report_title="Constellation Sync Report - $(date '+%Y-%m-%d %H:%M')"
    
    # Use the existing mailjet.sh script to send the report
    if [[ -x "$HOME/.zen/Astroport.ONE/tools/mailjet.sh" ]]; then
        "$HOME/.zen/Astroport.ONE/tools/mailjet.sh" --expire 24h "$captain_email" "$temp_html" "$report_title"
        local mail_exit_code=$?
        
        # Clean up temporary file
        rm -f "$temp_html"
        
        if [[ $mail_exit_code -eq 0 ]]; then
            echo "✅ Synchronization report sent successfully to $captain_email"
            return 0
        else
            echo "❌ Failed to send synchronization report"
            return 1
        fi
    else
        echo "❌ mailjet.sh not found or not executable"
        rm -f "$temp_html"
        return 1
    fi
}

# Main execution
main() {
    echo "🔍 Constellation Sync Report Generator"
    echo "======================================"
    
    # Check if CAPTAINEMAIL is set
    if [[ -z "$CAPTAINEMAIL" ]]; then
        echo "❌ CAPTAINEMAIL not set in environment"
        exit 1
    fi
    
    # Check if log file exists
    if [[ ! -f "$REPORT_LOG" ]]; then
        echo "❌ Sync log file not found: $REPORT_LOG"
        exit 1
    fi
    
    # Send the report
    send_sync_report "$CAPTAINEMAIL"
}

# Run main function
main "$@"
