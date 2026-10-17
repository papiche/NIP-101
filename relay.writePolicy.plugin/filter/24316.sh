#!/bin/bash
# filter/24316.sh — Sonnerie de visio (kind 24316, ÉPHÉMÈRE) : invitation chiffrée pour UN ami EN LIGNE.
#
# Ne passe que si le destinataire est connecté (strfry ne stocke pas les éphémères) : c'est le
# complément temps réel du message privé durable (kind 14) qui porte la même invitation pour
# un ami hors ligne. Le client destinataire ne déchiffre que les sonneries de ses amis mutuels
# (le filtre par auteur évite toute invite de déchiffrement d'un inconnu).
#   tags     ["p", <hex64>] exactement un destinataire
#   content  invitation chiffrée NIP-44 (base64, ≤ 4096 caractères) — jamais lisible par le relay
# Contrôles : kind, un seul p hex64, contenu base64 borné, horloge ±120 s, expéditeur connu
# (visio_sender_known, common.sh). Conforme à NIP-101/KIND_REGISTRY.md §7.

MY_PATH="$(dirname "$0")"
MY_PATH="$(cd "$MY_PATH" && pwd)"
source "$MY_PATH/common.sh"

event_json="$1"
now=$(date +%s)

verdict=$(echo "$event_json" | jq -r --argjson now "$now" '
  .event as $e
  | ($e.tags // []) as $t
  | ([$t[] | select(.[0] == "p")]) as $ps
  | if $e.kind != 24316 then "kind"
    elif (($e.created_at - $now) | fabs) > 120 then "clock"
    elif ($ps | length) != 1 or (($ps[0][1] // "") | test("^[0-9a-f]{64}$") | not) then "p"
    elif (($e.content // "") | test("^[A-Za-z0-9+/=]{16,4096}$") | not) then "content"
    else "ok" end' 2>/dev/null)

if [[ "$verdict" != "ok" ]]; then
    echo "[24316] refusé : ${verdict:-json}" >&2
    exit 1
fi

pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
if visio_sender_known "$pubkey"; then
    exit 0
fi
echo "[24316] refusé : pubkey inconnue ${pubkey:0:8}…" >&2
exit 1
