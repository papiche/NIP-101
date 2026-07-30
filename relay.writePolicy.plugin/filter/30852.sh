#!/bin/bash
################################################################################
# Author: Fred (support@qo-op.com)
# License: AGPL-3.0
################################################################################
#~ filter/30852.sh — Kind 30852 : transaction Ğ1-Nostr (N²)
#
# Ledger local au relay strfry, sans consensus multi-nœuds — CE FILTRE est le
# seul arbitre de validité d'une transaction. Anti-double-dépense par chaînage
# `prev` (référence à la dernière transaction sortante connue de l'auteur) +
# vérification de solde (Σreçus - Σenvoyés, via n2_ledger_lib.sh, un seul scan
# combiné). Anti-réécriture rétroactive par vérification de doublon sur le
# tag `d`. Anti-suppression : cf. filter/5.sh (kind 30852 dans PROTECTED_KINDS).
#
# Format de l'event (cf. NIP-101/KIND_REGISTRY.md) :
#   tags: [["d","n2-<ts>-<nonce>"],["p","<hex64 dest>"],["amount","12.50"],
#          ["prev","<hex64 ou 'genesis'>"],["t","g1-n2"],["t","mint"]?]
#   content: "" (libre, non normatif — aucune vérification ne s'y appuie)
#
# LIMITES DE CE MODÈLE DE CONFIANCE (documentées en détail dans le plan
# d'implémentation) — la station elle-même est un tiers de confiance non
# vérifiable de l'extérieur, ce filtre ne protège que le chemin d'écriture
# client direct (jamais `strfry import`/backfill_constellation.sh — kind 30852
# ne doit JAMAIS être ajouté aux kinds synchronisés entre stations).
################################################################################

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

source "$MY_PATH/common.sh"
source "$MY_PATH/n2_ledger_lib.sh"

LOG_FILE="$HOME/.zen/tmp/nostr_kind30852.log"
ensure_log_dir "$LOG_FILE"
log_n2() { log_with_timestamp "$LOG_FILE" "$1"; }

N2_MINT_AUTHORITIES_FILE="${N2_MINT_AUTHORITIES_FILE:-$HOME/.zen/strfry/n2_mint_authorities.txt}"
N2_LOCK_FILE="${N2_LEDGER_DIR}/.lock"

event_json="$1"
extract_event_data "$event_json"

################################################################################
# 1. VALIDATION STRUCTURELLE — aucun I/O disque/réseau, rejet bon marché avant
#    tout accès au ledger. extract_tags() de common.sh CONCATÈNE les valeurs de
#    tags multiples (dangereux ici : un event malicieux avec deux tags "p"
#    différents doit être détecté, jamais silencieusement fusionné) — comptage
#    direct par jq, pas de extract_tags() pour ces 4 tags.
################################################################################

tag_counts=$(echo "$event_json" | jq -r '
    ([.event.tags[] | select(.[0]=="p")]      | length) as $p |
    ([.event.tags[] | select(.[0]=="prev")]   | length) as $prev |
    ([.event.tags[] | select(.[0]=="d")]      | length) as $d |
    ([.event.tags[] | select(.[0]=="amount")] | length) as $amount |
    "\($p) \($prev) \($d) \($amount)"
' 2>/dev/null)
read -r p_count prev_count d_count amount_count <<< "$tag_counts"

if [[ "$p_count" != "1" || "$prev_count" != "1" || "$d_count" != "1" || "$amount_count" != "1" ]]; then
    log_n2 "REJECTED: tags p/prev/d/amount dupliqués ou manquants (p=$p_count prev=$prev_count d=$d_count amount=$amount_count) — event ${event_id:0:8}..."
    exit 1
fi

dest_pubkey=$(get_tag_value "$event_json" "p")
prev_id=$(get_tag_value "$event_json" "prev")
d_tag=$(get_tag_value "$event_json" "d")
amount=$(get_tag_value "$event_json" "amount")

# amount : nombre strictement positif
if ! [[ "$amount" =~ ^[0-9]+(\.[0-9]{1,2})?$ ]] || ! awk "BEGIN{exit !($amount > 0)}"; then
    log_n2 "REJECTED: amount invalide '$amount' — event ${event_id:0:8}..."
    exit 1
fi

# destinataire : hex64 valide, jamais soi-même
if ! [[ "$dest_pubkey" =~ ^[0-9a-f]{64}$ ]]; then
    log_n2 "REJECTED: tag p invalide (pas un hex64) — event ${event_id:0:8}..."
    exit 1
fi
if [[ "$dest_pubkey" == "$pubkey" ]]; then
    log_n2 "REJECTED: auto-paiement interdit (pubkey==p) — event ${event_id:0:8}..."
    exit 1
fi

# prev : soit "genesis", soit un hex64
if [[ "$prev_id" != "genesis" ]] && ! [[ "$prev_id" =~ ^[0-9a-f]{64}$ ]]; then
    log_n2 "REJECTED: tag prev invalide (ni 'genesis' ni hex64) — event ${event_id:0:8}..."
    exit 1
fi

# d-tag : non vide, borné
if [[ -z "$d_tag" || ${#d_tag} -gt 128 ]]; then
    log_n2 "REJECTED: tag d invalide (vide ou >128 chars) — event ${event_id:0:8}..."
    exit 1
fi

# anti dérive d'horloge / anti-fork futur
now=$(date +%s)
if [[ "$created_at" -gt $((now + 300)) ]]; then
    log_n2 "REJECTED: created_at dans le futur (>5min) — event ${event_id:0:8}..."
    exit 1
fi

# tag t=mint : réservé aux pubkeys de la whitelist mint — rejet EXPLICITE d'une
# usurpation, jamais de dégradation silencieuse (ex. traiter comme transaction
# normale sans le privilège mint).
is_mint=false
if has_tag_value "$event_json" "t" "mint"; then
    if [[ -s "$N2_MINT_AUTHORITIES_FILE" ]] && grep -qF "$pubkey" "$N2_MINT_AUTHORITIES_FILE" 2>/dev/null; then
        is_mint=true
    else
        log_n2 "REJECTED: usurpation de mint — ${pubkey:0:8}... n'est pas dans n2_mint_authorities.txt — event ${event_id:0:8}..."
        exit 1
    fi
fi

# émetteur doit être un membre reconnu (player/uplanet/amisOfAmis) — le
# dispatcher (all_but_blacklist.sh) exécute CE filtre même pour "nobody" et
# accepte si le filtre renvoie 0 : cette vérification est donc nécessaire ici,
# pas optionnelle.
if ! check_authorization "$pubkey" "log_n2"; then
    exit 1
fi

################################################################################
# 2. SECTION CRITIQUE — verrou global, borné dans le temps. NE JAMAIS bloquer
#    indéfiniment : RelayServer::runWriter() est mono-thread et bloque sur la
#    pipe de ce plugin — un hang ici gèlerait tout le relais.
################################################################################

mkdir -p "$N2_LEDGER_DIR" 2>/dev/null
exec 200>"$N2_LOCK_FILE"
if ! flock -w 2 200; then
    log_n2 "REJECTED: verrou ledger indisponible (timeout 2s) — event ${event_id:0:8}..."
    exit 1
fi

################################################################################
# 3. Anti-rejeu/anti-réécriture — d-tag déjà utilisé par cet auteur ?
################################################################################

if n2_ledger_dtag_exists "$pubkey" "$d_tag"; then
    log_n2 "REJECTED: d-tag '$d_tag' déjà utilisé par ${pubkey:0:8}... (rejeu ou réécriture) — event ${event_id:0:8}..."
    exit 1
fi

################################################################################
# 4. Solde + last_tx_id de l'émetteur (cache si présent, sinon un seul scan
#    combiné émis+reçus — jamais un scan par transaction historique).
################################################################################

sender_state=$(n2_ledger_get_balance "$pubkey")
IFS='|' read -r sender_balance sender_last_tx <<< "$sender_state"

################################################################################
# 5. Vérification prev (anti-fork/anti-rejeu de chaîne)
################################################################################

if [[ -z "$sender_last_tx" ]]; then
    if [[ "$prev_id" != "genesis" ]]; then
        log_n2 "REJECTED: 1re transaction de ${pubkey:0:8}... doit référencer 'genesis' (reçu: $prev_id) — event ${event_id:0:8}..."
        exit 1
    fi
elif [[ "$prev_id" != "$sender_last_tx" ]]; then
    log_n2 "REJECTED: prev '$prev_id' != dernière tx connue '$sender_last_tx' pour ${pubkey:0:8}... — fork/rejeu/course — event ${event_id:0:8}..."
    exit 1
fi

################################################################################
# 6. Vérification de solde (sauf mint — un mint n'est jamais débité)
################################################################################

if [[ "$is_mint" != "true" ]] && ! awk "BEGIN{exit !($sender_balance >= $amount)}"; then
    log_n2 "REJECTED: solde insuffisant pour ${pubkey:0:8}... (solde=$sender_balance, demandé=$amount) — event ${event_id:0:8}..."
    exit 1
fi

################################################################################
# 7. MISE À JOUR ATOMIQUE du cache — AVANT que strfry ne commit en LMDB. C'est
#    ce qui ferme la fenêtre de course : deux transactions conflictuelles du
#    même auteur, même dans le même batch réseau, sont sérialisées par le
#    writer mono-thread MAIS `strfry scan` seul ne verrait pas la 1ère tant
#    qu'elle n'est pas committée — d'où ce cache write-through.
################################################################################

if [[ "$is_mint" == "true" ]]; then
    new_sender_balance="$sender_balance"
else
    new_sender_balance=$(awk "BEGIN{printf \"%.2f\", $sender_balance - $amount}")
fi
n2_ledger_cache_write "$pubkey" "$new_sender_balance" "$event_id"

recipient_state=$(n2_ledger_get_balance "$dest_pubkey")
IFS='|' read -r recipient_balance recipient_last_tx <<< "$recipient_state"
new_recipient_balance=$(awk "BEGIN{printf \"%.2f\", $recipient_balance + $amount}")
# last_tx_id du destinataire N'EST PAS touché ici — ne concerne que SA propre
# chaîne sortante, pas les crédits qu'il reçoit.
n2_ledger_cache_write "$dest_pubkey" "$new_recipient_balance" "$recipient_last_tx"

################################################################################
# 8. Accepté.
################################################################################

log_n2 "ACCEPTED: ${pubkey:0:8}... → ${dest_pubkey:0:8}... : ${amount}Ẑ (mint=$is_mint, d=$d_tag) — event ${event_id:0:8}..."
nip101_log_event "30852" "accepted" "1" "{\"amount\":${amount},\"mint\":${is_mint}}"
echo ">>> (30852) N² TRANSFER: ${pubkey:0:8}... → ${dest_pubkey:0:8}... : ${amount}Ẑ"
exit 0
