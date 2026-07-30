#!/bin/bash
################################################################################
# Author: Fred (support@qo-op.com)
# License: AGPL-3.0
################################################################################
#~ n2_ledger_lib.sh
#~ Calcul de solde MUTUALISÉ pour le ledger Ğ1-Nostr (kind 30852, cf.
#~ NIP-101/KIND_REGISTRY.md). Sourcé par filter/30852.sh (validation d'écriture,
#~ writePolicy strfry) ET par Astroport.ONE/tools/g1n2_check.sh / g1n2_pay.sh
#~ (lecture côté client, dual-stack G1_MODE) — UNE SEULE implémentation du
#~ calcul de solde, jamais deux qui pourraient diverger silencieusement : le
#~ filtre est la seule autorité de validation, tout le reste n'est que lecteur.
#
# Cache : ~/.zen/tmp/$IPFSNODEID/n2_ledger/<pubkey_hex>.json
#   {"balance": <nombre>, "last_tx_id": "<id hex64 ou \"\">", "cached_at": <unix ts>}
#
# Chaque fonction est autonome (pas d'état de module) — aucune dépendance à
# common.sh, pour rester sourçable aussi bien depuis NIP-101 que depuis
# Astroport.ONE sans dupliquer de logique d'auth NOSTR non pertinente ici.
################################################################################

N2_STRFRY_DIR="${N2_STRFRY_DIR:-$HOME/.zen/strfry}"
N2_LEDGER_DIR="${N2_LEDGER_DIR:-$HOME/.zen/tmp/${IPFSNODEID:-_local}/n2_ledger}"

n2_ledger_cache_file() {
    echo "${N2_LEDGER_DIR}/${1}.json"
}

## Lit le cache existant SANS jamais recalculer — chemin chaud, aucun I/O relay.
## Sortie : "balance|last_tx_id" ("0|" si jamais aucune transaction pour ce pubkey).
## Usage : IFS='|' read -r balance last_tx_id <<< "$(n2_ledger_cache_read "$pubkey")"
n2_ledger_cache_read() {
    local pubkey="$1" cache_file
    cache_file=$(n2_ledger_cache_file "$pubkey")
    if [[ -s "$cache_file" ]]; then
        jq -r '[(.balance // 0), (.last_tx_id // "")] | join("|")' "$cache_file" 2>/dev/null || echo "0|"
    else
        echo "0|"
    fi
}

## Écrit le cache de façon ATOMIQUE (tmpfile + mv) — jamais de lecture partielle
## possible par un autre process pendant l'écriture.
n2_ledger_cache_write() {
    local pubkey="$1" balance="$2" last_tx_id="$3" cache_file tmp
    mkdir -p "$N2_LEDGER_DIR" 2>/dev/null
    cache_file=$(n2_ledger_cache_file "$pubkey")
    tmp=$(mktemp "${cache_file}.XXXXXX" 2>/dev/null) || return 1
    jq -cn --argjson balance "${balance:-0}" --arg last_tx_id "${last_tx_id:-}" --argjson cached_at "$(date +%s)" \
        '{balance: $balance, last_tx_id: $last_tx_id, cached_at: $cached_at}' > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$cache_file" \
        || { rm -f "$tmp"; return 1; }
}

## Anti-rejeu / anti-réécriture rétroactive : un event ADRESSABLE strfry (kind
## 30000-39999) REMPLACE un event de même d-tag — sans cette vérification, un
## auteur pourrait donc réécrire une de ses propres transactions passées en
## republiant avec le même d. Scan ciblé sur authors+#d (indexé, bon marché —
## PAS un scan complet de l'historique).
## Retourne 0 (vrai) si un event {authors:[pubkey], #d:[d_tag]} existe déjà.
n2_ledger_dtag_exists() {
    local pubkey="$1" d_tag="$2"
    [[ -x "${N2_STRFRY_DIR}/strfry" ]] || return 1
    local count
    count=$(cd "$N2_STRFRY_DIR" && ./strfry scan \
        "{\"kinds\":[30852],\"authors\":[\"${pubkey}\"],\"#d\":[\"${d_tag}\"]}" 2>/dev/null \
        | grep -c '"id"') || count=0
    [[ "${count:-0}" -gt 0 ]]
}

## Recalcule intégralement solde + last_tx_id d'un auteur via UN SEUL strfry
## scan combiné (émis + reçus, filtre multi-objets = sémantique OR NIP-01) —
## jamais un scan par transaction historique. Écrit le cache et affiche
## "balance|last_tx_id". À utiliser au chemin froid (cache absent) ou --fresh.
n2_ledger_rescan_author() {
    local pubkey="$1"
    [[ -x "${N2_STRFRY_DIR}/strfry" ]] || { echo "0|"; return 1; }

    local raw
    raw=$(cd "$N2_STRFRY_DIR" && ./strfry scan \
        "[{\"kinds\":[30852],\"authors\":[\"${pubkey}\"]},{\"kinds\":[30852],\"#p\":[\"${pubkey}\"]}]" \
        2>/dev/null)

    local result
    result=$(echo "$raw" | jq -rs --arg me "$pubkey" '
        {
            received: ([.[] | select(.pubkey != $me)
                              | select(any(.tags[]; .[0]=="p" and .[1]==$me))
                              | (.tags[] | select(.[0]=="amount") | .[1] | tonumber)] | add // 0),
            sent:     ([.[] | select(.pubkey == $me)
                              | select((any(.tags[]; .[0]=="t" and .[1]=="mint")) | not)
                              | (.tags[] | select(.[0]=="amount") | .[1] | tonumber)] | add // 0),
            last_tx:  ([.[] | select(.pubkey == $me)]
                       | if length > 0 then (sort_by(.created_at) | last | .id) else "" end)
        } | "\(.received - .sent)|\(.last_tx)"
    ' 2>/dev/null)
    [[ -z "$result" || "$result" == "null|" ]] && result="0|"

    local balance last_tx_id
    IFS='|' read -r balance last_tx_id <<< "$result"
    n2_ledger_cache_write "$pubkey" "$balance" "$last_tx_id"
    echo "$result"
}

## Point d'entrée unique pour un lecteur (g1n2_check.sh) : cache si présent,
## sinon rescan complet. Ne JAMAIS dupliquer cette logique ailleurs.
n2_ledger_get_balance() {
    local pubkey="$1" fresh="${2:-false}"
    if [[ "$fresh" == "true" ]]; then
        n2_ledger_rescan_author "$pubkey"
        return
    fi
    local cache_file
    cache_file=$(n2_ledger_cache_file "$pubkey")
    if [[ -s "$cache_file" ]]; then
        n2_ledger_cache_read "$pubkey"
    else
        n2_ledger_rescan_author "$pubkey"
    fi
}
