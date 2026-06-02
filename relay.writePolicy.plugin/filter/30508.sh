#!/bin/bash
# filter/30508.sh
# Match vibratoire ATOM4LOVE (Kind 30508)
# Produit par cabine-33 après scan BLE/WiFi (k ≥ 0.85 entre deux porteurs).
# Seuls les membres MULTIPASS (local, swarm ou amisOfAmis) peuvent publier.

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

source "$MY_PATH/common.sh"

LOG_FILE="$HOME/.zen/tmp/nostr_kind30508.log"
ensure_log_dir "$LOG_FILE"
log_match() { log_with_timestamp "$LOG_FILE" "$1"; }

event_json="$1"
extract_event_data "$event_json"
extract_tags "$event_json" "d"
partner_pubkey="$d"

# Extraire k du content JSON (produit par cabine-33)
k_value=$(echo "$content" | jq -r '.k // empty' 2>/dev/null)

log_match "=== Kind 30508 — Match vibratoire A4L ==="
log_match "Pubkey    : $pubkey"
log_match "Event ID  : $event_id"
log_match "Partner   : $partner_pubkey"
log_match "k         : $k_value"

# Seuls les membres MULTIPASS (local, swarm ou amisOfAmis) peuvent publier
if ! check_authorization "$pubkey" "log_match"; then
    log_match "REJECTED: pubkey non autorisée pour Kind 30508"
    exit 1
fi

# Valider la valeur k ∈ [0.85, 1.0] — seuil super-cohérence cabine-33
if [[ -z "$k_value" ]]; then
    log_match "REJECTED: champ k absent du content JSON"
    exit 1
fi

k_check=$(echo "$k_value >= 0.85 && $k_value <= 1.0" | bc -l 2>/dev/null)
if [[ "$k_check" != "1" ]]; then
    log_match "REJECTED: k=$k_value hors seuil [0.85, 1.0]"
    exit 1
fi

# Vérifier que le partner pubkey est un hex valide (64 chars)
if [[ -z "$partner_pubkey" ]] || ! [[ "$partner_pubkey" =~ ^[0-9a-f]{64}$ ]]; then
    log_match "REJECTED: tag d (partner pubkey) invalide : '$partner_pubkey'"
    exit 1
fi

log_match "ACCEPTED: k=$k_value entre ${pubkey:0:8}… et ${partner_pubkey:0:8}…"
log_match "========================================="

exit 0
