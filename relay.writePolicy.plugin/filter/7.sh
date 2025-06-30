#!/bin/bash
# filter/7.sh
# This script handles Nostr events of kind:7 (reactions/likes)
#
# NIP-25 Overview:
# - kind:7 is used for reactions to other events
# - Content can be "+" for like, "-" for dislike, or custom emoji
# - Must include 'e' tag referencing the event being reacted to
# - Can include 'p' tag referencing the author of the event being reacted to
# - Can include 'k' tag specifying the kind of event being reacted to
#
# Example Event Structure:
# {
#   "kind": 7,
#   "content": "+",
#   "tags": [
#     ["e", "event-id-being-reacted-to"],
#     ["p", "pubkey-of-event-author"],
#     ["k", "1"]
#   ],
#   "pubkey": "...",
#   "id": "..."
# }

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Définition du fichier de log spécifique aux likes
LOG_FILE="$HOME/.zen/tmp/nostr_likes.log"

# Assurez-vous que le répertoire pour le fichier de log existe
mkdir -p "$(dirname "$LOG_FILE")"

# Fonction de logging pour les likes
log_like() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Extraire les informations nécessaires de l'événement JSON passé en argument
event_json="$1"

event_id=$(echo "$event_json" | jq -r '.event.id')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
content=$(echo "$event_json" | jq -r '.event.content')
created_at=$(echo "$event_json" | jq -r '.event.created_at')

# Extraire les tags importants
reacted_event_id=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "e") | .[1]' | head -n1)
reacted_author_pubkey=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "p") | .[1]' | head -n1)
reacted_event_kind=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "k") | .[1]' | head -n1)

# Vérifier si l'émetteur est autorisé (reconnu ou dans amisOfAmis.txt)
AMISOFAMIS_FILE="${HOME}/.zen/strfry/amisOfAmis.txt"
AUTHORIZED=false

# Vérifier si la clé publique est dans le répertoire des joueurs autorisés
KEY_DIR="$HOME/.zen/game/nostr"
while IFS= read -r -d $'\0' key_file; do
    if [[ "$pubkey" == "$(cat "$key_file")" ]]; then
        AUTHORIZED=true
        break
    fi
done < <(find "$KEY_DIR" -type f -name "HEX" -print0)

# Si pas trouvé dans les joueurs autorisés, vérifier dans amisOfAmis.txt
if [[ "$AUTHORIZED" == "false" && -f "$AMISOFAMIS_FILE" && "$pubkey" != "" ]]; then
    if grep -q "^$pubkey$" "$AMISOFAMIS_FILE"; then
        AUTHORIZED=true
    fi
fi

# Rejeter l'événement si l'émetteur n'est pas autorisé
if [[ "$AUTHORIZED" == "false" ]]; then
    log_like "REJECTED: Unauthorized pubkey ${pubkey:0:8}... sending reaction - not in authorized players or amisOfAmis.txt"
    exit 1
fi

# Déterminer le type de réaction
case "$content" in
    ""|"+"|"👍"|"❤️"|"♥️")
        reaction_type="LIKE"

        # Search if reacted_author_pubkey is part of UPlanet
        G1PUBNOSTR=$(
            ~/.zen/Astroport.ONE/tools/search_for_this_hex_in_uplanet.sh $reacted_author_pubkey 2>/dev/null
        )
        if [[ $? -eq 0 && -n "$G1PUBNOSTR" ]]; then
            log_like "REACTION: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}... is part of UPlanet (G1PUBNOSTR: ${G1PUBNOSTR:0:8}...)"

            # Find the player directory for the like sender
            PLAYER_DIR=""
            while IFS= read -r -d $'\0' key_file; do
                if [[ "$pubkey" == "$(cat "$key_file")" ]]; then
                    PLAYER_DIR=$(dirname "$key_file")
                    break
                fi
            done < <(find "$HOME/.zen/game/nostr" -type f -name "HEX" -print0)

            # Check if we found the player and if they have a secret.dunikey
            if [[ -n "$PLAYER_DIR" && -s "${PLAYER_DIR}/.secret.dunikey" ]]; then
                # Send 0.1 G1 to the G1PUBNOSTR using PAYforSURE.sh
                AMOUNT="0.1"
                COMMENT="Nostr Like Reward for event ${reacted_event_id:0:8}..."
                
                log_like "PAYMENT: Attempting to send $AMOUNT G1 to $G1PUBNOSTR using ${PLAYER_DIR}/.secret.dunikey"
                
                ~/.zen/Astroport.ONE/tools/PAYforSURE.sh "${PLAYER_DIR}/.secret.dunikey" "$AMOUNT" "$G1PUBNOSTR" "$COMMENT"
                PAYMENT_RESULT=$?
                
                if [[ $PAYMENT_RESULT -eq 0 ]]; then
                    log_like "PAYMENT: Successfully sent $AMOUNT G1 to $G1PUBNOSTR for LIKE reaction"
                else
                    log_like "PAYMENT: Failed to send $AMOUNT G1 to $G1PUBNOSTR (exit code: $PAYMENT_RESULT)"
                fi
            else
                log_like "PAYMENT: Cannot send payment - player directory not found or missing .secret.dunikey for ${pubkey:0:8}..."
            fi
        else
            log_like "REACTION: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}... is not part of UPlanet"
        fi
        ;;
    "-"|"👎"|"💔")
        reaction_type="DISLIKE"
        ;;
    *)
        reaction_type="CUSTOM:$content"
        ;;
esac

# Logger l'information de la réaction
log_like "REACTION: $reaction_type | From: ${pubkey:0:8}... | To Event: ${reacted_event_id:0:8}... | To Author: ${reacted_author_pubkey:0:8}... | Event Kind: $reacted_event_kind | Reaction ID: $event_id"

# Vérifier que les tags obligatoires sont présents
if [[ -z "$reacted_event_id" ]]; then
    log_like "ERROR: Missing 'e' tag in reaction event $event_id - REJECTING"
    exit 1  # Rejeter l'événement s'il n'y a pas de tag 'e'
fi

# Logger les détails complets pour debug si nécessaire
log_like "DETAILS: Event ID: $event_id | Pubkey: $pubkey | Content: '$content' | Created: $created_at"

echo ">>> (7) REACTION: $reaction_type from ${pubkey:0:8}... to event ${reacted_event_id:0:8}..."

exit 0 