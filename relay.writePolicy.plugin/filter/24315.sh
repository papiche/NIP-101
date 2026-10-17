#!/bin/bash
# filter/24315.sh — Présence (kind 24315, ÉPHÉMÈRE) : « je suis en ligne » pour mes amis mutuels.
#
# Éphémère (20000-29999) : strfry le relaie aux abonnés connectés et ne le stocke JAMAIS
# (ephemeralEventsLifetimeSeconds = 600 : mémoire tampon courte, pas de base). Format :
#   tags  ["p", <hex64>] × 1..50   destinataires (amis mutuels qui ont accepté de me voir)
#         ["status", online|visio|away|offline]
#   content  vide
# Chaque événement traverse ce script (bash + jq) : une seule passe jq, pas de scan strfry,
# pas de journal par événement (un battement toutes les 4 min par membre suffirait à noyer le journal).
# Refus : pubkey inconnue (ni MULTIPASS local, ni essaim, ni amisOfAmis), tags hors format,
# contenu non vide, horloge à plus de 120 s. Conforme à NIP-101/KIND_REGISTRY.md §7.

MY_PATH="$(dirname "$0")"
MY_PATH="$(cd "$MY_PATH" && pwd)"
source "$MY_PATH/common.sh"

event_json="$1"
now=$(date +%s)

verdict=$(echo "$event_json" | jq -r --argjson now "$now" '
  .event as $e
  | ($e.tags // []) as $t
  | ([$t[] | select(.[0] == "p")]) as $ps
  | ([$t[] | select(.[0] == "status") | .[1]]) as $st
  | if $e.kind != 24315 then "kind"
    elif ($e.content // "") != "" then "content"
    elif (($e.created_at - $now) | fabs) > 120 then "clock"
    elif ($ps | length) < 1 or ($ps | length) > 50 then "p-count"
    elif ([$ps[] | select((.[1] // "") | test("^[0-9a-f]{64}$") | not)] | length) > 0 then "p-format"
    elif ($st | length) != 1 or ((["online","visio","away","offline"] | index($st[0])) == null) then "status"
    else "ok" end' 2>/dev/null)

if [[ "$verdict" != "ok" ]]; then
    echo "[24315] refusé : ${verdict:-json}" >&2
    exit 1
fi

pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
if visio_sender_known "$pubkey"; then
    exit 0
fi
echo "[24315] refusé : pubkey inconnue ${pubkey:0:8}…" >&2
exit 1
