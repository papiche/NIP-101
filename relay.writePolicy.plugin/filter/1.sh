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
MESSAGE_LIMIT=3

# Variables pour la gestion de la file d'attente
QUEUE_DIR="$HOME/.zen/tmp/uplanet_queue"
mkdir -p "$QUEUE_DIR"
MAX_QUEUE_SIZE=5
PROCESS_TIMEOUT=300  # 5 minutes timeout for processing
QUEUE_CLEANUP_AGE=3600  # 1 hour for queue file cleanup

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

# Fonction pour vérifier et gérer le message "Hello NOSTR visitor"
handle_visitor_message() {
    local pubkey="$1"
    local event_id="$2"

    # Créer le répertoire de comptage si inexistant
    mkdir -p "$COUNT_DIR"

    # Vérifier si la clé publique est déjà blacklistée (should be done before calling 1.sh)
    if grep -q "^$pubkey$" "$BLACKLIST_FILE"; then
        echo "Pubkey $pubkey is blacklisted, skipping visitor message."
        return 0 # Ne rien faire, la clé est blacklistée
    fi

    local count_file="$COUNT_DIR/$pubkey"

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

            RESPN="Hello NOSTR visitor.

I noticed that you're using our Relay without being registered on our #Ğ1 Web of Trust.

You have $remaining_messages message(s) left before being automatically blocked. Please join our self-sovereign community to avoid interruption.
Take a Place on #UPlanet : $myIPFS/ipns/copylaradio.com

Your devoted Astroport Captain.

#CopyLaRadio #mem
* UPlanet : ${UPLANETG1PUB:0:8}
* ♥️BOX : /ipns/$IPFSNODEID
"

            nostpy-cli send_event \
              -privkey "$NPRIV_HEX" \
              -kind 1 \
              -content "$RESPN" \
              -tags "[['e', '$event_id'], ['p', '$pubkey'], ['t', 'Warning']]" \
              --relay "$myRELAY" >> "$HOME/.zen/tmp/nostpy.log" 2>&1
        fi
        ) &
    else
        echo "Visitor limit reached for pubkey $pubkey. Removing Messages & Blacklisting."
        cd ~/.zen/strfry
        ./strfry delete --filter "{\"authors\":[\"$pubkey\"]}"
        cd -
        echo "$pubkey" >> "$BLACKLIST_FILE"
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
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Killed stuck process $pid" >> "$HOME/.zen/tmp/uplanet_messages.log"
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
            timeout $PROCESS_TIMEOUT $HOME/.zen/Astroport.ONE/IA/UPlanet_IA_Responder.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$full_content" "$url" "$KNAME" &
        fi

        echo "$event_id" > "$COUNT_DIR/lastevent"
        
        # MEMORIZE EVENT in UMAP / PUBKEY MEMORY if #mem not present
        if [[ ! "$content" =~ "#mem" ]]; then
            $HOME/.zen/Astroport.ONE/IA/short_memory.py "$event_json" "$latitude" "$longitude"
        fi

        ######################### UPlanet Message IA Treatment
        exit 0
    else
        ## MEMORIZE ANY RESPONSE (except #mem tagged messages)
        if [[ ! "$content" =~ "#mem" ]]; then
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
