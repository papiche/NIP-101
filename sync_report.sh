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
    # Use tail -1 to get last match and tr -d '\n' to remove newlines
    local total_events=$(echo "$sync_stats" | grep -o 'events=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local dm_events=$(echo "$sync_stats" | grep -o 'dms=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local public_events=$(echo "$sync_stats" | grep -o 'public=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local deletion_events=$(echo "$sync_stats" | grep -o 'deletions=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local video_events=$(echo "$sync_stats" | grep -o 'videos=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local file_events=$(echo "$sync_stats" | grep -o 'files=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local comment_events=$(echo "$sync_stats" | grep -o 'comments=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local voice_events=$(echo "$sync_stats" | grep -o 'voice=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local tag_events=$(echo "$sync_stats" | grep -o 'tags=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local tmdb_events=$(echo "$sync_stats" | grep -o 'tmdb=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local channel_events=$(echo "$sync_stats" | grep -o 'channels=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local playlist_events=$(echo "$sync_stats" | grep -o 'playlists=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local status_events=$(echo "$sync_stats" | grep -o 'status=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local did_events=$(echo "$sync_stats" | grep -o 'did=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local oracle_events=$(echo "$sync_stats" | grep -o 'oracle=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local ore_events=$(echo "$sync_stats" | grep -o 'ore_spaces=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local economic_health_events=$(echo "$sync_stats" | grep -o 'economic_health=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local workflow_events=$(echo "$sync_stats" | grep -o 'workflows=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local profile_events=$(echo "$sync_stats" | grep -o 'profiles=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local text_events=$(echo "$sync_stats" | grep -o 'text=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local contact_events=$(echo "$sync_stats" | grep -o 'contacts=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local repost_events=$(echo "$sync_stats" | grep -o 'reposts=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local reaction_events=$(echo "$sync_stats" | grep -o 'reactions=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local blog_events=$(echo "$sync_stats" | grep -o 'blog=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local draft_events=$(echo "$sync_stats" | grep -o 'drafts=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local nip52_calendar_events=$(echo "$sync_stats" | grep -o 'nip52_calendar=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local analytics_events=$(echo "$sync_stats" | grep -o 'analytics=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local encrypted_analytics_events=$(echo "$sync_stats" | grep -o 'encrypted_analytics=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local badge_award_events=$(echo "$sync_stats" | grep -o 'badge_awards=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local profile_badge_events=$(echo "$sync_stats" | grep -o 'profile_badges=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local badge_definition_events=$(echo "$sync_stats" | grep -o 'badge_definitions=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local n2_memory_events=$(echo "$sync_stats" | grep -o 'n2_memory=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    
    local hex_count=$(echo "$sync_hex" | grep -o 'count=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local profiles_found=$(echo "$sync_profiles" | grep -o 'found=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local profiles_missing=$(echo "$sync_profiles" | grep -o 'missing=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local success_peers=$(echo "$sync_peers" | grep -o 'success=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local total_peers=$(echo "$sync_peers" | grep -o 'total=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    local imported_events=$(echo "$sync_import" | grep -o 'events=[0-9]*' | tail -1 | cut -d= -f2 | tr -d '\n')
    
    # Set default values if not found
    [[ -z "$total_events" ]] && total_events="0"
    [[ -z "$dm_events" ]] && dm_events="0"
    [[ -z "$public_events" ]] && public_events="0"
    [[ -z "$deletion_events" ]] && deletion_events="0"
    [[ -z "$video_events" ]] && video_events="0"
    [[ -z "$file_events" ]] && file_events="0"
    [[ -z "$comment_events" ]] && comment_events="0"
    [[ -z "$voice_events" ]] && voice_events="0"
    [[ -z "$tag_events" ]] && tag_events="0"
    [[ -z "$tmdb_events" ]] && tmdb_events="0"
    [[ -z "$channel_events" ]] && channel_events="0"
    [[ -z "$playlist_events" ]] && playlist_events="0"
    [[ -z "$status_events" ]] && status_events="0"
    [[ -z "$did_events" ]] && did_events="0"
    [[ -z "$oracle_events" ]] && oracle_events="0"
    [[ -z "$ore_events" ]] && ore_events="0"
    [[ -z "$economic_health_events" ]] && economic_health_events="0"
    [[ -z "$workflow_events" ]] && workflow_events="0"
    [[ -z "$profile_events" ]] && profile_events="0"
    [[ -z "$text_events" ]] && text_events="0"
    [[ -z "$contact_events" ]] && contact_events="0"
    [[ -z "$repost_events" ]] && repost_events="0"
    [[ -z "$reaction_events" ]] && reaction_events="0"
    [[ -z "$blog_events" ]] && blog_events="0"
    [[ -z "$draft_events" ]] && draft_events="0"
    [[ -z "$nip52_calendar_events" ]] && nip52_calendar_events="0"
    [[ -z "$analytics_events" ]] && analytics_events="0"
    [[ -z "$encrypted_analytics_events" ]] && encrypted_analytics_events="0"
    [[ -z "$badge_award_events" ]] && badge_award_events="0"
    [[ -z "$profile_badge_events" ]] && profile_badge_events="0"
    [[ -z "$badge_definition_events" ]] && badge_definition_events="0"
    [[ -z "$n2_memory_events" ]] && n2_memory_events="0"
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
FILE_EVENTS="$file_events"
COMMENT_EVENTS="$comment_events"
VOICE_EVENTS="$voice_events"
TAG_EVENTS="$tag_events"
TMDB_EVENTS="$tmdb_events"
CHANNEL_EVENTS="$channel_events"
PLAYLIST_EVENTS="$playlist_events"
STATUS_EVENTS="$status_events"
DID_EVENTS="$did_events"
ORACLE_EVENTS="$oracle_events"
ORE_EVENTS="$ore_events"
ECONOMIC_HEALTH_EVENTS="$economic_health_events"
WORKFLOW_EVENTS="$workflow_events"
PROFILE_EVENTS="$profile_events"
TEXT_EVENTS="$text_events"
CONTACT_EVENTS="$contact_events"
REPOST_EVENTS="$repost_events"
REACTION_EVENTS="$reaction_events"
BLOG_EVENTS="$blog_events"
DRAFT_EVENTS="$draft_events"
NIP52_CALENDAR_EVENTS="$nip52_calendar_events"
ANALYTICS_EVENTS="$analytics_events"
ENCRYPTED_ANALYTICS_EVENTS="$encrypted_analytics_events"
BADGE_AWARD_EVENTS="$badge_award_events"
PROFILE_BADGE_EVENTS="$profile_badge_events"
BADGE_DEFINITION_EVENTS="$badge_definition_events"
N2_MEMORY_EVENTS="$n2_memory_events"
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
    if [[ -n "$TOTAL_PEERS" ]] && [[ "$TOTAL_PEERS" =~ ^[0-9]+$ ]] && [[ "$TOTAL_PEERS" -gt 0 ]]; then
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
    local file_percent="0"
    local comment_percent="0"
    local voice_percent="0"
    local tag_percent="0"
    local tmdb_percent="0"
    local channel_percent="0"
    local playlist_percent="0"
    local status_percent="0"
    local deletion_percent="0"
    local did_percent="0"
    local oracle_percent="0"
    local ore_percent="0"
    local economic_health_percent="0"
    local workflow_percent="0"
    local profile_percent="0"
    local text_percent="0"
    local contact_percent="0"
    local repost_percent="0"
    local reaction_percent="0"
    local blog_percent="0"
    local draft_percent="0"
    local nip52_calendar_percent="0"
    local analytics_percent="0"
    local encrypted_analytics_percent="0"
    
    if [[ -n "$PROFILE_EVENTS" ]] && [[ "$PROFILE_EVENTS" =~ ^[0-9]+$ ]] && [[ "$PROFILE_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + PROFILE_EVENTS))
    fi
    if [[ -n "$TEXT_EVENTS" ]] && [[ "$TEXT_EVENTS" =~ ^[0-9]+$ ]] && [[ "$TEXT_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + TEXT_EVENTS))
    fi
    if [[ -n "$CONTACT_EVENTS" ]] && [[ "$CONTACT_EVENTS" =~ ^[0-9]+$ ]] && [[ "$CONTACT_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + CONTACT_EVENTS))
    fi
    if [[ -n "$REPOST_EVENTS" ]] && [[ "$REPOST_EVENTS" =~ ^[0-9]+$ ]] && [[ "$REPOST_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + REPOST_EVENTS))
    fi
    if [[ -n "$REACTION_EVENTS" ]] && [[ "$REACTION_EVENTS" =~ ^[0-9]+$ ]] && [[ "$REACTION_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + REACTION_EVENTS))
    fi
    if [[ -n "$BLOG_EVENTS" ]] && [[ "$BLOG_EVENTS" =~ ^[0-9]+$ ]] && [[ "$BLOG_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + BLOG_EVENTS))
    fi
    if [[ -n "$DRAFT_EVENTS" ]] && [[ "$DRAFT_EVENTS" =~ ^[0-9]+$ ]] && [[ "$DRAFT_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + DRAFT_EVENTS))
    fi
    if [[ -n "$NIP52_CALENDAR_EVENTS" ]] && [[ "$NIP52_CALENDAR_EVENTS" =~ ^[0-9]+$ ]] && [[ "$NIP52_CALENDAR_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + NIP52_CALENDAR_EVENTS))
    fi
    if [[ -n "$PUBLIC_EVENTS" ]] && [[ "$PUBLIC_EVENTS" =~ ^[0-9]+$ ]] && [[ "$PUBLIC_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + PUBLIC_EVENTS))
    fi
    if [[ -n "$DM_EVENTS" ]] && [[ "$DM_EVENTS" =~ ^[0-9]+$ ]] && [[ "$DM_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + DM_EVENTS))
    fi
    if [[ -n "$VIDEO_EVENTS" ]] && [[ "$VIDEO_EVENTS" =~ ^[0-9]+$ ]] && [[ "$VIDEO_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + VIDEO_EVENTS))
    fi
    if [[ -n "$FILE_EVENTS" ]] && [[ "$FILE_EVENTS" =~ ^[0-9]+$ ]] && [[ "$FILE_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + FILE_EVENTS))
    fi
    if [[ -n "$COMMENT_EVENTS" ]] && [[ "$COMMENT_EVENTS" =~ ^[0-9]+$ ]] && [[ "$COMMENT_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + COMMENT_EVENTS))
    fi
    if [[ -n "$VOICE_EVENTS" ]] && [[ "$VOICE_EVENTS" =~ ^[0-9]+$ ]] && [[ "$VOICE_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + VOICE_EVENTS))
    fi
    if [[ -n "$TAG_EVENTS" ]] && [[ "$TAG_EVENTS" =~ ^[0-9]+$ ]] && [[ "$TAG_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + TAG_EVENTS))
    fi
    if [[ -n "$TMDB_EVENTS" ]] && [[ "$TMDB_EVENTS" =~ ^[0-9]+$ ]] && [[ "$TMDB_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + TMDB_EVENTS))
    fi
    if [[ -n "$CHANNEL_EVENTS" ]] && [[ "$CHANNEL_EVENTS" =~ ^[0-9]+$ ]] && [[ "$CHANNEL_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + CHANNEL_EVENTS))
    fi
    if [[ -n "$PLAYLIST_EVENTS" ]] && [[ "$PLAYLIST_EVENTS" =~ ^[0-9]+$ ]] && [[ "$PLAYLIST_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + PLAYLIST_EVENTS))
    fi
    if [[ -n "$STATUS_EVENTS" ]] && [[ "$STATUS_EVENTS" =~ ^[0-9]+$ ]] && [[ "$STATUS_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + STATUS_EVENTS))
    fi
    if [[ -n "$DELETION_EVENTS" ]] && [[ "$DELETION_EVENTS" =~ ^[0-9]+$ ]] && [[ "$DELETION_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + DELETION_EVENTS))
    fi
    if [[ -n "$DID_EVENTS" ]] && [[ "$DID_EVENTS" =~ ^[0-9]+$ ]] && [[ "$DID_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + DID_EVENTS))
    fi
    if [[ -n "$ORACLE_EVENTS" ]] && [[ "$ORACLE_EVENTS" =~ ^[0-9]+$ ]] && [[ "$ORACLE_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + ORACLE_EVENTS))
    fi
    if [[ -n "$ORE_EVENTS" ]] && [[ "$ORE_EVENTS" =~ ^[0-9]+$ ]] && [[ "$ORE_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + ORE_EVENTS))
    fi
    if [[ -n "$ECONOMIC_HEALTH_EVENTS" ]] && [[ "$ECONOMIC_HEALTH_EVENTS" =~ ^[0-9]+$ ]] && [[ "$ECONOMIC_HEALTH_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + ECONOMIC_HEALTH_EVENTS))
    fi
    if [[ -n "$WORKFLOW_EVENTS" ]] && [[ "$WORKFLOW_EVENTS" =~ ^[0-9]+$ ]] && [[ "$WORKFLOW_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + WORKFLOW_EVENTS))
    fi
    if [[ -n "$ANALYTICS_EVENTS" ]] && [[ "$ANALYTICS_EVENTS" =~ ^[0-9]+$ ]] && [[ "$ANALYTICS_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + ANALYTICS_EVENTS))
    fi
    if [[ -n "$ENCRYPTED_ANALYTICS_EVENTS" ]] && [[ "$ENCRYPTED_ANALYTICS_EVENTS" =~ ^[0-9]+$ ]] && [[ "$ENCRYPTED_ANALYTICS_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + ENCRYPTED_ANALYTICS_EVENTS))
    fi
    if [[ -n "$BADGE_AWARD_EVENTS" ]] && [[ "$BADGE_AWARD_EVENTS" =~ ^[0-9]+$ ]] && [[ "$BADGE_AWARD_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + BADGE_AWARD_EVENTS))
    fi
    if [[ -n "$PROFILE_BADGE_EVENTS" ]] && [[ "$PROFILE_BADGE_EVENTS" =~ ^[0-9]+$ ]] && [[ "$PROFILE_BADGE_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + PROFILE_BADGE_EVENTS))
    fi
    if [[ -n "$BADGE_DEFINITION_EVENTS" ]] && [[ "$BADGE_DEFINITION_EVENTS" =~ ^[0-9]+$ ]] && [[ "$BADGE_DEFINITION_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + BADGE_DEFINITION_EVENTS))
    fi
    if [[ -n "$N2_MEMORY_EVENTS" ]] && [[ "$N2_MEMORY_EVENTS" =~ ^[0-9]+$ ]] && [[ "$N2_MEMORY_EVENTS" -gt 0 ]]; then
        total_message_events=$((total_message_events + N2_MEMORY_EVENTS))
    fi
    
    if [[ $total_message_events -gt 0 ]]; then
        public_percent=$(echo "scale=1; $PUBLIC_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        dm_percent=$(echo "scale=1; $DM_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        video_percent=$(echo "scale=1; $VIDEO_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        file_percent=$(echo "scale=1; $FILE_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        comment_percent=$(echo "scale=1; $COMMENT_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        voice_percent=$(echo "scale=1; $VOICE_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        tag_percent=$(echo "scale=1; $TAG_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        tmdb_percent=$(echo "scale=1; $TMDB_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        channel_percent=$(echo "scale=1; $CHANNEL_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        playlist_percent=$(echo "scale=1; $PLAYLIST_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        status_percent=$(echo "scale=1; $STATUS_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        deletion_percent=$(echo "scale=1; $DELETION_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        did_percent=$(echo "scale=1; $DID_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        oracle_percent=$(echo "scale=1; $ORACLE_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        ore_percent=$(echo "scale=1; $ORE_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        economic_health_percent=$(echo "scale=1; $ECONOMIC_HEALTH_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        workflow_percent=$(echo "scale=1; $WORKFLOW_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        profile_percent=$(echo "scale=1; $PROFILE_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        text_percent=$(echo "scale=1; $TEXT_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        contact_percent=$(echo "scale=1; $CONTACT_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        repost_percent=$(echo "scale=1; $REPOST_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        reaction_percent=$(echo "scale=1; $REACTION_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        blog_percent=$(echo "scale=1; $BLOG_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        draft_percent=$(echo "scale=1; $DRAFT_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        nip52_calendar_percent=$(echo "scale=1; $NIP52_CALENDAR_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        analytics_percent=$(echo "scale=1; $ANALYTICS_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        encrypted_analytics_percent=$(echo "scale=1; $ENCRYPTED_ANALYTICS_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        badge_award_percent=$(echo "scale=1; $BADGE_AWARD_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        profile_badge_percent=$(echo "scale=1; $PROFILE_BADGE_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        badge_definition_percent=$(echo "scale=1; $BADGE_DEFINITION_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
        n2_memory_percent=$(echo "scale=1; $N2_MEMORY_EVENTS * 100 / $total_message_events" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Determine report type and create informative title
    local report_type="Sync Report"
    local title_suffix=""
    
    # Build informative title with key metrics
    local title_parts=()
    
    if [[ "$IMPORTED_EVENTS" -gt 0 ]]; then
        title_parts+=("${IMPORTED_EVENTS} events imported")
    fi
    
    if [[ "$SUCCESS_PEERS" -gt 0 && "$TOTAL_PEERS" -gt 0 ]]; then
        title_parts+=("${SUCCESS_PEERS}/${TOTAL_PEERS} peers")
    fi
    
    # Add top event types to title
    local top_events=()
    [[ "$VIDEO_EVENTS" -gt 0 ]] && top_events+=("${VIDEO_EVENTS} videos")
    [[ "$TEXT_EVENTS" -gt 0 ]] && top_events+=("${TEXT_EVENTS} notes")
    [[ "$DM_EVENTS" -gt 0 ]] && top_events+=("${DM_EVENTS} DMs")
    [[ "$FILE_EVENTS" -gt 0 ]] && top_events+=("${FILE_EVENTS} files")
    [[ "$COMMENT_EVENTS" -gt 0 ]] && top_events+=("${COMMENT_EVENTS} comments")
    [[ "$PROFILE_EVENTS" -gt 0 ]] && top_events+=("${PROFILE_EVENTS} profiles")
    [[ "$BADGE_AWARD_EVENTS" -gt 0 ]] && top_events+=("${BADGE_AWARD_EVENTS} badge awards")
    [[ "$N2_MEMORY_EVENTS" -gt 0 ]] && top_events+=("${N2_MEMORY_EVENTS} N² memory")
    
    # Take top 3 event types
    if [[ ${#top_events[@]} -gt 0 ]]; then
        local top_3_list=""
        local count=0
        for event in "${top_events[@]}"; do
            [[ $count -ge 3 ]] && break
            [[ -n "$top_3_list" ]] && top_3_list+=", "
            top_3_list+="$event"
            ((count++))
        done
        [[ -n "$top_3_list" ]] && title_parts+=("$top_3_list")
    fi
    
    # Add error indicator if present
    local total_failures=$((BATCH_FAILURES + WEBSOCKET_FAILURES + TUNNEL_FAILURES))
    if [[ "$total_failures" -gt 0 ]]; then
        title_parts+=("⚠️ ${total_failures} errors")
    fi
    
    # Build final title
    if [[ ${#title_parts[@]} -gt 0 ]]; then
        local title_joined=""
        for part in "${title_parts[@]}"; do
            [[ -n "$title_joined" ]] && title_joined+=" • "
            title_joined+="$part"
        done
        title_suffix=" - $title_joined"
    fi
    
    # Determine report type for classification
    if [[ "$IMPORTED_EVENTS" -gt 0 && "$total_failures" -gt 0 ]]; then
        report_type="Sync Report (Activity + Errors)"
    elif [[ "$IMPORTED_EVENTS" -gt 0 ]]; then
        report_type="Sync Report (Activity)"
    elif [[ "$total_failures" -gt 0 ]]; then
        report_type="Sync Report (Errors)"
    fi
    
    # Generate HTML report
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>UPlanet Constellation $report_type$title_suffix</title>
    <script src="https://ipfs.copylaradio.com/ipns/copylaradio.com/@p5.min.js"></script>
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
        .badge-events { background: #fff9e6; }
        .n2-memory-events { background: #e8f0fe; border-left: 3px solid #1a73e8; }
        .footer { text-align: center; margin-top: 20px; color: #7f8c8d; font-size: 12px; }
        #p5-canvas { position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: -1; pointer-events: none; opacity: 0.1; }
    </style>
</head>
<body>
    <div id="p5-canvas"></div>
    <div class="container">
        <div class="header">
            <h1>🌍 UPlanet Constellation $report_type$title_suffix</h1>
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
            <div class="stat-card video-events">
                <div class="stat-value">$FILE_EVENTS</div>
                <div class="stat-label">File Metadata ($file_percent%)</div>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card video-events">
                <div class="stat-value">$COMMENT_EVENTS</div>
                <div class="stat-label">Comments ($comment_percent%)</div>
            </div>
            <div class="stat-card video-events">
                <div class="stat-value">$TAG_EVENTS</div>
                <div class="stat-label">User Tags ($tag_percent%)</div>
            </div>
            <div class="stat-card deletion-events">
                <div class="stat-value">$DELETION_EVENTS</div>
                <div class="stat-label">Deletion Events ($deletion_percent%)</div>
            </div>
            <div class="stat-card did-events">
                <div class="stat-value">$DID_EVENTS</div>
                <div class="stat-label">DID Documents ($did_percent%)</div>
            </div>
            <div class="stat-card oracle-events">
                <div class="stat-value">$ORACLE_EVENTS</div>
                <div class="stat-label">Oracle Permits ($oracle_percent%)</div>
            </div>
            <div class="stat-card badge-events">
                <div class="stat-value">$BADGE_AWARD_EVENTS</div>
                <div class="stat-label">Badge Awards ($badge_award_percent%)</div>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card ore-events">
                <div class="stat-value">$ORE_EVENTS</div>
                <div class="stat-label">ORE Contracts ($ore_percent%)</div>
            </div>
            <div class="stat-card n2-memory-events">
                <div class="stat-value">$N2_MEMORY_EVENTS</div>
                <div class="stat-label">N² Memory ($n2_memory_percent%)</div>
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
                • <strong>Profiles:</strong> $PROFILE_EVENTS ($profile_percent%) - User profiles (kind 0 - NIP-01)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Text Notes:</strong> $TEXT_EVENTS ($text_percent%) - Text notes and posts (kind 1 - NIP-01)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Contacts:</strong> $CONTACT_EVENTS ($contact_percent%) - Contact lists and follows (kind 3 - NIP-02)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Direct Messages:</strong> $DM_EVENTS ($dm_percent%) - Private conversations between users (kind 4 - NIP-04)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Reposts:</strong> $REPOST_EVENTS ($repost_percent%) - Reposted events (kind 6 - NIP-18)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Reactions:</strong> $REACTION_EVENTS ($reaction_percent%) - Like and reaction events (kind 7 - NIP-25)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Public Messages:</strong> $PUBLIC_EVENTS ($public_percent%) - Other public messages and communications
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Video Events:</strong> $VIDEO_EVENTS ($video_percent%) - YouTube videos (kind 21/22) from process_youtube.sh
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>File Metadata:</strong> $FILE_EVENTS ($file_percent%) - File attachments (kind 1063 - NIP-94) from upload2ipfs.sh
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Comments:</strong> $COMMENT_EVENTS ($comment_percent%) - Video comments (kind 1111 - NIP-22) from theater-modal.html
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Voice Messages:</strong> $VOICE_EVENTS ($voice_percent%) - Short voice messages (kinds 1222, 1244 - NIP-A0)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>User Tags:</strong> $TAG_EVENTS ($tag_percent%) - User-generated tags (kind 1985 - NIP-32) from tags.html and publish_nostr_video.sh
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>TMDB Enrichments:</strong> $TMDB_EVENTS ($tmdb_percent%) - Video metadata enrichments (kinds 1986, 30001 - NIP-71 extension) from contrib.html
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Channel Messages:</strong> $CHANNEL_EVENTS ($channel_percent%) - Channel messages and mute events (kinds 40-44 - NIP-28)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Playlists:</strong> $PLAYLIST_EVENTS ($playlist_percent%) - User playlists (kinds 30005, 10001 - NIP-51)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>User Statuses:</strong> $STATUS_EVENTS ($status_percent%) - Live user statuses including music (kind 30315 - NIP-38)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Deletion Events:</strong> $DELETION_EVENTS ($deletion_percent%) - Messages marked for deletion (kind 5)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>DID Documents:</strong> $DID_EVENTS ($did_percent%) - Identity documents (kind 30800 - NIP-101) from did_manager_nostr.sh
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Oracle Permits:</strong> $ORACLE_EVENTS ($oracle_percent%) - Permit system events (kinds 30500-30503): definitions, requests, attestations, credentials
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Badge Awards:</strong> $BADGE_AWARD_EVENTS ($badge_award_percent%) - Badge awards (kind 8 - NIP-58) from Oracle system
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Profile Badges:</strong> $PROFILE_BADGE_EVENTS ($profile_badge_percent%) - User profile badge selections (kind 30008 - NIP-58)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Badge Definitions:</strong> $BADGE_DEFINITION_EVENTS ($badge_definition_percent%) - Badge definitions (kind 30009 - NIP-58) from Oracle system
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>ORE Contracts:</strong> $ORE_EVENTS ($ore_percent%) - Environmental obligations (kinds 30312-30313): meeting spaces, verification meetings
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Economic Health:</strong> $ECONOMIC_HEALTH_EVENTS ($economic_health_percent%) - Wallet balance reports (kinds 30850-30851 - NIP-101 extension) from todo.sh
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Cookie Workflows:</strong> $WORKFLOW_EVENTS ($workflow_percent%) - Workflow definitions and executions (kinds 31900-31902 - NIP-101 extension) from n8n.html
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Blog Posts:</strong> $BLOG_EVENTS ($blog_percent%) - Long-form blog posts (kind 30023 - NIP-23)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Draft Articles:</strong> $DRAFT_EVENTS ($draft_percent%) - Draft long-form content (kind 30024 - NIP-23)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>NIP-52 Calendar:</strong> $NIP52_CALENDAR_EVENTS ($nip52_calendar_percent%) - Lunar calendar events from plantnet.html (kinds 31922-31925 - NIP-52)
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Analytics Events:</strong> $ANALYTICS_EVENTS ($analytics_percent%) - UPlanet analytics events (kind 10000 - NIP-10000, unencrypted) from astro.js
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>Encrypted Analytics:</strong> $ENCRYPTED_ANALYTICS_EVENTS ($encrypted_analytics_percent%) - Encrypted UPlanet analytics events (kind 10000 - NIP-10000, encrypted content) from astro.js
            </p>
            <p style="margin: 5px 0; color: #555;">
                • <strong>N² Memory:</strong> $N2_MEMORY_EVENTS ($n2_memory_percent%) - AI recommendations, Captain TODOs, votes (kind 31910 - NIP-101 extension) from todo.sh
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
    <script>
        // p5.js visualization for stats
        function setup() {
            createCanvas(windowWidth, windowHeight);
            noStroke();
        }
        
        function draw() {
            background(245, 245, 245, 10);
            
            // Animated particles representing events
            for (let i = 0; i < 50; i++) {
                let x = (frameCount * 0.5 + i * 50) % width;
                let y = height / 2 + sin(frameCount * 0.01 + i) * 100;
                let size = 2 + sin(frameCount * 0.02 + i) * 2;
                fill(52, 152, 219, 50);
                ellipse(x, y, size, size);
            }
            
            // Constellation pattern
            for (let i = 0; i < 20; i++) {
                let angle = (frameCount * 0.005 + i) * TWO_PI / 20;
                let radius = 150 + sin(frameCount * 0.01 + i) * 30;
                let x = width / 2 + cos(angle) * radius;
                let y = height / 2 + sin(angle) * radius;
                fill(46, 204, 113, 30);
                ellipse(x, y, 3, 3);
            }
        }
        
        function windowResized() {
            resizeCanvas(windowWidth, windowHeight);
        }
    </script>
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
    if [[ -n "$IMPORTED_EVENTS" ]] && [[ "$IMPORTED_EVENTS" =~ ^[0-9]+$ ]] && [[ "$IMPORTED_EVENTS" -gt 0 ]]; then
        has_imported_events=true
    fi
    
    # Check if there are any errors
    local has_errors=false
    if ( [[ -n "$BATCH_FAILURES" ]] && [[ "$BATCH_FAILURES" =~ ^[0-9]+$ ]] && [[ "$BATCH_FAILURES" -gt 0 ]] ) || \
       ( [[ -n "$WEBSOCKET_FAILURES" ]] && [[ "$WEBSOCKET_FAILURES" =~ ^[0-9]+$ ]] && [[ "$WEBSOCKET_FAILURES" -gt 0 ]] ) || \
       ( [[ -n "$TUNNEL_FAILURES" ]] && [[ "$TUNNEL_FAILURES" =~ ^[0-9]+$ ]] && [[ "$TUNNEL_FAILURES" -gt 0 ]] ); then
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
    
    # Send report using nostr_send_note.py
    echo "📤 Sending synchronization report via NOSTR..."
    
    # Create a meaningful title for the report
    local report_title="Constellation Sync Report - $(date '+%Y-%m-%d %H:%M')"
    
    # Upload HTML report to IPFS (similar to mailjet.sh)
    echo "📤 Uploading report to IPFS..."
    local report_ipfs=$(ipfs add -q "$temp_html" 2>/dev/null)
    
    if [[ -z "$report_ipfs" ]]; then
        echo "❌ Failed to upload report to IPFS"
        rm -f "$temp_html"
        return 1
    fi
    
    echo "✅ Report uploaded to IPFS: /ipfs/$report_ipfs"
    
    # Get IPFS gateway URL
    local ipfs_url="$(myIpfsGw)/ipfs/$report_ipfs"
    
    # Prepare NOSTR message content
    eval "$stats"
    
    # Get captain nprofile for reference (if available)
    local CAPTAIN_NPROFILE=""
    if [[ -n "$CAPTAINEMAIL" && -n "$CAPTAINHEX" ]]; then
        CAPTAIN_NPROFILE=$($HOME/.zen/Astroport.ONE/tools/nostr_hex2nprofile.sh "$CAPTAINHEX" 2>/dev/null)
        [[ -z "$CAPTAIN_NPROFILE" ]] && CAPTAIN_NPROFILE="unknown_captain"
    fi
    
    local nostr_content="📊 ${report_title}

🔗 Full Report: ${ipfs_url}
/ipfs/${report_ipfs}

📈 Summary:
• Peers: ${SUCCESS_PEERS}/${TOTAL_PEERS} successful
• Events: ${TOTAL_EVENTS} collected, ${IMPORTED_EVENTS} imported
• HEX Pubkeys: ${HEX_PUBKEYS}
• Profiles: ${PROFILES_FOUND} found, ${PROFILES_MISSING} missing

📨 Message Types:
• Profiles: ${PROFILE_EVENTS}
• Text Notes: ${TEXT_EVENTS}
• Contacts: ${CONTACT_EVENTS}
• DMs: ${DM_EVENTS}
• Reposts: ${REPOST_EVENTS}
• Reactions: ${REACTION_EVENTS}
• Public: ${PUBLIC_EVENTS}
• Videos: ${VIDEO_EVENTS}
• Files: ${FILE_EVENTS}
• Comments: ${COMMENT_EVENTS}
• Voice: ${VOICE_EVENTS}
• Tags: ${TAG_EVENTS}
• TMDB: ${TMDB_EVENTS}
• Channels: ${CHANNEL_EVENTS}
• Playlists: ${PLAYLIST_EVENTS}
• Status: ${STATUS_EVENTS}
• Deletions: ${DELETION_EVENTS}
• DID: ${DID_EVENTS}
• Oracle: ${ORACLE_EVENTS}
• ORE: ${ORE_EVENTS}
• Economic Health: ${ECONOMIC_HEALTH_EVENTS}
• Workflows: ${WORKFLOW_EVENTS}
• Blog: ${BLOG_EVENTS}
• Drafts: ${DRAFT_EVENTS}
• NIP-52 Calendar: ${NIP52_CALENDAR_EVENTS}
• Analytics: ${ANALYTICS_EVENTS}
• Encrypted Analytics: ${ENCRYPTED_ANALYTICS_EVENTS}
• Badge Awards: ${BADGE_AWARD_EVENTS}
• Profile Badges: ${PROFILE_BADGE_EVENTS}
• Badge Definitions: ${BADGE_DEFINITION_EVENTS}
• N² Memory: ${N2_MEMORY_EVENTS}

⚠️ Retries: Batch=${BATCH_RETRIES}, WS=${WEBSOCKET_RETRIES}, Tunnel=${TUNNEL_RETRIES}
❌ Failures: Batch=${BATCH_FAILURES}, WS=${WEBSOCKET_FAILURES}, Tunnel=${TUNNEL_FAILURES}

⏰ Sync Time: ${SYNC_START_TIME} → ${SYNC_END_TIME}
🌐 Node: ${IPFSNODEID}

🌍 UMAP 0.00,0.00 - Global Meeting Point
This synchronization report comes from the global UMAP (0.00,0.00), the meeting point for system messages and reports.

#UMAP_0.00_0.00
#Captain:${CAPTAIN_NPROFILE}"

    # Generate UMAP 0.00,0.00 key (same as 1.sh)
    local UMAPNSEC=$($HOME/.zen/Astroport.ONE/tools/keygen -t nostr "${UPLANETNAME}0.00" "${UPLANETNAME}0.00" -s)
    
    if [[ -z "$UMAPNSEC" ]]; then
        echo "❌ Failed to generate UMAP 0.00,0.00 NSEC key"
        rm -f "$temp_html"
        return 1
    fi
    
    # Convert NSEC to HEX
    local UMAP_HEX=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$UMAPNSEC")
    
    if [[ -z "$UMAP_HEX" ]]; then
        echo "❌ Failed to convert UMAP NSEC to HEX"
        rm -f "$temp_html"
        return 1
    fi
    
    echo "🌍 Using UMAP 0.00,0.00 key for sync report (pubkey: ${UMAP_HEX:0:16}...)"
    
    # Create temporary keyfile for nostr_send_note.py in .secret.nostr format
    # Format: NSEC=nsec1...; (NPUB and HEX are optional, NSEC is required)
    local umap_keyfile="/tmp/umap_0.00_keyfile_$(date +%s).nsec"
    echo "NSEC=$UMAPNSEC;" > "$umap_keyfile"
    chmod 600 "$umap_keyfile"
    
    # Get default relay from environment (myRELAY) or use default
    local nostr_relay="${myRELAY:-ws://127.0.0.1:7777}"
    
    # Send via NOSTR using nostr_send_note.py
    local nostr_script="$HOME/.zen/Astroport.ONE/tools/nostr_send_note.py"
    
    if [[ ! -x "$nostr_script" ]]; then
        echo "❌ nostr_send_note.py not found or not executable: $nostr_script"
        rm -f "$temp_html"
        return 1
    fi
    
    echo "🚀 Sending NOSTR note via $nostr_relay using UMAP 0.00,0.00 key..."
    
    # Call nostr_send_note.py with ephemeral flag (1h = 3600 seconds)
    python3 "$nostr_script" \
        --keyfile "$umap_keyfile" \
        --content "$nostr_content" \
        --relays "$nostr_relay" \
        --ephemeral 3600 \
        --json > /tmp/nostr_result.json 2>&1
    
    local nostr_exit_code=$?
    local nostr_result=$(cat /tmp/nostr_result.json 2>/dev/null)
    
    # Clean up temporary files
    rm -f "$temp_html" "$umap_keyfile" /tmp/nostr_result.json
    
    # Check result
    if [[ $nostr_exit_code -eq 0 ]] && echo "$nostr_result" | grep -q '"success":\s*true'; then
        local event_id=$(echo "$nostr_result" | grep -o '"event_id":\s*"[^"]*"' | grep -o '[a-f0-9]\{64\}' | head -n 1)
        if [[ -n "$event_id" ]]; then
            echo "✅ Synchronization report sent successfully via NOSTR"
            echo "   Event ID: ${event_id:0:16}..."
            echo "   IPFS: /ipfs/$report_ipfs"
            return 0
        else
            echo "✅ Synchronization report sent via NOSTR (no event ID returned)"
            return 0
        fi
    else
        echo "❌ Failed to send synchronization report via NOSTR"
        echo "   Error output: $nostr_result"
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
