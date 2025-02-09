#!/bin/bash

# Définition du répertoire de stockage des clés publiques
KEY_DIR="$HOME/.zen/game/nostr"

# Fonction pour vérifier si une clé est autorisée
is_key_authorized() {
  local pubkey="$1"
  local authorized=0

  find "$KEY_DIR" -type f -name "HEX" -print0 | while IFS= read -r -d $'\0' key_file; do
      if grep -q "$pubkey" "$key_file"; then
          NPUBHEX="$pubkey"
          authorized=1
          break
      fi
  done

  if [[ $authorized -eq 0 ]]; then
      return 1 # Clé non autorisée
  else
      return 0 # Clé autorisée
  fi
}

# Fonction de traitement pour les messages de type 0 (métadonnées)
process_kind_0() {
    local event_json="$1"

    # Extraire les informations de l'événement
    local pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
    local content=$(echo "$event_json" | jq -r '.event.content')

    # Vérifier si la clé est autorisée
    if ! is_key_authorized "$pubkey"; then
        echo "Unauthorized pubkey for kind 0: $pubkey" >&2
        # Action en cas de clé non autorisée (ici, on rejette)
        # Possibilité de faire des logs plus spécifiques
        return
    fi

    # Traitement spécifique pour les messages de type 0 (métadonnées) si nécessaire
    # Ici, un simple message de log
    echo "Processing kind 0 event. pubkey : $pubkey" >&2

    # Accepter l'événement par défaut après traitement
    echo "{\"id\": $(echo "$event_json" | jq -r '.event.id'), \"action\": \"accept\"}"
}

# Fonction de traitement pour les messages de type 1 (note)
process_kind_1() {
  local event_json="$1"

  # Extraire les informations de l'événement
  local pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
    local content=$(echo "$event_json" | jq -r '.event.content')

  # Vérifier si la clé est autorisée
  if ! is_key_authorized "$pubkey"; then
      echo "Unauthorized pubkey for kind 1: $pubkey" >&2
      # Action en cas de clé non autorisée
      return
  fi

  # Traitement spécifique pour les messages de type 1 (note)
  echo "Processing kind 1 event, pubkey : $pubkey, content : $content" >&2

  # Accepter l'événement
    echo "{\"id\": $(echo "$event_json" | jq -r '.event.id'), \"action\": \"accept\"}"
}

# Fonction de traitement pour les messages de type 3 (contact list)
process_kind_3() {
  local event_json="$1"

  # Extraire les informations de l'événement
    local pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
  # Vérifier si la clé est autorisée
  if ! is_key_authorized "$pubkey"; then
      echo "Unauthorized pubkey for kind 3: $pubkey" >&2
      # Action en cas de clé non autorisée
      return
  fi

    # Traitement spécifique pour les messages de type 3 (liste de contacts)
   echo "Processing kind 3 event, pubkey : $pubkey" >&2
  # Accepter l'événement
   echo "{\"id\": $(echo "$event_json" | jq -r '.event.id'), \"action\": \"accept\"}"
}

# Fonction de traitement pour les messages de type 7 (réaction)
process_kind_7() {
  local event_json="$1"

  # Extraire les informations de l'événement
    local pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
  # Vérifier si la clé est autorisée
  if ! is_key_authorized "$pubkey"; then
       echo "Unauthorized pubkey for kind 7: $pubkey" >&2
      # Action en cas de clé non autorisée
      return
  fi

    # Traitement spécifique pour les messages de type 7 (réaction)
  echo "Processing kind 7 event, pubkey : $pubkey" >&2
    # Accepter l'événement
    echo "{\"id\": $(echo "$event_json" | jq -r '.event.id'), \"action\": \"accept\"}"
}

# Boucle principale qui lit les événements depuis stdin
while IFS= read -r line; do

  # Vérifier que la ligne n'est pas vide
  if [[ -z "$line" ]]; then
      continue
  fi

  if echo "$line" | jq -e '.event.kind' > /dev/null 2>&1; then # Vérifie si la ligne est un json contenant "event.kind"

    local event_json="$line"
    local kind=$(echo "$event_json" | jq -r '.event.kind')

    case "$kind" in
        0)  process_kind_0 "$event_json" ;;
        1)  process_kind_1 "$event_json" ;;
        3)  process_kind_3 "$event_json" ;;
        7)  process_kind_7 "$event_json" ;;
        *) # Autres kinds, acceptés par défaut
        echo "Processing kind ${kind} event" >&2
        echo "{\"id\": $(echo "$event_json" | jq -r '.event.id'), \"action\": \"accept\"}"
        ;;
    esac
  else
      # Si la ligne n'est pas un événement Nostr, la rejeter
      echo "Non-JSON input received: $line" >&2
      echo "{\"action\": \"reject\"}"
  fi
done
