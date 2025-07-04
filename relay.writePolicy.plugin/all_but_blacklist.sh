#!/bin/bash
#~ Ce script gère les messages reçus par le relai Nostr en autorisant tout le monde sauf les adresses blacklistées.
#~ Format du fichier blacklist.txt :
#~ Chaque ligne du fichier doit contenir une clé publique blacklistée.
#~ Exemple :
#~ blacklisted_pubkey1
#~ blacklisted_pubkey2
#~
#~ Elle est alimentée par le script ~/.zen/Astroport.ONE/IA/UPlanet_IA_Responder.sh
#~ /filter/$kind.sh sont les scripts qui filtrent les événements.
#~ /filter/1.sh est le script qui filtre les événements de type 1
#~ etc...

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Définition du fichier de log
LOG_FILE="$HOME/.zen/tmp/strfry.log"

# Assurez-vous que le répertoire pour le fichier de log existe
mkdir -p "$(dirname "$LOG_FILE")"

# Fonction de logging qui écrit seulement dans le fichier de log, pas dans stdout
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Définition du répertoire de stockage des clés publiques
KEY_DIR="$HOME/.zen/game/nostr"

# Fichier contenant la blacklist
BLACKLIST_FILE="$HOME/.zen/strfry/blacklist.txt"

# Fonction pour vérifier si une clé est blacklistée
is_key_blacklisted() {
    local pubkey="$1"
    local BLACKLIST=($(cat "$BLACKLIST_FILE"))
    for blacklisted_key in "${BLACKLIST[@]}"; do
        if [[ "$pubkey" == "$blacklisted_key" ]]; then
            return 0 # Clé blacklistée
        fi
    done
    return 1 # Clé non blacklistée
}


# Fonction pour traiter un événement de type 'new'
process_new_event() {
    local event_json="$1"
    
    # Extraire les informations nécessaires de l'événement
    local event_id=$(echo "$event_json" | jq -r '.event.id')
    local pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
    local kind=$(echo "$event_json" | jq -r '.event.kind')
    local current_time=$(date +%s)

    log_message "Processing event ID: $event_id, pubkey: $pubkey, kind: $kind"

    # Vérifier si la clé publique est blacklistée
    if is_key_blacklisted "$pubkey"; then
        log_message "Rejecting ALL events (kind $kind) from blacklisted pubkey: $pubkey"
        echo "{\"id\": \"$event_id\", \"action\": \"reject\"}"
        return
    fi

    # Exécuter le filtre correspondant (si le script existe)
    if [[ -x $MY_PATH/filter/$kind.sh ]]; then
        # log_message "Running filter for kind $kind"
        # Rediriger toutes les sorties du filtre ~/.zen/tmp/strfry.log 
        $MY_PATH/filter/$kind.sh "$event_json" >> ~/.zen/tmp/strfry.log
        local filter_result=$?
        #vérifier si le filtre est bien exécuté
        if [[ $filter_result -ne 0 ]]; then
            # Si le filtre renvoie un code d'erreur, rejeter l'événement
            log_message "Filter $kind.sh rejected event: $event_id"
            echo "{\"id\": \"$event_id\", \"action\": \"reject\"}"
            return
        fi
    fi

    # Accepter l'événement
    log_message "Accepting event: $event_id"
    echo "{\"id\": \"$event_id\", \"action\": \"accept\"}"
}

# Boucle principale qui lit les événements depuis stdin
while IFS= read -r line; do
    # Vérifier que la ligne n'est pas vide
    if [[ -z "$line" ]]; then
        continue
    fi

    # Vérifier si la ligne contient un JSON valide
    if echo "$line" | jq -e '.' > /dev/null 2>&1; then
        # Extraire le type d'événement
        event_type=$(echo "$line" | jq -r '.type')
        event_id=$(echo "$line" | jq -r '.event.id')
        event_kind=$(echo "$line" | jq -r '.event.kind')

        if [[ "$event_type" == "new" ]]; then
            # Traiter les nouveaux événements
            process_new_event "$line"
        else
            # Accepter automatiquement les autres types d'événements (sync, etc.)
            echo "{\"id\": \"$event_id\", \"action\": \"accept\"}"
        fi
    else
        echo "{\"action\": \"reject\"}"
    fi

done < /dev/stdin
