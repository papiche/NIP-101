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

# Déterminer le type de réaction
case "$content" in
    "+"|"👍"|"❤️"|"♥️")
        reaction_type="LIKE"
        ;;
    "-"|"👎"|"💔")
        reaction_type="DISLIKE"
        ;;
    "")
        reaction_type="LIKE"  # Contenu vide considéré comme like par défaut
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