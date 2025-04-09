#!/bin/bash
# Ce script ajoute un filtrage au relai nostr strfry.
# Il vérifie que la clé publique de la source du messaage
# est enregistré comme Nostr Card sur la station Astroport.ONE
# Selon le type applique un traitement à la volée...
MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Définition du fichier de log
LOG_FILE="$HOME/.zen/strfry/plugin.log"

# Assurez-vous que le répertoire pour le fichier de log existe
mkdir -p "$(dirname "$LOG_FILE")"

# Rediriger stderr et stdout vers le fichier de log
exec > >(tee -a "$LOG_FILE") 2>&1

# Définition du répertoire de stockage des clés publiques
KEY_DIR="$HOME/.zen/game/nostr"

# Fonction pour vérifier si une clé est autorisée
is_key_authorized() {
    local pubkey="$1"
    local key_file

    while IFS= read -r -d $'\0' key_file; do
        if [[ "$pubkey" == "$(cat "$key_file")" ]]; then
            #~ echo "___FOUND $pubkey in $key_file" >&2
            return 0 # Clé autorisée
        fi
    done < <(find "$KEY_DIR" -type f -name "HEX" -print0)

    return 1 # Clé non autorisée
}

# Fonction pour traiter un événement de type 'new'
process_new_event() {
    local event_json="$1"
    #~ echo "$event_json" >&2

    # Extraire les informations nécessaires de l'événement
    local event_id=$(echo "$event_json" | jq -r '.event.id')
    local pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
    local kind=$(echo "$event_json" | jq -r '.event.kind')
    #~ echo "------- $kind - ($pubkey) ---------------- $event_id" >&2
    #~ echo "$event_json" >&2

    # Vérifier si la clé publique est autorisée
    if ! is_key_authorized "$pubkey"; then
        #~ echo "Unauthorized pubkey for kind $kind: $pubkey" >&2
        echo "{\"id\": \"$event_id\", \"action\": \"shadowReject\"}"
        return
    fi

    # Exécuter le filtre correspondant (si le script existe)
    if [[ -x $MY_PATH/filter/$kind.sh ]]; then
        $MY_PATH/filter/$kind.sh "$event_json"
        if [[ $? -ne 0 ]]; then
            # Si le filtre renvoie un code d'erreur, rejeter l'événement
            #~ echo "Rejecting event of type: $event_type" >&2
            echo "{\"id\": \"$event_id\", \"action\": \"reject\"}"
            return
        fi
    fi

    # Logs pour les événements autorisés
    #~ echo "Processing new event of kind . pubkey: $pubkey" >&2
    #~ echo "$event_json" >&2
    # Accepter l'événement après traitement
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
            #~ echo "Accepting non-new event of type (Relay Syncronization): $event_type" >&2
            echo "{\"id\": \"$event_id\", \"action\": \"accept\"}"
        fi
    else
        #~ echo "Non-JSON input received: $line" >&2
        echo "{\"action\": \"reject\"}"
    fi

done < /dev/stdin
