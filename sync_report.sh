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
    
    # Extract standardized sync data using simple key=value parsing
    local sync_stats=$(grep "SYNC_STATS:" "$log_file" | tail -1 | sed 's/.*SYNC_STATS: //')
    local sync_hex=$(grep "SYNC_HEX:" "$log_file" | tail -1 | sed 's/.*SYNC_HEX: //')
    local sync_profiles=$(grep "SYNC_PROFILES:" "$log_file" | tail -1 | sed 's/.*SYNC_PROFILES: //')
    local sync_peers=$(grep "SYNC_PEERS:" "$log_file" | tail -1 | sed 's/.*SYNC_PEERS: //')
    local sync_import=$(grep "SYNC_IMPORT:" "$log_file" | tail -1 | sed 's/.*SYNC_IMPORT: //')
    
    # Parse key=value pairs
    local total_events=$(echo "$sync_stats" | grep -o 'events=[0-9]*' | cut -d= -f2)
    local dm_events=$(echo "$sync_stats" | grep -o 'dms=[0-9]*' | cut -d= -f2)
    local public_events=$(echo "$sync_stats" | grep -o 'public=[0-9]*' | cut -d= -f2)
    local deletion_events=$(echo "$sync_stats" | grep -o 'deletions=[0-9]*' | cut -d= -f2)
    local video_events=$(echo "$sync_stats" | grep -o 'videos=[0-9]*' | cut -d= -f2)
    local did_events=$(echo "$sync_stats" | grep -o 'did=[0-9]*' | cut -d= -f2)
    local oracle_events=$(echo "$sync_stats" | grep -o 'oracle=[0-9]*' | cut -d= -f2)
    local ore_events=$(echo "$sync_stats" | grep -o 'ore=[0-9]*' | cut -d= -f2)
    
    local hex_count=$(echo "$sync_hex" | grep -o 'count=[0-9]*' | cut -d= -f2)
    local profiles_found=$(echo "$sync_profiles" | grep -o 'found=[0-9]*' | cut -d= -f2)
    local profiles_missing=$(echo "$sync_profiles" | grep -o 'missing=[0-9]*' | cut -d= -f2)
    local success_peers=$(echo "$sync_peers" | grep -o 'success=[0-9]*' | cut -d= -f2)
    local total_peers=$(echo "$sync_peers" | grep -o 'total=[0-9]*' | cut -d= -f2)
    local imported_events=$(echo "$sync_import" | grep -o 'events=[0-9]*' | cut -d= -f2)
    
    # Set default values if not found
    [[ -z "$total_events" ]] && total_events="0"
    [[ -z "$dm_events" ]] && dm_events="0"
    [[ -z "$public_events" ]] && public_events="0"
    [[ -z "$deletion_events" ]] && deletion_events="0"
    [[ -z "$video_events" ]] && video_events="0"
    [[ -z "$did_events" ]] && did_events="0"
    [[ -z "$oracle_events" ]] && oracle_events="0"
    [[ -z "$ore_events" ]] && ore_events="0"
    [[ -z "$hex_count" ]] && hex_count="0"
    [[ -z "$profiles_found" ]] && profiles_found="0"
    [[ -z "$profiles_missing" ]] && profiles_missing="0"
    [[ -z "$success_peers" ]] && success_peers="0"
    [[ -z "$total_peers" ]] && total_peers="0"
    [[ -z "$imported_events" ]] && imported_events="0"
    
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
DM_EVENTS="$dm_events"
PUBLIC_EVENTS="$public_events"
DELETION_EVENTS="$deletion_events"
VIDEO_EVENTS="$video_events"
DID_EVENTS="$did_events"
ORACLE_EVENTS="$oracle_events"
ORE_EVENTS="$ore_events"
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
    
    # Calculate message type percentages
    local total_message_events=0
    local public_percent="0"
    local dm_percent="0"
    local video_percent="0"
    local deletion_percent="0"
    local did_percent="0"
    local oracle_percent="0"
    local ore_percent="0"
    
    if [[ -n "$PUBLIC_EVENTS" && "$PUBLIC_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + PUBLIC_EVENTS))
    fi
    if [[ -n "$DM_EVENTS" && "$DM_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + DM_EVENTS))
    fi
    if [[ -n "$VIDEO_EVENTS" && "$VIDEO_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + VIDEO_EVENTS))
    fi
    if [[ -n "$DELETION_EVENTS" && "$DELETION_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + DELETION_EVENTS))
    fi
    if [[ -n "$DID_EVENTS" && "$DID_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + DID_EVENTS))
    fi
    if [[ -n "$ORACLE_EVENTS" && "$ORACLE_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + ORACLE_EVENTS))
    fi
    if [[ -n "$ORE_EVENTS" && "$ORE_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + ORE_EVENTS))
    fi
    
    if [[ $total_message_events -gt 0 ]]; then
        public_percent=$(echo "scale=1; $PUBLIC_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        dm_percent=$(echo "scale=1; $DM_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        video_percent=$(echo "scale=1; $VIDEO_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        deletion_percent=$(echo "scale=1; $DELETION_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        did_percent=$(echo "scale=1; $DID_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        oracle_percent=$(echo "scale=1; $ORACLE_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        ore_percent=$(echo "scale=1; $ORE_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Determine report type based on activity
    local report_type="Sync Report"
    if [[ "$IMPORTED_EVENTS" -gt 0 && "$BATCH_FAILURES" -gt 0 ]]; then
        report_type="Sync Report (Activity + Errors)"
    elif [[ "$IMPORTED_EVENTS" -gt 0 ]]; then
        report_type="Sync Report (Activity)"
    elif [[ "$BATCH_FAILURES" -gt 0 || "$WEBSOCKET_FAILURES" -gt 0 || "$TUNNEL_FAILURES" -gt 0 ]]; then
        report_type="Sync Report (Errors)"
    fi
    
    # Generate HTML report
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>UPlanet Constellation $report_type</title>
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
        .message-types { background: #e3f2fd; }
        .video-events { background: #f3e5f5; }
        .dm-events { background: #e8f5e8; }
        .deletion-events { background: #ffebee; }
        .did-events { background: #fff3e0; }
        .oracle-events { background: #e8f5e9; }
        .ore-events { background: #e3f2fd; }
        .footer { text-align: center; margin-top: 20px; color: #7f8c8d; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌍 UPlanet Constellation $report_type</h1>
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
            <div class="stat-card message-types">
                <div class="stat-value">$PUBLIC_EVENTS</div>
                <div class="stat-label">Public Messages ($public_percent%)</div>
            </div>
            <div class="stat-card dm-events">
                <div class="stat-value">$DM_EVENTS</div>
                <div class="stat-label">Direct Messages ($dm_percent%)</div>
            </div>
            <div class="stat-card video-events">
                <div class="stat-value">$VIDEO_EVENTS</div>
                <div class="stat-label">Video Events ($video_percent%)</div>
            </div>
            <div class="stat-card deletion-events">
                <div class="stat-value">$DELETION_EVENTS</div>
                <div class="stat-label">Deletion Events ($deletion_percent%)</div>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card did-events">
                <div class="stat-value">$DID_EVENTS</div>
                <div class="stat-label">DID Documents ($did_percent%)</div>
            </div>
            <div class="stat-card oracle-events">
                <div class="stat-value">$ORACLE_EVENTS</div>
                <div class="stat-label">Oracle Permits ($oracle_percent%)</div>
            </div>
            <div class="stat-card ore-events">
                <div class="stat-value">$ORE_EVENTS</div>
                <div class="stat-label">ORE Contracts ($ore_percent%)</div>
            </div>
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
        </div>
        
        <div class="stats-grid">
            <div class="stat-card retry-info">
                <div class="stat-value">$WEBSOCKET_RETRIES</div>
                <div class="stat-label">WebSocket Retries</div>
            </div>
            <div class="stat-card retry-info">
                <div class="stat-value">$TUNNEL_RETRIES</div>
                <div class="stat-label">Tunnel Retries</div>
            </div>
            <div class="stat-card performance">
                <div class="stat-value">$HEX_CACHE_TIME</div>
                <div class="stat-label">HEX Cache Time</div>
            </div>
            <div class="stat-card performance">
                <div class="stat-value">$PEERS_TIME</div>
                <div class="stat-label">Peers Discovery</div>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card performance">
                <div class="stat-value">$BATCH_SCAN_TIME</div>
                <div class="stat-label">Batch Scan Time</div>
            </div>
            <div class="stat-card performance">
                <div class="stat-value">$PARALLEL_SYNC_TIME</div>
                <div class="stat-label">Parallel Sync Time</div>
            </div>
            <div class="stat-card error-info">
                <div class="stat-value error">$BATCH_FAILURES</div>
                <div class="stat-label">Batch Failures</div>
            </div>
            <div class="stat-card error-info">
                <div class="stat-value error">$WEBSOCKET_FAILURES</div>
                <div class="stat-label">WebSocket Failures</div>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card error-info">
                <div class="stat-value error">$TUNNEL_FAILURES</div>
                <div class="stat-label">Tunnel Failures</div>
            </div>
            <div class="stat-card retry-info">
                <div class="stat-value">$TUNNEL_RETRIES</div>
                <div class="stat-label">Tunnel Retries</div>
            </div>
        </div>
        
        <div style="margin-top: 30px; padding: 20px; background: #f8f9fa; border-radius: 8px; border-left: 4px solid #3498db;">
            <h3 style="margin-top: 0; color: #2c3e50;">📊 Message Type Summary</h3>
            <p style="margin: 10px 0; color: #555;">
                <strong>Total Message Events:</strong> $total_message_events
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Public Messages:</strong> $PUBLIC_EVENTS ($public_percent%) - Notes, articles, and public communications
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Direct Messages:</strong> $DM_EVENTS ($dm_percent%) - Private conversations between users
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Video Events:</strong> $VIDEO_EVENTS ($video_percent%) - YouTube videos (kind 21/22) from process_youtube.sh
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Deletion Events:</strong> $DELETION_EVENTS ($deletion_percent%) - Messages marked for deletion (kind 5)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>DID Documents:</strong> $DID_EVENTS ($did_percent%) - Identity documents (kind 30311) from did_manager_nostr.sh
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Oracle Permits:</strong> $ORACLE_EVENTS ($oracle_percent%) - Permit system events (kinds 30500-30503): definitions, requests, attestations, credentials
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>ORE Contracts:</strong> $ORE_EVENTS ($ore_percent%) - Environmental obligations (kinds 30400-30402): contracts, validations, rewards
            </p>
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

# Function to check if report should be sent
should_send_report() {
    local stats="$1"
    
    # Source the statistics
    eval "$stats"
    
    # Check if there are imported events (synchronized messages)
    local has_imported_events=false
    if [[ -n "$IMPORTED_EVENTS" && "$IMPORTED_EVENTS" -gt 0 ]]; then
        has_imported_events=true
    fi
    
    # Check if there are any errors
    local has_errors=false
    if [[ -n "$BATCH_FAILURES" && "$BATCH_FAILURES" -gt 0 ]] || \
       [[ -n "$WEBSOCKET_FAILURES" && "$WEBSOCKET_FAILURES" -gt 0 ]] || \
       [[ -n "$TUNNEL_FAILURES" && "$TUNNEL_FAILURES" -gt 0 ]]; then
        has_errors=true
    fi
    
    # Send report only if there are synchronized messages or errors
    if [[ "$has_imported_events" == true || "$has_errors" == true ]]; then
        return 0
    else
        return 1
    fi
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
    
    # Check if report should be sent
    if ! should_send_report "$stats"; then
        echo "ℹ️  No synchronized messages or errors detected - skipping report"
        return 0
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
        "$HOME/.zen/Astroport.ONE/tools/mailjet.sh" --expire 1h "$captain_email" "$temp_html" "$report_title"
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
