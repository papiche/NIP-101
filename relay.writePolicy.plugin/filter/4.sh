#!/bin/bash
# filter/4.sh — Filtre kind 4 (DMs chiffrés NIP-04/NIP-44)
#
# Accepte tous les DMs kind 4.
# Si le DM est adressé au NODE HEX de cette station, il est enqueué dans
# ~/.zen/tmp/bro_dm_queue/ pour traitement immédiat par bro_dm_daemon.sh
# (via inotifywait) sans attendre le cycle NOSTRCARD.refresh.sh.
## Le NODE_HEX est lu depuis ~/.zen/game/secret.nostr

MY_PATH="$(dirname "$0")"
MY_PATH="$(cd "$MY_PATH" && pwd)"

source "$MY_PATH/common.sh"

event_json="$1"

## Extraire event_id et pubkey via la fonction commune
extract_event_data "$event_json"

## Accepter immédiatement — les DM kind 4 sont toujours relayés
_accept() { echo "{\"id\":\"$event_id\",\"action\":\"accept\"}"; exit 0; }

## Vérifier si ce DM est destiné au NODE local
SECRET_FILE="$HOME/.zen/game/secret.nostr"
[[ ! -s "$SECRET_FILE" ]] && _accept

NODE_HEX=$(grep -oP 'HEX=\K[^;]+' "$SECRET_FILE" 2>/dev/null | tr -d '[:space:]')
[[ -z "$NODE_HEX" || ${#NODE_HEX} -ne 64 ]] && _accept

## Vérifier le tag #p du DM
is_for_node=$(echo "$event_json" | jq -r --arg h "$NODE_HEX" \
    '.event.tags // [] | map(select(.[0]=="p" and .[1]==$h)) | length > 0' 2>/dev/null)

if [[ "$is_for_node" == "true" ]]; then
    QUEUE_DIR="$HOME/.zen/tmp/bro_dm_queue"
    mkdir -p "$QUEUE_DIR"
    ## Écrire l'event (format strfry : {event:{...}, receivedAt:...}) dans la queue
    ## atomic via fichier temporaire + mv
    _tmp=$(mktemp -p "$QUEUE_DIR" "${event_id}_XXXXXX.json.tmp")
    echo "$event_json" > "$_tmp"
    mv "$_tmp" "$QUEUE_DIR/${event_id}.json"
fi

_accept
