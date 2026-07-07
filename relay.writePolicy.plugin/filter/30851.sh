#!/bin/bash
# filter/30851.sh
# Log ZEN Emission Proof (kind 30851) — cf. KIND_REGISTRY.md §Kind 30851
#
# Preuve cryptographique d'une émission ẐEN déclenchée par une contribution
# OpenCollective (source de vérité distribuée pour l'idempotence, cf.
# OC2UPlanet/oc2uplanet.sh). Jusqu'ici sans filtre dédié : angle mort sur le
# flux d'émission monétaire, pourtant central pour NODE (traçabilité
# économique) et pour BRO (comprendre pourquoi un solde a bougé, au-delà du
# simple seuil bas déjà surveillé par low_g1_balance).

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Source common functions
source "$MY_PATH/common.sh"

event_json="$1"
extract_event_data "$event_json"

# Tags sans ":" — extract_tags() convient ici.
extract_tags "$event_json" "d" "s" "email" "amount" "tier" "constellation"

LOG_FILE="$HOME/.zen/tmp/nostr_kind30851.log"
ensure_log_dir "$LOG_FILE"

log_with_timestamp "$LOG_FILE" "=== ZEN Emission Proof (kind 30851) ==="
log_with_timestamp "$LOG_FILE" "Key: ${d:-?} | Status: ${s:-?} | Email: ${email:-?} | Amount: ${amount:-?} | Tier: ${tier:-?}"
log_with_timestamp "$LOG_FILE" "================================"

_emission_ok=0
[[ "${s:-}" == "OK" ]] && _emission_ok=1

nip101_log_event "30851" "emission_${s:-unknown}" "$_emission_ok" \
    "{\"email\":\"${email:-}\",\"amount\":\"${amount:-}\",\"tier\":\"${tier:-}\"}"

# Toujours accepté — preuve informative, aucune politique de rejet documentée
# (l'idempotence est vérifiée en amont par OC2UPlanet via scan strfry, pas ici).
exit 0
