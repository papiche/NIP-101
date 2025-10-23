#!/bin/bash
# filter/1.sh (OPTIMIZED)
MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Source common functions
source "$MY_PATH/common.sh"

# Extract event data using optimized common function
event_json="$1"
extract_event_data "$event_json"

# Extract UPlanet-specific tags
extract_tags "$event_json" "application" "url" "latitude" "longitude" "g"
application="$application"
url="$url"
latitude="$latitude"
longitude="$longitude"

# Extract coordinates from "g" tag if latitude/longitude not directly provided
# Format: ["g", "lat,lon"] (standard Nostr geolocation tag)
if [[ -z "$latitude" || -z "$longitude" ]] && [[ -n "$g" ]]; then
    latitude=$(echo "$g" | cut -d',' -f1 | xargs)
    longitude=$(echo "$g" | cut -d',' -f2 | xargs)
    log_uplanet "Extracted coordinates from 'g' tag: lat=$latitude, lon=$longitude"
fi

# Initialize full_content with content if not already set
[[ -z "$full_content" ]] && full_content="$content"

############################################################
# Variables pour la gestion du message "Hello NOSTR visitor"
BLACKLIST_FILE="$HOME/.zen/strfry/blacklist.txt"
COUNT_DIR="$HOME/.zen/strfry/pubkey_counts"
WARNING_MESSAGES_DIR="$HOME/.zen/strfry/warning_messages"
MESSAGE_LIMIT=3
VISITOR_MESSAGE_EXPIRY=86400  # 24 hours in seconds for visitor messages

# Variables pour la gestion de la file d'attente des traitements #BRO or #BOT
QUEUE_DIR="$HOME/.zen/tmp/uplanet_queue"
mkdir -p "$QUEUE_DIR" "$WARNING_MESSAGES_DIR"
MAX_QUEUE_SIZE=5
PROCESS_TIMEOUT=300  # 5 minutes timeout for processing
QUEUE_CLEANUP_AGE=3600  # 1 hour for queue file cleanup
WARNING_MESSAGE_TTL=172800  # 48 heures en secondes

# Logging functions using common utilities
log_uplanet() {
    log_with_timestamp "$HOME/.zen/tmp/nostr_kind1_messages.log" "$1"
}

log_ia() {
    log_with_timestamp "$HOME/.zen/tmp/IA.log" "$1"
}

# Ensure log directories exist
ensure_log_dir "$HOME/.zen/tmp/nostr_kind1_messages.log"
ensure_log_dir "$HOME/.zen/tmp/IA.log"

# Optimized function to get key directory with GPS handling
get_key_directory_with_gps() {
    local pubkey="$1"
    
    # Use common function to get email
    local email=$(get_key_email "$pubkey")
    if [[ -n "$email" ]]; then
        # Load GPS data from the specific directory
        local key_dir="$KEY_DIR/$email"
        LAT=""; LON=""; ## reset old global values
        source "$key_dir/GPS" 2>/dev/null ## get NOSTR Card default LAT / LON
        [[ "$latitude" == "" ]] && latitude="$LAT"
        [[ "$longitude" == "" ]] && longitude="$LON"
        KNAME="$email" # GLOBAL VARIABLE containing the email of the player
        return 0 # Clé autorisée
    fi
    KNAME=""
    return 1 # Clé non autorisée
}

######################################################
## CLASSIFY MESSAGE INCOMER
## CHECK if Nobody, Nostr Player Card, CAPTAIN or UPlanet Geo key
## First check if it's a local NOSTR account (MULTIPASS)
if get_key_directory_with_gps "$pubkey"; then
    # Local NOSTR account found
    if [[ $KNAME =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ || $KNAME == "CAPTAIN" ]]; then
        check="player"
        log_uplanet "Local NOSTR player account: $KNAME"
    else
        check="uplanet"
        log_uplanet "Local NOSTR UPlanet account: $KNAME"
    fi
else
    # Not a local account, check amisOfAmis
    check="nobody"
    if check_amis_of_amis "$pubkey"; then
        check="uplanet"
        log_uplanet "Pubkey $pubkey is in amisOfAmis.txt, setting check to uplanet"
    fi
fi

############################################################
## UPlanet DEFAULT UMAP
[[ "$latitude" == "" ]] && latitude="0.00"
[[ "$longitude" == "" ]] && longitude="0.00"

# Optimized early tag detection
is_secret_message=false
is_rec_message=false
memory_slot=0

# Early detection optimizations
if [[ "$content" == *"#secret"* ]]; then
    is_secret_message=true
    log_uplanet "SECRET message detected, will return 1 to reject event from relay"
fi

# Detect #rec and slot in one pass
if [[ "$content" == *"#rec"* && "$content" != *"#rec2"* ]]; then
    is_rec_message=true
    # Detect slot tag (#1 to #12) efficiently
    for i in {1..12}; do
        if [[ "$content" =~ \#${i}\b ]]; then
            memory_slot=$i
            break
        fi
    done
fi

# PlantNet detection (handled by UPlanet_IA_Responder.sh)
is_plantnet_message=false
if [[ "$content" == *"#plantnet"* ]]; then
    is_plantnet_message=true
    log_uplanet "PLANTNET message detected - will be processed by UPlanet_IA_Responder.sh"
fi

# Consolidated memory handling function
handle_memory_storage() {
    local user_id="$KNAME"
    [[ -z "$user_id" ]] && user_id="$pubkey"
    
    # Check memory slot access
    if check_memory_slot_access "$user_id" "$memory_slot"; then
        log_uplanet "SHORT_MEMORY: $event_json $latitude $longitude $memory_slot $user_id"
        $HOME/.zen/Astroport.ONE/IA/short_memory.py "$event_json" "$latitude" "$longitude" "$memory_slot" "$user_id"
    else
        log_uplanet "Memory access denied for user: $user_id, slot: $memory_slot"
        send_memory_access_denied "$pubkey" "$event_id" "$memory_slot"
    fi
}

# Optimized cleanup function with better logging
cleanup_warning_messages() {
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - WARNING_MESSAGE_TTL))

    # Use UMAP 0.00,0.00 pubkey for cleanup
    local UMAP_PUBKEY=""
    local UMAPNSEC=$($HOME/.zen/Astroport.ONE/tools/keygen -t nostr "${UPLANETNAME}0.00" "${UPLANETNAME}0.00" -s)
    if [[ -n "$UMAPNSEC" ]]; then
        UMAP_PUBKEY=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$UMAPNSEC")
        if [[ -z "$UMAP_PUBKEY" ]]; then
            log_uplanet "Warning: Failed to convert UMAP NSEC to HEX for cleanup"
            return 1
        fi
    else
        log_uplanet "Warning: Failed to generate UMAP NSEC for cleanup"
        return 1
    fi

    if [[ -n "$UMAP_PUBKEY" ]]; then
        log_uplanet "Cleaning up old visitor messages sent by UMAP 0.00,0.00: $UMAP_PUBKEY (older than $(date -d "@$cutoff_time"))"

        cd "$HOME/.zen/strfry"
        # Search for both "Hello NOSTR visitor" and BRO response messages from UMAP 0.00,0.00
        local messages_48h_json=$(./strfry scan \
            '{"authors":["'"$UMAP_PUBKEY"'"], "until":'"$cutoff_time"', "kinds":[1]}' \
            2>/dev/null)

        local message_ids=()
        if echo "$messages_48h_json" | jq -e '.id' >/dev/null 2>&1; then
            # Find messages containing "Hello NOSTR visitor" or BRO responses
            message_ids=($(echo "$messages_48h_json" | jq -r 'select(.content | contains("Hello NOSTR visitor") or (.tags[] | select(.[0] == "t" and .[1] == "BRO"))) | .id'))
        fi
        cd - >/dev/null

        if [ ${#message_ids[@]} -gt 0 ]; then
            local ids_string=""
            for id in "${message_ids[@]}"; do
                ids_string+="\"$id\","
            done
            ids_string=${ids_string%,} # Remove trailing comma

            log_uplanet "Deleting old visitor messages by ID: $ids_string"

            cd "$HOME/.zen/strfry"
            ./strfry delete --filter "{\"ids\":[$ids_string]}" >> "$HOME/.zen/tmp/nostr_kind1_messages.log" 2>&1
            cd - >/dev/null
        else
            log_uplanet "No old visitor messages from UMAP 0.00,0.00 found to delete."
        fi
    else
        log_uplanet "Warning: UMAP 0.00,0.00 key not found/set. Skipping visitor message cleanup."
    fi

    # Cleanup of individual warning tracking files (if older than TTL)
    for warning_file in "$WARNING_MESSAGES_DIR"/*; do
        [[ ! -f "$warning_file" ]] && continue

        local file_time=$(stat -c %Y "$warning_file" 2>/dev/null)
        [[ -z "$file_time" ]] && continue

        if [ $((current_time - file_time)) -gt $WARNING_MESSAGE_TTL ]; then
            log_uplanet "Cleaning up 48h old warning tracking file for pubkey: $(basename "$warning_file")"
            rm -f "$warning_file"
        fi
    done
}

# Optimized visitor message handling
handle_visitor_message() {
    local pubkey="$1"
    local event_id="$2"
    local visitor_content="$3"

    # Nettoyer les anciens messages d'avertissement
    cleanup_warning_messages &

    # Créer le répertoire de comptage si inexistant
    mkdir -p "$COUNT_DIR" 2>/dev/null

    # Vérifier si la clé publique est déjà blacklistée
    if grep -q "^$pubkey$" "$BLACKLIST_FILE" 2>/dev/null; then
        echo "Pubkey $pubkey is blacklisted, skipping visitor message."
        return 0
    fi

    local count_file="$COUNT_DIR/$pubkey"
    local warning_file="$WARNING_MESSAGES_DIR/$pubkey"

    # Initialiser le compteur à 0 si le fichier n'existe pas
    local current_count=0
    [[ -f "$count_file" ]] && current_count=$(cat "$count_file")

    local next_count=$((current_count + 1))
    local remaining_messages=$((MESSAGE_LIMIT - next_count))

    echo "$next_count" > "$count_file"

    if [[ "$next_count" -le "$MESSAGE_LIMIT" ]]; then
        (
        # Use UMAP 0.00,0.00 key for visitor messages instead of captain key
        UMAPNSEC=$($HOME/.zen/Astroport.ONE/tools/keygen -t nostr "${UPLANETNAME}0.00" "${UPLANETNAME}0.00" -s)
        NPRIV_HEX=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$UMAPNSEC")
        if [[ "$pubkey" != "$NPRIV_HEX" && "$UMAPNSEC" != "" ]]; then
            log_uplanet "Notice: Astroport Relay Anonymous Usage (UMAP 0.00,0.00)"
            
            local ORIGIN="ORIGIN"
            [[ "$UPLANETNAME" != "EnfinLibre" ]] && ORIGIN=${UPLANETG1PUB:0:8}
            
            nprofile=$($HOME/.zen/Astroport.ONE/tools/nostr_hex2nprofile.sh "$pubkey" 2>/dev/null)
            # Get captain nprofile once to avoid repeated calls
            CAPTAIN_NPROFILE=$($HOME/.zen/Astroport.ONE/tools/nostr_hex2nprofile.sh "$CAPTAINHEX" 2>/dev/null)
            if [[ -z "$CAPTAIN_NPROFILE" ]]; then
                log_uplanet "Warning: Failed to get captain nprofile for $CAPTAINHEX"
                CAPTAIN_NPROFILE="unknown_captain"
            fi
            RESPN="Hello NOSTR visitor.

$nprofile, we noticed that you're using our Relay without being registered on our #Ğ1 Web of Trust.

You have $remaining_messages message(s) left before being automatically blocked. Please join our self-sovereign community to avoid interruption.

🌍 UMAP 0.00,0.00 - Global Meeting Point
This message comes from the global UMAP (0.00,0.00), the meeting point for users without GPS coordinates who cannot benefit from localized UMAP journals. This is where non-geolocated messages are collected and shared.

Take place on #UPlanet : $myIPFS/ipns/copylaradio.com
Get a #MULTIPASS to access localized content

#UMAP_0.00_0.00
#UPlanet:$ORIGIN
#Captain:$CAPTAIN_NPROFILE
#♥️BOX [$myRELAY]
"

            # Calculate expiration timestamp (current time + expiry duration)
            EXPIRY_TIMESTAMP=$(($(date +%s) + VISITOR_MESSAGE_EXPIRY))
            log_uplanet "⏰ Visitor message will expire at: $(date -d "@$EXPIRY_TIMESTAMP") (${VISITOR_MESSAGE_EXPIRY}s from now)"
            
            # Envoyer le message d'avertissement avec expiration
            WARNING_MSG_OUTPUT=$(nostpy-cli send_event \
              -privkey "$NPRIV_HEX" \
              -kind 1 \
              -content "$RESPN" \
              -tags "[['e', '$event_id'], ['p', '$pubkey'], ['t', 'Warning'], ['expiration', '$EXPIRY_TIMESTAMP']]" \
              --relay "$myRELAY" 2>&1)

            # Extraire l'ID du message d'avertissement
            WARNING_MSG_ID=$(echo "$WARNING_MSG_OUTPUT" | grep -oE "'id': '[a-f0-9]{64}'" | cut -d"'" -f4 | head -n 1)

            # Update the warning file timestamp
            touch "$warning_file"
            log_uplanet "Warning message sent (ID: $WARNING_MSG_ID) and tracked for pubkey: $pubkey"
            log_uplanet "$WARNING_MSG_OUTPUT"
            
            # Send automatic BRO response after visitor warning (only for first message)
            if [[ -n "$WARNING_MSG_ID" && "$next_count" == "1" ]]; then
                log_uplanet "Sending automatic BRO response for visitor: $pubkey"
                
                # Generate intelligent BRO response using AstroBot personas
                if [[ -n "$visitor_content" ]]; then
                    # Use AstroBot persona selector for personalized response
                    BRO_RESPONSE_CONTENT=$($MY_PATH/astrobot_visitor_response.py \
                      "$pubkey" \
                      "$visitor_content" \
                      2>/dev/null)
                else
                    # Fallback for empty content
                    BRO_RESPONSE_CONTENT=$($MY_PATH/astrobot_visitor_response.py \
                      "$pubkey" \
                      "Hello" \
                      2>/dev/null)
                fi
                
                # Add captain reference and UMAP explanation to AI-generated response
                if [[ -n "$BRO_RESPONSE_CONTENT" && "$BRO_RESPONSE_CONTENT" != *"ERROR"* ]]; then
                    BRO_RESPONSE_CONTENT="$BRO_RESPONSE_CONTENT

🌍 I'm speaking from UMAP_0.00_0.00 - the global meeting point for users without GPS coordinates.

#Captain:$CAPTAIN_NPROFILE
#UMAP_0.00_0.00"
                fi
                
                # Fallback if AI response fails
                if [[ -z "$BRO_RESPONSE_CONTENT" || "$BRO_RESPONSE_CONTENT" == *"ERROR"* ]]; then
                    BRO_RESPONSE_CONTENT="Hello visitor! I'm AstroBot, UPlanet AI assistant. I noticed you're new here. Would you like to learn more about our community? Feel free to ask me anything about #UPlanet, #CopyLaRadio, or how to get started!

🌍 I'm speaking from UMAP_0.00_0.00 - the global meeting point for users without GPS coordinates. This is where non-geolocated messages are collected and shared.

#Captain:$CAPTAIN_NPROFILE
#UMAP_0.00_0.00"
                fi
                
                # Send BRO response as UMAP 0.00,0.00
                BRO_MSG_OUTPUT=$(nostpy-cli send_event \
                  -privkey "$NPRIV_HEX" \
                  -kind 1 \
                  -content "$BRO_RESPONSE_CONTENT" \
                  -tags "[['e', '$event_id'], ['p', '$pubkey'], ['t', 'BRO'], ['t', 'VisitorWelcome'], ['expiration', '$EXPIRY_TIMESTAMP']]" \
                  --relay "$myRELAY" 2>&1)
                
                BRO_MSG_ID=$(echo "$BRO_MSG_OUTPUT" | grep -oE "'id': '[a-f0-9]{64}'" | cut -d"'" -f4 | head -n 1)
                log_uplanet "BRO response sent (ID: $BRO_MSG_ID) for visitor: $pubkey"
                log_uplanet "$BRO_MSG_OUTPUT"
            fi
        fi
        ) &
    else
        echo "Visitor limit reached for pubkey $pubkey. Removing Messages & Blacklisting."
        cd ~/.zen/strfry
        ./strfry delete --filter "{\"authors\":[\"$pubkey\"]}"
        cd -
        echo "$pubkey" >> "$BLACKLIST_FILE"
        rm -f "$warning_file"
        rm -f "$count_file"
    fi
    return 0
}

# Optimized queue management functions
cleanup_old_queue_files() {
    find "$QUEUE_DIR" -type f -mmin +60 -delete 2>/dev/null
}

check_stuck_processes() {
    local current_time=$(date +%s)
    for pid in $(pgrep -f "UPlanet_IA_Responder.sh"); do
        local process_start=$(ps -p $pid -o lstart= 2>/dev/null)
        if [ -n "$process_start" ]; then
            local start_time=$(date -d "$process_start" +%s 2>/dev/null)
            if [ $? -eq 0 ] && [ $((current_time - start_time)) -gt $PROCESS_TIMEOUT ]; then
                kill -9 $pid 2>/dev/null
                log_uplanet "Killed stuck UPlanet_IA_Responder.sh process $pid"
            fi
        fi
    done
}

# Optimized queue file creation
create_queue_file() {
    QUEUE_FILE="$QUEUE_DIR/${pubkey}.sh"
    cat > "$QUEUE_FILE" << EOF
pubkey="$pubkey"
event_id="$event_id"
latitude="$latitude"
longitude="$longitude"
full_content="$full_content"
url="$url"
KNAME="$KNAME"
EOF
}

# Streamlined queue processing
process_queue() {
    cleanup_old_queue_files
    check_stuck_processes

    [[ -z "$(ls -A $QUEUE_DIR/ 2>/dev/null)" ]] && return 0

    # Check if process is already running
    if pgrep -f "UPlanet_IA_Responder.sh" > /dev/null; then
        # Only queue if content contains #BRO or #BOT
        if [[ "$full_content" == *"#BRO"* || "$full_content" == *"#BOT"* ]]; then
            local queue_size=$(ls -1 $QUEUE_DIR/ 2>/dev/null | wc -l)
            if [ "$queue_size" -lt "$MAX_QUEUE_SIZE" ]; then
                create_queue_file
            else
                log_uplanet "Queue is full, message dropped: $event_id"
            fi
        fi
        
        # Handle memory storage
        [[ "$is_rec_message" == true ]] && handle_memory_storage
        exit 0
    else
        # Launch process directly
        local secret_flag=""
        [[ "$is_secret_message" == true ]] && secret_flag="--secret"
        
        timeout $PROCESS_TIMEOUT $HOME/.zen/Astroport.ONE/IA/UPlanet_IA_Responder.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$full_content" "$url" "$KNAME" $secret_flag &
    fi
}

################# MAIN TREATMENT
process_queue

if [[ "$check" != "nobody" ]]; then
    # UPlanet APP NOSTR messages.
    if [[ -n "$latitude" && -n "$longitude" && "$check" != "uplanet" && ("$content" == *"#BRO"* || "$content" == *"#BOT"*) ]]; then
        # Optimized anti-duplicate check
        [[ -f "$COUNT_DIR/lastevent" && "$(cat "$COUNT_DIR/lastevent")" == "$event_id" ]] && exit 0

        log_uplanet "OK Authorized key : $KNAME"
        log_uplanet "UPlanet Message - Lat: $latitude, Lon: $longitude, Content: $full_content"

        # Check if process is running
        if pgrep -f "UPlanet_IA_Responder.sh" > /dev/null; then
            local queue_size=$(ls -1 $QUEUE_DIR/ 2>/dev/null | wc -l)
            if [ "$queue_size" -lt "$MAX_QUEUE_SIZE" ]; then
                create_queue_file
                log_uplanet "QUEUE_FILE: $QUEUE_FILE"
            else
                log_uplanet "Queue is full, message dropped: $event_id"
            fi
        else
            log_ia "PROCESSING UPlanet_IA_Responder.sh $pubkey $event_id $latitude $longitude $full_content $url $KNAME"
            local secret_flag=""
            [[ "$is_secret_message" == true ]] && secret_flag="--secret"
            
            timeout $PROCESS_TIMEOUT $HOME/.zen/Astroport.ONE/IA/UPlanet_IA_Responder.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$full_content" "$url" "$KNAME" $secret_flag 2>&1 >> "$HOME/.zen/tmp/IA.log" &
        fi

        echo "$event_id" > "$COUNT_DIR/lastevent"
        [[ "$is_rec_message" == true ]] && handle_memory_storage

        # Return appropriately for secret messages
        [[ "$is_secret_message" == true ]] && exit 1 || exit 0
    else
        # Handle memory for other authorized users
        [[ "$is_rec_message" == true ]] && handle_memory_storage
        exit 0
    fi
else
    # Visitor NOSTR message reply
    # Only respond if message contains more than 50 characters
    content_length=${#content}
    if [[ $content_length -le 50 ]]; then
        log_uplanet "Message from nobody ($pubkey) too short ($content_length chars), rejecting without response"
        exit 1  # Reject message without responding
    fi
    
    handle_visitor_message "$pubkey" "$event_id" "$content"
    exit 0
fi

exit 0
