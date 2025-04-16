#!/bin/bash
# filter/1.sh
MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Extraire les informations nécessaires de l'événement JSON passé en argument
event_json="$1"
#~ echo "$event_json" >> "$HOME/.zen/strfry/1_messages.log" ## DEBUG

application=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "application") | .[1]')
url=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "url") | .[1]')
latitude=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "latitude") | .[1]')
longitude=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "longitude") | .[1]')
content=$(echo "$event_json" | jq -r '.event.content')
event_id=$(echo "$event_json" | jq -r '.event.id')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
created_at=$(echo "$event_json" | jq -r '.event.created_at')
kind=$(echo "$event_json" | jq -r '.event.kind')
tags=$(echo "$event_json" | jq -r '.event.tags')

# Variables pour la gestion du message "Hello NOSTR visitor"
BLACKLIST_FILE="$HOME/.zen/strfry/blacklist.txt"
COUNT_DIR="$HOME/.zen/strfry/pubkey_counts"
MESSAGE_LIMIT=3

# Fonction pour vérifier si une clé est autorisée
KEY_DIR="$HOME/.zen/game/nostr"
get_key_directory() {
    local pubkey="$1"
    local key_file
    local found_dir=""

    while IFS= read -r -d $'\0' key_file; do
        if [[ "$pubkey" == "$(cat "$key_file")" ]]; then
            # Extraire le dernier répertoire du chemin
            KNAME=$(basename "$(dirname "$key_file")")
            return 0 # Clé autorisée
        fi
    done < <(find "$KEY_DIR" -type f -name "HEX" -print0)

    return 1 # Clé non autorisée
}

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
            echo "Notice: Astroport Relay Anonymous Usage"

            RESPN="Hello NOSTR visitor.

I noticed that you're using our Astroport Relay without being registered on our Ğ1 Web of Trust.

You have $remaining_messages message(s) left before being automatically blocked. Please join our self-sovereign community to avoid interruption.
Enter Email to Register: $uSPOT/scan

#CopyLaRadio Relay : “♥️BOX” ($IPFSNODEID)
#UPlanet : ${UPLANETG1PUB:0:8}"

            nostpy-cli send_event \
              -privkey "$NPRIV_HEX" \
              -kind 1 \
              -content "$RESPN" \
              -tags "[['e', '$event_id'], ['p', '$pubkey'], ['t', 'Warning']]" \
              --relay "$myRELAY"
        fi
        ) &
    else
        echo "Visitor limit reached for pubkey $pubkey. Removing Messages & Blacklisting."
        ~/.zen/strfry/strfry delete --filter "{\"authors\":[\"$pubkey\"]}"
        echo "$pubkey" >> "$BLACKLIST_FILE"
    fi
    return 0
}


if [[ "$application" == UPlanet* ]]; then
# UPlanet NOSTR messages.
    if [[ -n "$latitude" && -n "$longitude" ]]; then
        # Activation du script AI
        [[ "$(cat $COUNT_DIR/lastevent)" == "$event_id" ]] && exit 0 ## AVOID DOUBLE PUBLISHING
        ######################### UPlanet Message IA Treatment
        $MY_PATH/IA_UPlanet.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$content" "$url" &
        echo "$event_id" > "$COUNT_DIR/lastevent"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - UPlanet Message - Lat: $latitude, Lon: $longitude, Content: $content" >> "$HOME/.zen/strfry/uplanet_messages.log"
        exit 0 # Indiquer que le filtre UPlanet a réussi (clé générée)
    else
        echo "Latitude ou longitude manquante pour UPlanet" >&2
        exit 1 # Latitude ou longitude manquante
    fi
else
# Simple NOSTR messages.
    if get_key_directory "$pubkey"; then
        echo "OK Authorized key : $KNAME"
        exit 0
    fi

    handle_visitor_message "$pubkey" "$event_id"
    exit 0
fi
