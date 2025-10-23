#!/bin/bash
# filter/22.sh - Long Video Event Filter (NIP-71)
# Logs long video recordings and extended content for analysis

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Source common functions
source "$MY_PATH/common.sh"

# Extract event data using optimized common function
event_json="$1"
extract_event_data "$event_json"

# Extract video-specific tags
extract_tags "$event_json" "title" "imeta" "duration" "published_at" "g" "location" "application" "url" "latitude" "longitude"
title="$title"
imeta="$imeta"
duration="$duration"
published_at="$published_at"
g="$g"
location="$location"
application="$application"
url="$url"
latitude="$latitude"
longitude="$longitude"

# Extract coordinates from "g" tag if latitude/longitude not directly provided
# Format: ["g", "lat,lon"] (standard Nostr geolocation tag)
if [[ -z "$latitude" || -z "$longitude" ]] && [[ -n "$g" ]]; then
    latitude=$(echo "$g" | cut -d',' -f1 | xargs)
    longitude=$(echo "$g" | cut -d',' -f2 | xargs)
    log_long_video "Extracted coordinates from 'g' tag: lat=$latitude, lon=$longitude"
fi

# Initialize full_content with content if not already set
[[ -z "$full_content" ]] && full_content="$content"

# Video logging directory
TMP_LOG_DIR="$HOME/.zen/tmp"
mkdir -p "$TMP_LOG_DIR"

# Long video log file
LONG_VIDEO_LOG_FILE="$TMP_LOG_DIR/nostr_long_video_events.log"

# Long video statistics file
LONG_VIDEO_STATS_FILE="$TMP_LOG_DIR/nostr_long_video_stats.json"

# Logging functions
log_long_video() {
    log_with_timestamp "$LONG_VIDEO_LOG_FILE" "$1"
}

# Ensure log directories exist
ensure_log_dir "$LONG_VIDEO_LOG_FILE"

# Extract video metadata from imeta tag
extract_video_metadata() {
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

# Update long video statistics
update_nostr_long_video_stats() {
    local pubkey="$1"
    local title="$2"
    local duration="$3"
    local dimensions="$4"
    local mime_type="$5"
    local has_location="$6"
    
    # Initialize stats file if it doesn't exist
    if [[ ! -f "$LONG_VIDEO_STATS_FILE" ]]; then
        echo '{"total_long_videos": 0, "total_duration": 0, "by_user": {}, "by_type": {}, "with_location": 0, "extended_content": 0}' > "$LONG_VIDEO_STATS_FILE"
    fi
    
    # Update statistics using jq
    local temp_file=$(mktemp)
    jq --arg pubkey "$pubkey" \
       --arg title "$title" \
       --argjson duration "${duration:-0}" \
       --arg dimensions "$dimensions" \
       --arg mime_type "$mime_type" \
       --argjson has_location "$has_location" \
       '.total_long_videos += 1 |
        .total_duration += $duration |
        .by_user[$pubkey] = (.by_user[$pubkey] // 0) + 1 |
        .by_type[$mime_type] = (.by_type[$mime_type] // 0) + 1 |
        .with_location += (if $has_location then 1 else 0 end) |
        .extended_content += (if ($title | length > 50) then 1 else 0 end)' \
       "$LONG_VIDEO_STATS_FILE" > "$temp_file"
    
    mv "$temp_file" "$LONG_VIDEO_STATS_FILE"
}

# Detect long video type and source
detect_nostr_long_video_type() {
    local title="$1"
    local content="$2"
    local duration="$3"
    
    local video_type="long_unknown"
    
    # Check for extended webcam recordings
    if [[ "$title" == *"webcam"* || "$title" == *"Webcam"* || "$content" == *"webcam"* ]]; then
        video_type="extended_webcam"
    # Check for long YouTube downloads
    elif [[ "$content" == *"youtube"* || "$content" == *"YouTube"* ]]; then
        video_type="long_youtube"
    # Check for extended OBS recordings
    elif [[ "$content" == *"OBS"* || "$content" == *"obs"* ]]; then
        video_type="extended_obs"
    # Check for live streams
    elif [[ "$content" == *"live"* || "$content" == *"stream"* ]]; then
        video_type="live_stream"
    # Check for tutorials or educational content
    elif [[ "$content" == *"tutorial"* || "$content" == *"how"* || "$content" == *"learn"* ]]; then
        video_type="educational"
    # Check for presentations
    elif [[ "$content" == *"presentation"* || "$content" == *"talk"* || "$content" == *"conference"* ]]; then
        video_type="presentation"
    fi
    
    echo "$video_type"
}

# Analyze content length and complexity
analyze_content_complexity() {
    local content="$1"
    local title="$2"
    
    local content_length=${#content}
    local title_length=${#title}
    local word_count=$(echo "$content" | wc -w)
    local line_count=$(echo "$content" | wc -l)
    
    local complexity="simple"
    
    if [[ $content_length -gt 500 ]]; then
        complexity="detailed"
    fi
    
    if [[ $word_count -gt 100 ]]; then
        complexity="extensive"
    fi
    
    if [[ $line_count -gt 10 ]]; then
        complexity="structured"
    fi
    
    echo "$complexity|$content_length|$word_count|$line_count"
}

# Main long video processing
process_nostr_long_video_event() {
    local pubkey="$1"
    local event_id="$2"
    local title="$3"
    local content="$4"
    local duration="$5"
    local latitude="$6"
    local longitude="$7"
    
    # Extract video metadata
    local metadata=$(extract_video_metadata "$imeta")
    local dimensions=$(echo "$metadata" | cut -d'|' -f1)
    local url=$(echo "$metadata" | cut -d'|' -f2)
    local hash=$(echo "$metadata" | cut -d'|' -f3)
    local mime_type=$(echo "$metadata" | cut -d'|' -f4)
    
    # Detect long video type
    local video_type=$(detect_nostr_long_video_type "$title" "$content" "$duration")
    
    # Analyze content complexity
    local complexity_data=$(analyze_content_complexity "$content" "$title")
    local complexity=$(echo "$complexity_data" | cut -d'|' -f1)
    local content_length=$(echo "$complexity_data" | cut -d'|' -f2)
    local word_count=$(echo "$complexity_data" | cut -d'|' -f3)
    local line_count=$(echo "$complexity_data" | cut -d'|' -f4)
    
    # Check if video has location
    local has_location="false"
    if [[ -n "$latitude" && -n "$longitude" && "$latitude" != "0.00" && "$longitude" != "0.00" ]]; then
        has_location="true"
    fi
    
    # Log long video event
    log_long_video "LONG_VIDEO_EVENT: ID=$event_id, Pubkey=$pubkey, Type=$video_type, Title='$title'"
    log_long_video "LONG_VIDEO_META: Duration=${duration}s, Dimensions=$dimensions, MIME=$mime_type, URL=$url"
    log_long_video "LONG_VIDEO_LOCATION: Lat=$latitude, Lon=$longitude, HasLocation=$has_location"
    log_long_video "LONG_VIDEO_HASH: $hash"
    log_long_video "LONG_VIDEO_COMPLEXITY: $complexity, ContentLength=$content_length, Words=$word_count, Lines=$line_count"
    
    # Update statistics
    update_nostr_long_video_stats "$pubkey" "$title" "$duration" "$dimensions" "$mime_type" "$has_location"
    
    # Log specific long video type information
    case "$video_type" in
        "extended_webcam")
            log_long_video "EXTENDED_WEBCAM: User=$pubkey, Duration=${duration}s, Location=$latitude,$longitude"
            ;;
        "long_youtube")
            log_long_video "LONG_YOUTUBE: User=$pubkey, URL=$url, Duration=${duration}s"
            ;;
        "extended_obs")
            log_long_video "EXTENDED_OBS: User=$pubkey, Duration=${duration}s, Dimensions=$dimensions"
            ;;
        "live_stream")
            log_long_video "LIVE_STREAM: User=$pubkey, Duration=${duration}s, Location=$latitude,$longitude"
            ;;
        "educational")
            log_long_video "EDUCATIONAL_VIDEO: User=$pubkey, Duration=${duration}s, Complexity=$complexity"
            ;;
        "presentation")
            log_long_video "PRESENTATION: User=$pubkey, Duration=${duration}s, Location=$latitude,$longitude"
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
        
        log_long_video "LONG_VIDEO_QUALITY: $quality ($dimensions)"
    fi
    
    # Log duration category for long videos
    local duration_category=""
    if [[ "$duration" -le 600 ]]; then
        duration_category="Medium"
    elif [[ "$duration" -le 1800 ]]; then
        duration_category="Long"
    else
        duration_category="Extended"
    fi
    
    log_long_video "LONG_VIDEO_DURATION_CATEGORY: $duration_category (${duration}s)"
    
    # Log UMAP information if location is provided
    if [[ "$has_location" == "true" ]]; then
        log_long_video "LONG_VIDEO_UMAP: Anchored at $latitude,$longitude"
    else
        log_long_video "LONG_VIDEO_UMAP: No location data (global UMAP 0.00,0.00)"
    fi
    
    # Log content analysis
    log_long_video "LONG_VIDEO_CONTENT_ANALYSIS: Complexity=$complexity, Length=$content_length, Words=$word_count"
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
log_long_video "=== LONG VIDEO EVENT PROCESSING START ==="
log_long_video "Event ID: $event_id"
log_long_video "Pubkey: $pubkey"
log_long_video "Title: $title"
log_long_video "Content: ${content:0:100}..."

# Extract coordinates
local coords=$(extract_coordinates)
local latitude=$(echo "$coords" | cut -d'|' -f1)
local longitude=$(echo "$coords" | cut -d'|' -f2)

# Process long video event
process_nostr_long_video_event "$pubkey" "$event_id" "$title" "$content" "$duration" "$latitude" "$longitude"

# UMAP Follow functionality for long video events
activate_umap_follow_for_long_video() {
    local pubkey="$1"
    local latitude="$2"
    local longitude="$3"
    local application="$4"
    local url="$5"
    
    # Only activate UMAP follow for videos with location data
    if [[ -n "$latitude" && -n "$longitude" && "$latitude" != "0.00" && "$longitude" != "0.00" ]]; then
        log_long_video "UMAP_FOLLOW: Activating UMAP follow for long video at $latitude,$longitude"
        
        # Get UMAP coordinates (rounded to 0.01° precision)
        local umap_lat=$(printf "%.2f" "$latitude")
        local umap_lon=$(printf "%.2f" "$longitude")
        
        # Generate UMAP NSEC for this location
        local umap_nsec=$($HOME/.zen/Astroport.ONE/tools/keygen -t nostr "${UPLANETNAME}${umap_lat}" "${UPLANETNAME}${umap_lon}" -s)
        
        if [[ -n "$umap_nsec" ]]; then
            # Get UMAP pubkey
            local umap_pubkey=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$umap_nsec")
            
            if [[ -n "$umap_pubkey" ]]; then
                log_long_video "UMAP_FOLLOW: UMAP pubkey for $umap_lat,$umap_lon: $umap_pubkey"
                
                # Follow the UMAP from the video publisher
                if [[ -n "$pubkey" && "$pubkey" != "$umap_pubkey" ]]; then
                    # Get publisher's NSEC (if available in MULTIPASS)
                    local publisher_nsec=""
                    local publisher_email=$(get_key_email "$pubkey")
                    
                    if [[ -n "$publisher_email" ]]; then
                        publisher_nsec=$(cat "$KEY_DIR/$publisher_email/NSEC" 2>/dev/null)
                    fi
                    
                    if [[ -n "$publisher_nsec" ]]; then
                        log_long_video "UMAP_FOLLOW: Following UMAP $umap_pubkey from publisher $pubkey"
                        
                        # Use nostr_follow.sh to follow the UMAP
                        $HOME/.zen/Astroport.ONE/tools/nostr_follow.sh "$publisher_nsec" "$umap_pubkey" "$myRELAY" 2>/dev/null
                        
                        if [[ $? -eq 0 ]]; then
                            log_long_video "UMAP_FOLLOW: Successfully followed UMAP $umap_pubkey"
                        else
                            log_long_video "UMAP_FOLLOW: Failed to follow UMAP $umap_pubkey"
                        fi
                    else
                        log_long_video "UMAP_FOLLOW: No NSEC found for publisher $pubkey, cannot follow UMAP"
                    fi
                else
                    log_long_video "UMAP_FOLLOW: Publisher is the same as UMAP, no follow needed"
                fi
            else
                log_long_video "UMAP_FOLLOW: Failed to get UMAP pubkey for $umap_lat,$umap_lon"
            fi
        else
            log_long_video "UMAP_FOLLOW: Failed to generate UMAP NSEC for $umap_lat,$umap_lon"
        fi
    else
        log_long_video "UMAP_FOLLOW: No location data, skipping UMAP follow"
    fi
}

# Activate UMAP follow for this long video event
activate_umap_follow_for_long_video "$pubkey" "$latitude" "$longitude" "$application" "$url"

log_long_video "=== LONG VIDEO EVENT PROCESSING END ==="

# Always accept long video events (they are logged but not blocked)
exit 0
