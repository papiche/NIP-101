#!/bin/bash
# filter/1.sh

# Extraire les informations nécessaires de l'événement JSON passé en argument
event_json="$1"
application=$(echo "$event_json" | jq -r '.event.tags | to_entries[] | select(.key=="application") | .value')
latitude=$(echo "$event_json" | jq -r '.event.tags | to_entries[] | select(.key=="latitude") | .value')
longitude=$(echo "$event_json" | jq -r '.event.tags | to_entries[] | select(.key=="longitude") | .value')
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
