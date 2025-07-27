#!/bin/bash
# filter/1.sh
MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Extraire les informations nécessaires de l'événement JSON passé en argument en une seule fois
event_json="$1"

# Optimisation: extraire toutes les valeurs en un seul appel jq
eval $(echo "$event_json" | jq -r '
    "created_at=" + (.event.created_at | tostring) + ";" +
    "event_id=" + .event.id + ";" +
    "content=" + (.event.content | @sh) + ";" +
    "pubkey=" + .event.pubkey + ";" +
    "application=" + ((.event.tags[] | select(.[0] == "application") | .[1]) // "null") + ";" +
    "url=" + ((.event.tags[] | select(.[0] == "url") | .[1]) // "null") + ";" +
    "latitude=" + ((.event.tags[] | select(.[0] == "latitude") | .[1]) // "") + ";" +
    "longitude=" + ((.event.tags[] | select(.[0] == "longitude") | .[1]) // "")
')

# Initialize full_content with content if not already set
[[ -z "$full_content" ]] && full_content="$content"

# Source my.sh once at the beginning to get all necessary variables
source $HOME/.zen/Astroport.ONE/tools/my.sh 2>/dev/null

############################################################
# Variables pour la gestion du message "Hello NOSTR visitor"
BLACKLIST_FILE="$HOME/.zen/strfry/blacklist.txt"
COUNT_DIR="$HOME/.zen/strfry/pubkey_counts"
WARNING_MESSAGES_DIR="$HOME/.zen/strfry/warning_messages"
MESSAGE_LIMIT=3

# Variables pour la gestion de la file d'attente des traitements #BRO or #BOT
QUEUE_DIR="$HOME/.zen/tmp/uplanet_queue"
mkdir -p "$QUEUE_DIR" "$WARNING_MESSAGES_DIR"
MAX_QUEUE_SIZE=5
PROCESS_TIMEOUT=300  # 5 minutes timeout for processing
QUEUE_CLEANUP_AGE=3600  # 1 hour for queue file cleanup
WARNING_MESSAGE_TTL=172800  # 48 heures en secondes

# Fonction optimisée pour vérifier si une clé est autorisée et charger les variables de GPS
KEY_DIR="$HOME/.zen/game/nostr"
get_key_directory() {
    local pubkey="$1"
    
    # Optimisation: utiliser cat/grep au lieu de find
    if cat "$KEY_DIR"/*/HEX 2>/dev/null | grep -q "^$pubkey$"; then
        # Trouver le répertoire spécifique
        local key_dir=$(grep -l "^$pubkey$" "$KEY_DIR"/*/HEX 2>/dev/null | head -1 | xargs dirname)
        if [[ -n "$key_dir" ]]; then
            source "$key_dir/GPS" 2>/dev/null ## get NOSTR Card default LAT / LON
            [[ "$latitude" == "" ]] && latitude="$LAT"
            [[ "$longitude" == "" ]] && longitude="$LON"
            KNAME=$(basename "$key_dir") # GLOBAL VARIABLE containing the email of the player
            return 0 # Clé autorisée
        fi
    fi
    KNAME=""
    return 1 # Clé non autorisée
}

######################################################
## CLASSIFY MESSAGE INCOMER
## CHECK if Nobody, Nostr Player Card, CAPTAIN or UPlanet Geo key
if ! get_key_directory "$pubkey"; then
    check="nobody"
    AMISOFAMIS_FILE="${HOME}/.zen/strfry/amisOfAmis.txt"
    if [[ -f "$AMISOFAMIS_FILE" && "$pubkey" != "" ]]; then
        if grep -q "^$pubkey$" "$AMISOFAMIS_FILE"; then
            check="uplanet"
            echo "Pubkey $pubkey is in amisOfAmis.txt, setting check to uplanet" >> "$HOME/.zen/tmp/uplanet_messages.log"
        fi
    fi
else
    if [[ $KNAME =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ || $KNAME == "CAPTAIN" ]]; then
        check="player"
    else
        check="uplanet"
    fi
fi

############################################################
## UPlanet DEFAULT UMAP
[[ "$latitude" == "" ]] && latitude="0.00"
[[ "$longitude" == "" ]] && longitude="0.00"

# Détection précoce du tag #secret pour optimiser les traitements
is_secret_message=false
is_rec_message=false
memory_slot=0

if [[ "$content" == *"#secret"* ]]; then
    is_secret_message=true
    echo "SECRET message detected, will return 1 to reject event from relay" >> "$HOME/.zen/tmp/uplanet_messages.log"
fi

# Optimisation: détecter #rec et le slot en une seule fois
if [[ "$content" == *"#rec"* && "$content" != *"#rec2"* ]]; then
    is_rec_message=true
    # Detect slot tag (#1 to #12) plus efficacement
    for i in {1..12}; do
        if [[ "$content" =~ \#${i}\b ]]; then
            memory_slot=$i
            break
        fi
    done
fi

# Fonction consolidée pour la mémoire
handle_memory_storage() {
    local user_id="$KNAME"
    [[ -z "$user_id" ]] && user_id="$pubkey"
    
    # Check memory slot access
    if check_memory_slot_access "$user_id" "$memory_slot"; then
        echo "SHORT_MEMORY: $event_json $latitude $longitude $memory_slot $user_id" >> "$HOME/.zen/tmp/uplanet_messages.log"
        $HOME/.zen/Astroport.ONE/IA/short_memory.py "$event_json" "$latitude" "$longitude" "$memory_slot" "$user_id"
    else
        echo "Memory access denied for user: $user_id, slot: $memory_slot" >> "$HOME/.zen/tmp/uplanet_messages.log"
        send_memory_access_denied "$pubkey" "$event_id" "$memory_slot"
    fi
}

# Fonction pour nettoyer les messages d'avertissement du Captain ayant plus de 48h
cleanup_warning_messages() {
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - WARNING_MESSAGE_TTL))

    # Source CAPTAIN's pubkey
    local CAPTAIN_PUBKEY=""
    if [[ -f "$HOME/.zen/game/nostr/$CAPTAINEMAIL/.secret.nostr" ]]; then
        source "$HOME/.zen/game/nostr/$CAPTAINEMAIL/.secret.nostr"
        CAPTAIN_PUBKEY="$HEX"
    fi

    if [[ -n "$CAPTAIN_PUBKEY" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleaning up old 'Hello NOSTR visitor' messages sent by Captain: $CAPTAIN_PUBKEY (older than $(date -d "@$cutoff_time"))" >> "$HOME/.zen/tmp/uplanet_messages.log"

        cd "$HOME/.zen/strfry"
        local messages_48h_json=$(./strfry scan \
            '{"authors":["'"$CAPTAIN_PUBKEY"'"], "until":'"$cutoff_time"', "kinds":[1]}' \
            2>/dev/null)

        local message_ids=()
        if echo "$messages_48h_json" | jq -e '.id' >/dev/null 2>&1; then
            message_ids=($(echo "$messages_48h_json" | jq -r 'select(.content | contains("Hello NOSTR visitor")) | .id'))
        fi
        cd - >/dev/null

        if [ ${#message_ids[@]} -gt 0 ]; then
            local ids_string=""
            for id in "${message_ids[@]}"; do
                ids_string+="\"$id\","
            done
            ids_string=${ids_string%,} # Remove trailing comma

            echo "$(date '+%Y-%m-%d %H:%M:%S') - Deleting old 'Hello NOSTR visitor' messages by ID: $ids_string" >> "$HOME/.zen/tmp/uplanet_messages.log"

            cd "$HOME/.zen/strfry"
            ./strfry delete --filter "{\"ids\":[$ids_string]}" >> "$HOME/.zen/tmp/uplanet_messages.log" 2>&1
            cd - >/dev/null
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - No old 'Hello NOSTR visitor' messages from Captain found to delete." >> "$HOME/.zen/tmp/uplanet_messages.log"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Warning: CAPTAIN_PUBKEY not found/set. Skipping global warning message cleanup." >> "$HOME/.zen/tmp/uplanet_messages.log"
    fi

    # Cleanup of individual warning tracking files (if older than TTL)
    for warning_file in "$WARNING_MESSAGES_DIR"/*; do
        [[ ! -f "$warning_file" ]] && continue

        local file_time=$(stat -c %Y "$warning_file" 2>/dev/null)
        [[ -z "$file_time" ]] && continue

        if [ $((current_time - file_time)) -gt $WARNING_MESSAGE_TTL ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleaning up 48h old warning tracking file for pubkey: $(basename "$warning_file")" >> "$HOME/.zen/tmp/uplanet_messages.log"
            rm -f "$warning_file"
        fi
    done
}

# Fonction pour vérifier et gérer le message "Hello NOSTR visitor"
handle_visitor_message() {
    local pubkey="$1"
    local event_id="$2"

    # Nettoyer les anciens messages d'avertissement
    cleanup_warning_messages &

    # Créer le répertoire de comptage si inexistant
    mkdir -p "$COUNT_DIR"

    # Vérifier si la clé publique est déjà blacklistée (should be done before calling 1.sh)
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
        #~ echo "Creating UPlanet️ ♥️BOX Captain NOSTR response..." sub process
        source $HOME/.zen/game/nostr/$CAPTAINEMAIL/.secret.nostr ## CAPTAIN SPEAKING
        if [[ "$pubkey" != "$HEX" && "$NSEC" != "" ]]; then
            NPRIV_HEX=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$NSEC")
            echo "Notice: Astroport Relay Anonymous Usage" >> "$HOME/.zen/tmp/uplanet_messages.log"
            
            local ORIGIN="ORIGIN"
            [[ "$UPLANETNAME" != "EnfinLibre" ]] && ORIGIN=${UPLANETG1PUB:0:8}
            
            nprofile=$($HOME/.zen/Astroport.ONE/tools/nostr_hex2nprofile.sh "$pubkey" 2>/dev/null)
            RESPN="Hello NOSTR visitor.

$nprofile, we noticed that you're using our Relay without being registered on our #Ğ1 Web of Trust.

You have $remaining_messages message(s) left before being automatically blocked. Please join our self-sovereign community to avoid interruption.

Take place on #UPlanet : $myIPFS/ipns/copylaradio.com
Get a #MULTIPASS

Your devoted Astroport Captain.

#CopyLaRadio #mem
#♥️BOX [$myRELAY]
#UPlanet:$ORIGIN:
"

            # Envoyer le message d'avertissement et récupérer l'ID du message
            WARNING_MSG_OUTPUT=$(nostpy-cli send_event \
              -privkey "$NPRIV_HEX" \
              -kind 1 \
              -content "$RESPN" \
              -tags "[['e', '$event_id'], ['p', '$pubkey'], ['t', 'Warning']]" \
              --relay "$myRELAY" 2>&1)

            # Extraire l'ID du message d'avertissement de la sortie (si disponible)
            WARNING_MSG_ID=$(echo "$WARNING_MSG_OUTPUT" | grep -oE '"id":"[a-f0-9]{64}"' | sed 's/"id":"\([^"]*\)"/\1/' | head -1)

            # Update the warning file timestamp
            touch "$warning_file"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Warning message sent (ID: $WARNING_MSG_ID) and tracked for pubkey: $pubkey" >> "$HOME/.zen/tmp/uplanet_messages.log"
            echo "$WARNING_MSG_OUTPUT" >> "$HOME/.zen/tmp/uplanet_messages.log"
        fi
        ) &
    else
        echo "Visitor limit reached for pubkey $pubkey. Removing Messages & Blacklisting."
        cd ~/.zen/strfry
        ./strfry delete --filter "{\"authors\":[\"$pubkey\"]}"
        cd -
        echo "$pubkey" >> "$BLACKLIST_FILE"
        rm -f "$warning_file"
    fi
    return 0
}

# Function to check if user has access to memory slots 1-12
check_memory_slot_access() {
    local user_id="$1"
    local slot="$2"
    
    # Slot 0 is always accessible
    [[ "$slot" == "0" ]] && return 0
    
    # For slots 1-12, check if user is in ~/.zen/game/players/
    if [[ "$slot" -ge 1 && "$slot" -le 12 ]]; then
        [[ -d "$HOME/.zen/game/players/$user_id" ]] && return 0 || return 1
    fi
    
    return 0  # Default allow for other cases
}

# Function to send memory access denied message
send_memory_access_denied() {
    local pubkey="$1"
    local event_id="$2"
    local slot="$3"
    
    (
    source $HOME/.zen/game/nostr/$CAPTAINEMAIL/.secret.nostr ## CAPTAIN SPEAKING
    if [[ "$pubkey" != "$HEX" && "$NSEC" != "" ]]; then
        NPRIV_HEX=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$NSEC")
        
        DENIED_MSG="⚠️ Accès refusé aux slots de mémoire 1-12.

Pour utiliser les slots de mémoire 1-12, vous devez être sociétaire CopyLaRadio ou posséder une ZenCard.

Le slot 0 reste accessible à tous les utilisateurs MULTIPASS.

Pour devenir sociétaire : https://opencollective.com/uplanet-zero

Votre dévoué Capitaine Astroport.
#CopyLaRadio #UPlanet"

        nostpy-cli send_event \
          -privkey "$NPRIV_HEX" \
          -kind 1 \
          -content "$DENIED_MSG" \
          -tags "[['e', '$event_id'], ['p', '$pubkey'], ['t', 'MemoryAccessDenied']]" \
          --relay "$myRELAY" 2>/dev/null
    fi
    ) &
}

# Fonctions optimisées pour la gestion de la file d'attente
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
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Killed stuck UPlanet_IA_Responder.sh process $pid" >> "$HOME/.zen/tmp/uplanet_messages.log"
            fi
        fi
    done
}

# Fonction pour créer un fichier de queue
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

# Fonction principale pour traiter la file d'attente - simplifiée
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
                echo "Queue is full, message dropped: $event_id" >> "$HOME/.zen/tmp/uplanet_messages.log"
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
        # Vérification anti-doublon optimisée
        [[ -f "$COUNT_DIR/lastevent" && "$(cat "$COUNT_DIR/lastevent")" == "$event_id" ]] && exit 0

        echo "OK Authorized key : $KNAME" >> "$HOME/.zen/tmp/uplanet_messages.log"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - UPlanet Message - Lat: $latitude, Lon: $longitude, Content: $full_content" >> "$HOME/.zen/tmp/uplanet_messages.log"

        # Check if process is running
        if pgrep -f "UPlanet_IA_Responder.sh" > /dev/null; then
            local queue_size=$(ls -1 $QUEUE_DIR/ 2>/dev/null | wc -l)
            if [ "$queue_size" -lt "$MAX_QUEUE_SIZE" ]; then
                create_queue_file
                echo "QUEUE_FILE: $QUEUE_FILE" >> "$HOME/.zen/tmp/uplanet_messages.log"
            else
                echo "Queue is full, message dropped: $event_id" >> "$HOME/.zen/tmp/uplanet_messages.log"
            fi
        else
            echo "PROCESSING UPlanet_IA_Responder.sh $pubkey $event_id $latitude $longitude $full_content $url $KNAME" >> "$HOME/.zen/tmp/IA.log"
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
    handle_visitor_message "$pubkey" "$event_id"
    exit 0
fi

exit 0
