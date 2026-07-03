#!/bin/bash
# filter/4.sh — Filtre kind 4 (DMs chiffrés NIP-04/NIP-44)
#
# Accepte tous les DMs kind 4.
# Si le DM est adressé au NODE HEX de cette station, il est enqueué dans
# ~/.zen/tmp/bro_dm_queue/ pour traitement immédiat par bro_dm_daemon.sh
# (via inotifywait) sans attendre le cycle NOSTRCARD.refresh.sh.
## Le NODE_HEX est lu depuis ~/.zen/game/secret.nostr
#
# Cas "self-DM" (author == #p == propre clé MULTIPASS, canal BRO personnel —
# voir bro_watch_core.py) : enqueué séparément dans ~/.zen/tmp/bro_self_dm_queue/
# avec un marqueur {"self_dm":true,...} — bro_dm_daemon.sh ne peut PAS déchiffrer
# ces events (seule la clé propre du propriétaire le peut, pas NODE_HEX) ; il se
# contente de résoudre l'email depuis le sender hex et de déclencher
# `bro_watch_core.py check-commands EMAIL`, qui fait son propre fetch+déchiffrement.

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

## Ne jamais enqueuer un DM envoyé PAR le NODE lui-même.
## _send_dm envoie les réponses sur tous les relays connus (constellation + local).
## Sans cette garde, chaque réponse passant par le relay local serait re-enqueuée
## et traitée comme une nouvelle commande → boucle de rétroaction infinie.
sender_hex=$(echo "$event_json" | jq -r '.event.pubkey // ""' 2>/dev/null)
[[ "$sender_hex" == "$NODE_HEX" ]] && _accept

## Vérifier le tag #p : le DM doit être adressé à ce NODE
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

## Cas "self-DM" (author == #p == propre clé MULTIPASS, canal BRO personnel) :
## enqueue séparé, sans déchiffrement ici (NODE_NSEC ne peut PAS déchiffrer un
## self-DM — seule la propre clé du propriétaire le peut). bro_dm_daemon.sh
## résout l'email depuis sender_hex et route localement ou relaie vers la
## home station si le joueur est en roaming sur cette station.
is_self_dm=$(echo "$event_json" | jq -r --arg s "$sender_hex" \
    '.event.tags // [] | map(select(.[0]=="p" and .[1]==$s)) | length > 0' 2>/dev/null)

if [[ "$is_self_dm" == "true" && ${#sender_hex} -eq 64 ]]; then
    SELF_QUEUE_DIR="$HOME/.zen/tmp/bro_self_dm_queue"
    mkdir -p "$SELF_QUEUE_DIR"
    _self_tmp=$(mktemp -p "$SELF_QUEUE_DIR" "${event_id}_XXXXXX.json.tmp")
    echo "{\"self_dm\":true,\"event\":$(echo "$event_json" | jq -c '.event')}" > "$_self_tmp"
    mv "$_self_tmp" "$SELF_QUEUE_DIR/${event_id}.json"
fi

_accept
