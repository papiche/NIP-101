#!/bin/bash
# filter/1.sh
MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Extraire les informations nécessaires de l'événement JSON passé en argument
event_json="$1"

created_at=$(echo "$event_json" | jq -r '.event.created_at')
event_id=$(echo "$event_json" | jq -r '.event.id')
content=$(echo "$event_json" | jq -r '.event.content')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
tags=$(echo "$event_json" | jq -r '.event.tags')
application=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "application") | .[1]')
url=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "url") | .[1]')
latitude=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "latitude") | .[1]')
longitude=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "longitude") | .[1]')

############################################################
# Variables pour la gestion du message "Hello NOSTR visitor"
BLACKLIST_FILE="$HOME/.zen/strfry/blacklist.txt"
COUNT_DIR="$HOME/.zen/strfry/pubkey_counts"
WARNING_MESSAGES_DIR="$HOME/.zen/strfry/warning_messages"
MESSAGE_LIMIT=3

# Variables pour la gestion de la file d'attente des traitements #BRO or #BOT
QUEUE_DIR="$HOME/.zen/tmp/uplanet_queue"
mkdir -p "$QUEUE_DIR"
mkdir -p "$WARNING_MESSAGES_DIR"
MAX_QUEUE_SIZE=5
PROCESS_TIMEOUT=300  # 5 minutes timeout for processing
QUEUE_CLEANUP_AGE=3600  # 1 hour for queue file cleanup
WARNING_MESSAGE_TTL=172800  # 48 heures en secondes

# Fonction pour vérifier si une clé est autorisée et charger les variables de GPS
KEY_DIR="$HOME/.zen/game/nostr"
get_key_directory() {
    local pubkey="$1"
    local key_file
    local found_dir=""

    while IFS= read -r -d $'\0' key_file; do
        if [[ "$pubkey" == "$(cat "$key_file")" ]]; then
            # Extraire le dernier répertoire du chemin
            source $(dirname "$key_file")/GPS 2>/dev/null ## get NOSTR Card default LAT / LON
            [[ "$latitude" == "" ]] && latitude="$LAT"
            [[ "$longitude" == "" ]] && longitude="$LON"
            KNAME=$(basename "$(dirname "$key_file")")
            return 0 # Clé autorisée
        fi
    done < <(find "$KEY_DIR" -type f -name "HEX" -print0)
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
###################################################### TEMP
############################################################

# Fonction pour nettoyer les messages d'avertissement du Captain ayant plus de 48h
cleanup_warning_messages() {
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - WARNING_MESSAGE_TTL))

    # Source CAPTAIN's pubkey
    local CAPTAIN_PUBKEY=""
    if [[ -f "$HOME/.zen/game/players/.current/secret.nostr" ]]; then
        source "$HOME/.zen/game/players/.current/secret.nostr"
        CAPTAIN_PUBKEY="$HEX"
    fi

    if [[ -n "$CAPTAIN_PUBKEY" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleaning up old 'Hello NOSTR visitor' messages sent by Captain: $CAPTAIN_PUBKEY (older than $(date -d "@$cutoff_time"))" >> "$HOME/.zen/tmp/uplanet_messages.log"

        cd "$HOME/.zen/strfry" || { echo "Failed to cd to strfry directory." >> "$HOME/.zen/tmp/uplanet_messages.log"; return 1; }
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

            cd "$HOME/.zen/strfry" || { echo "Failed to find ~/.zen/strfry directory." >> "$HOME/.zen/tmp/uplanet_messages.log"; return 1; }
            ./strfry delete --filter "{\"ids\":[$ids_string]}" >> "$HOME/.zen/tmp/uplanet_messages.log" 2>&1
            cd - >/dev/null
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - No old 'Hello NOSTR visitor' messages from Captain found to delete." >> "$HOME/.zen/tmp/uplanet_messages.log"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Warning: CAPTAIN_PUBKEY not found/set. Skipping global warning message cleanup." >> "$HOME/.zen/tmp/uplanet_messages.log"
    fi

    # Cleanup of individual warning tracking files (if older than TTL)
    # These files are now merely markers for a recipient's warning status, not for message IDs.
    for warning_file in "$WARNING_MESSAGES_DIR"/*; do
        [[ ! -f "$warning_file" ]] && continue # Skip if not a regular file

        local file_time=$(stat -c %Y "$warning_file" 2>/dev/null)
        [[ -z "$file_time" ]] && continue # Skip if stat fails

        # If the file (marker) has been around for more than 48 hours, remove it.
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
    if grep -q "^$pubkey$" "$BLACKLIST_FILE"; then
        echo "Pubkey $pubkey is blacklisted, skipping visitor message."
        return 0 # Ne rien faire, la clé est blacklistée
    fi

    local count_file="$COUNT_DIR/$pubkey"
    local warning_file="$WARNING_MESSAGES_DIR/$pubkey"

    # Initialiser le compteur à 0 si le fichier n'existe pas
    if [[ ! -f "$count_file" ]]; then
        echo 0 > "$count_file"
    fi

    local current_count=$(cat "$count_file")
    local next_count=$((current_count + 1))
    local remaining_messages=$((MESSAGE_LIMIT - next_count))

    echo "$next_count" > "$count_file"

    if [[ "$next_count" -le "$MESSAGE_LIMIT" ]]; then
        (
        #~ echo "Creating UPlanet️ ♥️BOX Captain NOSTR response..." sub process
        source $HOME/.zen/Astroport.ONE/tools/my.sh
        source ~/.zen/game/players/.current/secret.nostr ## CAPTAIN SPEAKING
        if [[ "$pubkey" != "$HEX" && "$NSEC" != "" ]]; then
            NPRIV_HEX=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$NSEC")
            echo "Notice: Astroport Relay Anonymous Usage" >> "$HOME/.zen/tmp/uplanet_messages.log"
            if [[ "$UPLANETNAME" == "EnfinLibre" ]]; then
                ORIGIN="ORIGIN"
            else
                ORIGIN=${UPLANETG1PUB:0:8}
            fi
            RESPN="Hello NOSTR visitor.

I noticed that you're using our Relay without being registered on our #Ğ1 Web of Trust.

You have $remaining_messages message(s) left before being automatically blocked. Please join our self-sovereign community to avoid interruption.

Take place on #UPlanet : $myIPFS/ipns/copylaradio.com
Get your #MULTIPASS

Your devoted Astroport Captain.

#CopyLaRadio #mem
#♥️BOX [$myRELAY]
#UPlanet$ORIGIN
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

            # Update the warning file timestamp (no longer storing message ID)
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

        # Nettoyer aussi le fichier de suivi des messages d'avertissement
        rm -f "$warning_file"
    fi
    return 0
}

# Function to get an event by ID using strfry scan
get_event_by_id() {
    local event_id="$1"
    cd $HOME/.zen/strfry
    # Use strfry scan with a filter for the specific event ID
    ./strfry scan '{"ids":["'"$event_id"'"]}' 2>/dev/null
    cd -
}

# Fonction pour nettoyer les anciens fichiers de la file d'attente
cleanup_old_queue_files() {
    find "$QUEUE_DIR" -type f -mmin +60 -delete 2>/dev/null
}

# Fonction pour vérifier et tuer les processus bloqués
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

# Fonction pour traiter la file d'attente
process_queue() {
    # Nettoyer les anciens fichiers
    cleanup_old_queue_files

    # Vérifier les processus bloqués
    check_stuck_processes

    # Vérifier s'il y a des fichiers dans la file d'attente
    if [ -z "$(ls -A $QUEUE_DIR/)" ]; then
        return 0
    fi

    # Vérifier si UPlanet_IA_Responder.sh est déjà en cours d'exécution
    if pgrep -f "UPlanet_IA_Responder.sh" > /dev/null; then
        # Only queue if content contains #BRO or #BOT
        if [[ "$full_content" == *"#BRO"* || "$full_content" == *"#BOT"* ]]; then
            # Compter le nombre de fichiers dans la file d'attente
            queue_size=$(ls -1 $QUEUE_DIR/ 2>/dev/null | wc -l)

            # Si la file d'attente n'est pas pleine, ajouter le message
            if [ "$queue_size" -lt "$MAX_QUEUE_SIZE" ]; then
                QUEUE_FILE="$QUEUE_DIR/${pubkey}.sh" ## on écrase le fichier si il existe
                cat > "$QUEUE_FILE" << EOF
pubkey="$pubkey"
event_id="$event_id"
latitude="$latitude"
longitude="$longitude"
full_content="$full_content"
url="$url"
KNAME="$KNAME"
EOF
            else
                echo "Queue is full, message dropped: $event_id" >> "$HOME/.zen/tmp/uplanet_messages.log"
            fi
        fi
        # MEMORIZE EVENT in UMAP / PUBKEY MEMORY
        if [[ "$content" != *"#mem"* ]]; then
            $HOME/.zen/Astroport.ONE/IA/short_memory.py "$event_json" "$latitude" "$longitude"
        fi

        exit 0
    else
        # Si aucun processus n'est en cours, lancer directement avec timeout
        timeout $PROCESS_TIMEOUT $HOME/.zen/Astroport.ONE/IA/UPlanet_IA_Responder.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$full_content" "$url" "$KNAME" &
    fi
}

################# MAIN TREATMENT
if [[ -z "$full_content" ]]; then
    full_content="$content"
fi
# Traiter la file d'attente
process_queue

if [[ "$check" != "nobody" ]]; then
    # UPlanet APP NOSTR messages.
    if [[ -n "$latitude" && -n "$longitude" && "$check" != "uplanet" && "$content" == *"#BRO"* || "$content" == *"#BOT"* ]]; then
        ###########################################################
        [[ "$(cat $COUNT_DIR/lastevent)" == "$event_id" ]] \
            && exit 0 ## NO REPLY TWICE

        # Ready to process UPlanet_IA_Responder
        echo "OK Authorized key : $KNAME" >> "$HOME/.zen/tmp/uplanet_messages.log"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - UPlanet Message - Lat: $latitude, Lon: $longitude, Content: $full_content" >> "$HOME/.zen/tmp/uplanet_messages.log"

        # Vérifier si UPlanet_IA_Responder.sh est déjà en cours d'exécution
        if pgrep -f "UPlanet_IA_Responder.sh" > /dev/null; then
            # Compter le nombre de fichiers dans la file d'attente
            queue_size=$(ls -1 $QUEUE_DIR/ 2>/dev/null | wc -l)

            # Si la file d'attente n'est pas pleine, ajouter le message
            if [ "$queue_size" -lt "$MAX_QUEUE_SIZE" ]; then
                echo "QUEUE_FILE: $QUEUE_FILE" >> "$HOME/.zen/tmp/uplanet_messages.log"
                QUEUE_FILE="$QUEUE_DIR/${pubkey}.sh" ## on écrase le fichier si il existe
                cat > "$QUEUE_FILE" << EOF
pubkey="$pubkey"
event_id="$event_id"
latitude="$latitude"
longitude="$longitude"
full_content="$full_content"
url="$url"
KNAME="$KNAME"
EOF
            else
                echo "Queue is full, message dropped: $event_id" >> "$HOME/.zen/tmp/uplanet_messages.log"
            fi
        else
            # Processing UPlanet_IA_Responder
            echo "PROCESSING UPlanet_IA_Responder.sh" "$pubkey" "$event_id" "$latitude" "$longitude" "$full_content" "$url" "$KNAME" >> "$HOME/.zen/tmp/IA.log"
            timeout $PROCESS_TIMEOUT $HOME/.zen/Astroport.ONE/IA/UPlanet_IA_Responder.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$full_content" "$url" "$KNAME" 2>&1 >> "$HOME/.zen/tmp/IA.log" &
        fi

        echo "$event_id" > "$COUNT_DIR/lastevent"

        # MEMORIZE EVENT in UMAP / PUBKEY MEMORY if #mem not present
        if [[ ! "$content" =~ "#mem" ]]; then
            echo "SHORT_MEMORY: $event_json" "$latitude" "$longitude" >> "$HOME/.zen/tmp/uplanet_messages.log"
            $HOME/.zen/Astroport.ONE/IA/short_memory.py "$event_json" "$latitude" "$longitude"
        fi

        ######################### UPlanet Message IA Treatment
        exit 0
    else
        ## MEMORIZE ANY RESPONSE (except #mem tagged messages)
        if [[ ! "$content" =~ "#mem" ]]; then
            echo "SHORT_MEMORY: $event_json" "$latitude" "$longitude" >> "$HOME/.zen/tmp/uplanet_messages.log"
            $HOME/.zen/Astroport.ONE/IA/short_memory.py "$event_json" "$latitude" "$longitude"
        fi
        exit 0
    fi
else
    # Visitor NOSTR message reply
    handle_visitor_message "$pubkey" "$event_id"
    exit 0
fi

exit 0
