#!/bin/bash
################################################################################
# Author: Fred (support@qo-op.com)
# License: AGPL-3.0
################################################################################
#~ filter/5.sh — Kind 5 : suppression (NIP-09), protection de kinds immuables
#
# Le comportement NIP-09 natif de strfry (suppression autorisée si le pubkey de
# la demande correspond au pubkey de l'événement ciblé) est TROP PERMISSIF pour
# les kinds du ledger Ğ1-Nostr : une transaction est un fait définitif, jamais
# supprimable — même par son propre auteur (le "droit à l'oubli" NIP-09 est
# délibérément désactivé pour ces kinds, l'intégrité du grand livre prime).
#
# Politique tout-ou-rien : si UN SEUL des events ciblés par ce kind-5 appartient
# à un kind protégé, la demande de suppression entière est rejetée (on ne peut
# de toute façon pas "réécrire" un event déjà signé pour ne garder que les
# suppressions légitimes).
#
# IMPORTANT — ce filtre protège uniquement le chemin d'écriture client direct
# (websocket → RelayWriter → plugin). Il ne protège PAS une suppression qui
# arriverait via `strfry import`/backfill_constellation.sh, qui n'invoque
# jamais writePolicy (cf. NIP-101/KIND_REGISTRY.md, section kind 30852).
################################################################################

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

source "$MY_PATH/common.sh"
source "$MY_PATH/../protected_kinds.sh"

LOG_FILE="$HOME/.zen/tmp/nostr_kind5.log"
ensure_log_dir "$LOG_FILE"
log_del() { log_with_timestamp "$LOG_FILE" "$1"; }

event_json="$1"
extract_event_data "$event_json"

e_ids=$(echo "$event_json" | jq -r '.event.tags[]? | select(.[0]=="e") | .[1]' 2>/dev/null)

if [[ -z "$e_ids" ]]; then
    # Rien à protéger — comportement natif NIP-09 de strfry s'applique.
    exit 0
fi

    ids_json=$(printf '%s\n' "$e_ids" | jq -R . | jq -sc .)

    # N2_STRFRY_DIR : même convention que n2_ledger_lib.sh (surchargeable pour les
    # tests en sandbox isolé) — défaut identique au reste du dépôt.
    _strfry_dir="${N2_STRFRY_DIR:-$HOME/.zen/strfry}"
    if [[ ! -x "${_strfry_dir}/strfry" ]]; then
        # Impossible de vérifier — par prudence, ne bloque pas ici (le NIP-09 natif
        # de strfry reste le dernier mot dans ce cas dégradé).
        exit 0
    fi

    targeted_kinds=$(cd "$_strfry_dir" && ./strfry scan "{\"ids\":${ids_json}}" 2>/dev/null | jq -r '.kind' 2>/dev/null)

for k in $targeted_kinds; do
    for protected in "${PROTECTED_KINDS[@]}"; do
        if [[ "$k" == "$protected" ]]; then
            log_del "REJECTED: tentative de suppression ciblant un event kind $k (protégé, immuable) par ${pubkey:0:8}... — event ${event_id:0:8}..."
            nip101_log_event "5" "rejected_protected_kind" "0" "{\"protected_kind\":${k}}"
            exit 1
        fi
    done
done

log_del "ACCEPTED: suppression sans cible protégée — ${pubkey:0:8}... — event ${event_id:0:8}..."
exit 0
