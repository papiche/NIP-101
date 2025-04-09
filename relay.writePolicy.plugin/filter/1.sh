#!/bin/bash
# filter/1.sh

# Extraire les informations nécessaires de l'événement JSON passé en argument
event_json="$1"
echo "$event_json" >> "$HOME/.zen/strfry/1_messages.log"

application=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "application") | .[1]')
latitude=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "latitude") | .[1]')
longitude=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "longitude") | .[1]')
content=$(echo "$event_json" | jq -r '.event.content')
event_id=$(echo "$event_json" | jq -r '.event.id')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
created_at=$(echo "$event_json" | jq -r '.event.created_at')
kind=$(echo "$event_json" | jq -r '.event.kind')
tags=$(echo "$event_json" | jq -r '.event.tags')

# Vérifier si l'application est "UPlanet"
if [[ "$application" == "UPlanet" ]]; then
    if [[ -n "$latitude" && -n "$longitude" ]]; then
        # Activation du script AI
        echo "$(date '+%Y-%m-%d %H:%M:%S') - UPlanet Message Accepted - Event ID: $event_id, Pubkey: $pubkey, Lat: $latitude, Lon: $longitude, Content: $content" >> "$HOME/.zen/strfry/uplanet_messages.log"
        exit 0 # Indiquer que le filtre UPlanet a réussi (clé générée)
    else
        echo "Latitude ou longitude manquante pour UPlanet" >&2
        exit 1 # Latitude ou longitude manquante
    fi
else
    exit 0
fi
