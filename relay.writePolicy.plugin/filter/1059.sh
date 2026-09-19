#!/bin/bash
# filter/1059.sh — Filtre kind 1059 (gift wrap NIP-59 / NIP-17)
#
# Un kind 1059 est TOUJOURS accepté : c'est une enveloppe scellée signée par une
# clé éphémère, illisible par le relay. Rien dans son contenu ne permet de juger
# sa légitimité, et elle peut très bien être destinée à un MULTIPASS hébergé par
# une AUTRE station de la constellation (ou à un joueur en roaming) — la refuser
# casserait la livraison sans bénéfice.
#
# Différence FONDAMENTALE avec filter/4.sh : un gift-wrap NIP-17 réel est chiffré
# vers le VRAI pubkey personnel du destinataire (son MULTIPASS,
# ~/.zen/game/nostr/{EMAIL}/HEX), PAS vers le NODE_HEX de la station. Seul le
# nsec personnel de l'utilisateur (~/.zen/game/nostr/{EMAIL}/.secret.nostr) peut
# déchiffrer la couche externe — que la station détient server-side, donc le
# daemon PEUT traiter l'event (contrairement au self-DM kind 4).
#
# Routage : le tag #p est comparé à TOUS les MULTIPASS locaux via get_key_email()
# (common.sh). Si match → enqueue {"email":EMAIL,"event":{...}} dans
# ~/.zen/tmp/bro_giftwrap_queue/{event_id}.json, consommé par
# IA/bro/bro_dm_daemon.sh::_handle_giftwrap_event() (dé-wrap via
# nostr_node_intercom.py unwrap-giftwrap, puis dispatch sur rumor.kind :
# 15 = message fichier NIP-17, 14 = message chat).
# Sinon → passthrough loggé (autre nœud du swarm / roaming).

MY_PATH="$(dirname "$0")"
MY_PATH="$(cd "$MY_PATH" && pwd)"

source "$MY_PATH/common.sh"

event_json="$1"

## Extraire event_id et pubkey via la fonction commune
extract_event_data "$event_json"

LOG_FILE="$HOME/.zen/tmp/nostr_kind1059_giftwrap.log"
ensure_log_dir "$LOG_FILE"
sender_hex=$(echo "$event_json" | jq -r '.event.pubkey // ""' 2>/dev/null)

## Accepter en journalisant la raison — même convention que filter/4.sh :
## un 1059 n'est jamais rejeté, mais savoir POURQUOI il n'a pas été enqueué
## (destinataire inconnu ici, pas de tag #p…) est la seule visibilité possible
## sur ce canal, dont le contenu est par construction opaque au relay.
_accept() {
    local _reason="${1:-passthrough}"
    log_with_timestamp "$LOG_FILE" "ACCEPTED ($_reason): event ${event_id:0:16}... from ${sender_hex:0:12}... (ephemeral)"
    nip101_log_event "1059" "$_reason" 1 "{\"sender\":\"${sender_hex:0:12}\"}"
    echo "{\"id\":\"$event_id\",\"action\":\"accept\"}"
    exit 0
}

## Résoudre le destinataire : premier tag #p correspondant à un MULTIPASS local.
## NIP-17 impose exactement un tag #p sur le gift wrap, mais on boucle par
## robustesse (même schéma que la résolution HEX_LOVE de filter/4.sh).
target_email=""
p_tags=$(echo "$event_json" | jq -r '.event.tags // [] | map(select(.[0]=="p")) | .[].[1]' 2>/dev/null)
if [[ -n "$p_tags" ]]; then
    while IFS= read -r _p; do
        [[ ${#_p} -ne 64 ]] && continue
        _email=$(get_key_email "$_p")
        if [[ -n "$_email" ]]; then
            target_email="$_email"
            break
        fi
    done <<< "$p_tags"
fi

[[ -z "$target_email" ]] && _accept "giftwrap_not_local"

GIFTWRAP_QUEUE_DIR="$HOME/.zen/tmp/bro_giftwrap_queue"
mkdir -p "$GIFTWRAP_QUEUE_DIR"

## Écriture atomique (fichier temporaire + mv), comme filter/4.sh : le daemon
## surveille ce répertoire via inotifywait et ne doit jamais lire un JSON partiel.
_tmp=$(mktemp -p "$GIFTWRAP_QUEUE_DIR" "${event_id}_XXXXXX.json.tmp")
echo "{\"giftwrap\":true,\"email\":\"${target_email}\",\"event\":$(echo "$event_json" | jq -c '.event')}" > "$_tmp"
mv "$_tmp" "$GIFTWRAP_QUEUE_DIR/${event_id}.json"

log_with_timestamp "$LOG_FILE" "QUEUED (giftwrap): event ${event_id:0:16}... to ${target_email}"
nip101_log_event "1059" "queued_giftwrap" 1 "{\"sender\":\"${sender_hex:0:12}\"}"

echo "{\"id\":\"$event_id\",\"action\":\"accept\"}"
exit 0
