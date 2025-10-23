#!/bin/bash
# filter/21.sh - Video Event Filter (NIP-71)
# Logs video recordings and webcam uploads for analysis

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Source common functions
source "$MY_PATH/common.sh"

# Extract event data using optimized common function
event_json="$1"
extract_event_data "$event_json"

# Extract video-specific tags
extract_tags "$event_json" "title" "imeta" "duration" "published_at" "g" "location"
title="$title"
imeta="$imeta"
duration="$duration"
published_at="$published_at"
g="$g"
location="$location"

# Initialize full_content with content if not already set
[[ -z "$full_content" ]] && full_content="$content"

# Video logging directory
TMP_LOG_DIR="$HOME/.zen/tmp"
mkdir -p "$TMP_LOG_DIR"

# Video log file
VIDEO_LOG_FILE="$TMP_LOG_DIR/nostr_video_events.log"

# Video statistics file
VIDEO_STATS_FILE="$TMP_LOG_DIR/nostr_video_stats.json"

# Logging functions
log_video() {
    log_with_timestamp "$VIDEO_LOG_FILE" "$1"
}

# Ensure log directories exist
ensure_log_dir "$VIDEO_LOG_FILE"

# Extract video metadata from imeta tag
extract_nostr_video_metadata() {
    local imeta_content="$1"
    local dimensions=""
    local url=""
    local hash=""
    local mime_type=""
    
    # Parse imeta content
    if [[ -n "$imeta_content" ]]; then
        # Extract dimensions (dim WIDTHxHEIGHT)
        dimensions=$(echo "$imeta_content" | grep -o 'dim [0-9]*x[0-9]*' | sed 's/dim //')
        
        # Extract URL (url URL)
        url=$(echo "$imeta_content" | grep -o 'url [^ ]*' | sed 's/url //')
        
        # Extract hash (x HASH)
        hash=$(echo "$imeta_content" | grep -o 'x [a-f0-9]*' | sed 's/x //')
        
        # Extract MIME type (m MIME_TYPE)
        mime_type=$(echo "$imeta_content" | grep -o 'm [^ ]*' | sed 's/m //')
    fi
    
    echo "$dimensions|$url|$hash|$mime_type"
}

# Update video statistics
update_nostr_video_stats() {
    local pubkey="$1"
    local title="$2"
    local duration="$3"
    local dimensions="$4"
    local mime_type="$5"
    local has_location="$6"
    
    # Initialize stats file if it doesn't exist
    if [[ ! -f "$VIDEO_STATS_FILE" ]]; then
        echo '{"total_videos": 0, "total_duration": 0, "by_user": {}, "by_type": {}, "with_location": 0, "webcam_videos": 0}' > "$VIDEO_STATS_FILE"
    fi
    
    # Update statistics using jq
    local temp_file=$(mktemp)
    jq --arg pubkey "$pubkey" \
       --arg title "$title" \
       --argjson duration "${duration:-0}" \
       --arg dimensions "$dimensions" \
       --arg mime_type "$mime_type" \
       --argjson has_location "$has_location" \
       '.total_videos += 1 |
        .total_duration += $duration |
        .by_user[$pubkey] = (.by_user[$pubkey] // 0) + 1 |
        .by_type[$mime_type] = (.by_type[$mime_type] // 0) + 1 |
        .with_location += (if $has_location then 1 else 0 end) |
        .webcam_videos += (if ($title | contains("webcam") or contains("Webcam")) then 1 else 0 end)' \
       "$VIDEO_STATS_FILE" > "$temp_file"
    
    mv "$temp_file" "$VIDEO_STATS_FILE"
}

# Detect video type and source
detect_nostr_video_type() {
    local title="$1"
    local content="$2"
    local tags="$3"
    
    local nostr_video_type="unknown"
    
    # Check for webcam recordings
    if [[ "$title" == *"webcam"* || "$title" == *"Webcam"* || "$content" == *"webcam"* ]]; then
        nostr_video_type="webcam"
    # Check for YouTube downloads
    elif [[ "$content" == *"youtube"* || "$content" == *"YouTube"* ]]; then
        nostr_video_type="youtube"
    # Check for OBS recordings
    elif [[ "$content" == *"OBS"* || "$content" == *"obs"* ]]; then
        nostr_video_type="obs"
    # Check for mobile recordings
    elif [[ "$content" == *"mobile"* || "$content" == *"phone"* ]]; then
        nostr_video_type="mobile"
    # Check for screen recordings
    elif [[ "$content" == *"screen"* || "$content" == *"capture"* ]]; then
        nostr_video_type="screen"
    fi
    
    echo "$nostr_video_type"
}

# Main video processing
process_nostr_video_event() {
    local pubkey="$1"
    local event_id="$2"
    local title="$3"
    local content="$4"
    local duration="$5"
    local latitude="$6"
    local longitude="$7"
    
    # Extract video metadata
    local metadata=$(extract_nostr_video_metadata "$imeta")
    local dimensions=$(echo "$metadata" | cut -d'|' -f1)
    local url=$(echo "$metadata" | cut -d'|' -f2)
    local hash=$(echo "$metadata" | cut -d'|' -f3)
    local mime_type=$(echo "$metadata" | cut -d'|' -f4)
    
    # Detect video type
    local nostr_video_type=$(detect_nostr_video_type "$title" "$content" "$tags")
    
    # Check if video has location
    local has_location="false"
    if [[ -n "$latitude" && -n "$longitude" && "$latitude" != "0.00" && "$longitude" != "0.00" ]]; then
        has_location="true"
    fi
    
    # Log video event
    log_video "VIDEO_EVENT: ID=$event_id, Pubkey=$pubkey, Type=$nostr_video_type, Title='$title'"
    log_video "VIDEO_META: Duration=${duration}s, Dimensions=$dimensions, MIME=$mime_type, URL=$url"
    log_video "VIDEO_LOCATION: Lat=$latitude, Lon=$longitude, HasLocation=$has_location"
    log_video "VIDEO_HASH: $hash"
    
    # Update statistics
    update_nostr_video_stats "$pubkey" "$title" "$duration" "$dimensions" "$mime_type" "$has_location"
    
    # Log specific video type information
    case "$nostr_video_type" in
        "webcam")
            log_video "WEBCAM_RECORDING: User=$pubkey, Duration=${duration}s, Location=$latitude,$longitude"
            ;;
        "youtube")
            log_video "YOUTUBE_DOWNLOAD: User=$pubkey, URL=$url, Duration=${duration}s"
            ;;
        "obs")
            log_video "OBS_RECORDING: User=$pubkey, Duration=${duration}s, Dimensions=$dimensions"
            ;;
        "mobile")
            log_video "MOBILE_RECORDING: User=$pubkey, Duration=${duration}s, Location=$latitude,$longitude"
            ;;
        "screen")
            log_video "SCREEN_RECORDING: User=$pubkey, Duration=${duration}s, Dimensions=$dimensions"
            ;;
    esac
    
    # Log video quality information
    if [[ -n "$dimensions" ]]; then
        local width=$(echo "$dimensions" | cut -d'x' -f1)
        local height=$(echo "$dimensions" | cut -d'x' -f2)
        local quality=""
        
        if [[ "$width" -ge 1920 && "$height" -ge 1080 ]]; then
            quality="HD"
        elif [[ "$width" -ge 1280 && "$height" -ge 720 ]]; then
            quality="HD"
        elif [[ "$width" -ge 854 && "$height" -ge 480 ]]; then
            quality="SD"
        else
            quality="Low"
        fi
        
        log_video "VIDEO_QUALITY: $quality ($dimensions)"
    fi
    
    # Log duration category
    local duration_category=""
    if [[ "$duration" -le 30 ]]; then
        duration_category="Short"
    elif [[ "$duration" -le 300 ]]; then
        duration_category="Medium"
    else
        duration_category="Long"
    fi
    
    log_video "VIDEO_DURATION_CATEGORY: $duration_category (${duration}s)"
    
    # Log UMAP information if location is provided
    if [[ "$has_location" == "true" ]]; then
        log_video "VIDEO_UMAP: Anchored at $latitude,$longitude"
    else
        log_video "VIDEO_UMAP: No location data (global UMAP 0.00,0.00)"
    fi
}

# Extract coordinates from location or g tag
extract_coordinates() {
    local latitude=""
    local longitude=""
    
    # Try to get coordinates from g tag first
    if [[ -n "$g" ]]; then
        latitude=$(echo "$g" | cut -d',' -f1 | xargs)
        longitude=$(echo "$g" | cut -d',' -f2 | xargs)
    fi
    
    # Try to get coordinates from location tag
    if [[ -z "$latitude" && -n "$location" ]]; then
        latitude=$(echo "$location" | cut -d',' -f1 | xargs)
        longitude=$(echo "$location" | cut -d',' -f2 | xargs)
    fi
    
    # Default to 0.00,0.00 if no coordinates found
    [[ -z "$latitude" ]] && latitude="0.00"
    [[ -z "$longitude" ]] && longitude="0.00"
    
    echo "$latitude|$longitude"
}

# Main execution
log_video "=== VIDEO EVENT PROCESSING START ==="
log_video "Event ID: $event_id"
log_video "Pubkey: $pubkey"
log_video "Title: $title"
log_video "Content: ${content:0:100}..."

# Extract coordinates
local coords=$(extract_coordinates)
local latitude=$(echo "$coords" | cut -d'|' -f1)
local longitude=$(echo "$coords" | cut -d'|' -f2)

# Process video event
process_nostr_video_event "$pubkey" "$event_id" "$title" "$content" "$duration" "$latitude" "$longitude"

log_video "=== VIDEO EVENT PROCESSING END ==="

# Always accept video events (they are logged but not blocked)
exit 0
