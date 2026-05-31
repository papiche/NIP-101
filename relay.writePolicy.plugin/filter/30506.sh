#!/bin/bash
# filter/30506.sh
# Dossier de médiation WoTx² (Kind 30506, NIP-33)
# Seul le capitaine local (oracle) ou un membre MULTIPASS peuvent publier.

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

source "$MY_PATH/common.sh"

LOG_FILE="$HOME/.zen/tmp/nostr_kind30506.log"
ensure_log_dir "$LOG_FILE"
log_justice() { log_with_timestamp "$LOG_FILE" "$1"; }

event_json="$1"
extract_event_data "$event_json"
extract_tags "$event_json" "d" "t" "status"
case_id="$d"
tag_t="$t"
case_status="$status"

log_justice "=== Kind 30506 — Dossier médiation ==="
log_justice "Pubkey    : $pubkey"
log_justice "Event ID  : $event_id"
log_justice "Case ID   : $case_id"
log_justice "Type      : $tag_t"
log_justice "Status    : $case_status"

# Seuls les membres MULTIPASS (local, swarm ou amisOfAmis) peuvent créer des dossiers
if ! check_authorization "$pubkey" "log_justice"; then
    log_justice "REJECTED: pubkey non autorisée pour Kind 30506"
    exit 1
fi

# Vérifier que c'est bien un dossier friction (tag t=friction obligatoire)
if [[ "$tag_t" != "friction" ]]; then
    log_justice "REJECTED: Kind 30506 avec t='$tag_t' — seul 'friction' est accepté"
    exit 1
fi

# Valider que le case_id commence par "friction-"
if [[ "$case_id" != friction-* ]]; then
    log_justice "REJECTED: case_id invalide (doit commencer par 'friction-'): $case_id"
    exit 1
fi

log_justice "ACCEPTED: Dossier $case_id (${case_status}) par ${pubkey:0:8}..."
log_justice "======================================="

exit 0
