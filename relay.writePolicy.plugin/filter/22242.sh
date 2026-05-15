#!/bin/bash
# filter/22242.sh (HARDENED – 2026-03)
# This script handles Nostr events of kind:22242 (NIP-42 Client Authentication)
#
# IMPORTANT – Ephemeral events
# ─────────────────────────────
# Kind 22242 is in the ephemeral range 20000-29999 (NIP-01).  strfry forwards
# these events to live subscribers but does NOT persist them in its database.
# That means a subsequent REQ or `strfry scan` will never find them.
#
# Security hardening (see UPassport docs/NIP42_SECURITY.md):
#
#  A. Pubkey-bound filename
#     Marker is named  ~/.zen/game/nostr/<email>/.nip42_auth_<hex_pubkey>
#     so a marker for Alice cannot authenticate Bob (pubkey-confusion attack).
#
#  B. Short TTL – 300 s enforced on the API side (was 3 600 s).
#
#  C. JSON content
#     Marker contains {"pubkey":"<hex>","event_hash":"<event_id>","created_at":<ts>}
#     The API cross-checks the embedded pubkey against the filename to detect
#     mis-placed or copied markers.
#
# The UPassport API (54321.py → services/nostr.py → check_nip42_auth_local_marker)
# uses the marker as proof of a recent NIP-42 authentication without needing to
# query the relay database.

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr.auth.22242.log"
ensure_log_dir "$LOG_FILE"

# Logging function
log_event() {
    log_with_timestamp "$LOG_FILE" "$1"
}

# Extract event data in one optimized call
# Sets: pubkey, kind, id, created_at, tags, content (all from the event JSON)
event_json="$1"
extract_event_data "$event_json"

# Extract event_id (= the 'id' field of the event – sha256 of the serialised event)
event_id="${id:-}"

# Check authorization using common function
# Sets global: AUTHORIZED, EMAIL, SOURCE
if ! check_authorization "$pubkey" "log_event"; then
    exit 1
fi

# ── ROAMING AMIS : Identification email via profil kind 0 ───────────────────
# Quand SOURCE=amisOfAmis, le joueur vient d'un réseau hors-swarm local.
# On tente d'extraire son email depuis son profil NOSTR (kind 0) pour activer
# le répertoire roaming éphémère et permettre la création du marker NIP-42.
if [[ "$SOURCE" == "amisOfAmis" ]]; then
    if cd "${HOME}/.zen/strfry" 2>/dev/null; then
        _AMIS_PROFILE=$(./strfry scan \
            "{\"authors\":[\"${pubkey}\"],\"kinds\":[0]}" 2>/dev/null | \
            jq -s 'if length > 0 then max_by(.created_at) else null end' 2>/dev/null)
        cd - >/dev/null 2>&1
        if [[ -n "$_AMIS_PROFILE" && "$_AMIS_PROFILE" != "null" ]]; then
            # 1. Tag ["i", "email:ADDR", ""] — source la plus fiable (nostr_setup_profile.py)
            _AMIS_EMAIL=$(echo "$_AMIS_PROFILE" | \
                jq -r '(.tags // [])[] | select(.[0] == "i" and (.[1] | startswith("email:"))) | .[1][6:]' \
                2>/dev/null | head -1)
            # 2. Fallback : email extrait du champ website (URL IPNS UPlanet)
            if [[ -z "$_AMIS_EMAIL" ]]; then
                _AMIS_WEBSITE=$(echo "$_AMIS_PROFILE" | \
                    jq -r '.content | fromjson | .website // ""' 2>/dev/null)
                _AMIS_EMAIL=$(echo "$_AMIS_WEBSITE" | \
                    grep -oP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | head -1)
            fi
            # 3. Fallback : champ nip05
            if [[ -z "$_AMIS_EMAIL" ]]; then
                _AMIS_NIP05=$(echo "$_AMIS_PROFILE" | \
                    jq -r '.content | fromjson | .nip05 // ""' 2>/dev/null)
                _AMIS_EMAIL=$(echo "$_AMIS_NIP05" | \
                    grep -oP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' | head -1)
            fi
            if [[ -n "$_AMIS_EMAIL" ]]; then
                EMAIL="$_AMIS_EMAIL"
                SOURCE="amisOfAmis_roaming"
                log_event "ROAMING_AMIS: Email identifié via profil kind 0 : $_AMIS_EMAIL (${pubkey:0:8}…)"
            fi
        fi
    fi
fi

# ── Create / refresh the secure local NIP-42 auth marker ────────────────────
# EMAIL is set by check_authorization (e.g. "fred@example.com").
# Only create the marker for real email addresses (skip "amisOfAmis" sentinel).
if [[ -n "$EMAIL" && "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then

    MARKER_DIR="$KEY_DIR/$EMAIL"

    # ── GESTION DU ROAMING ───────────────────────────────────────────────────
    # Si le joueur vient du Swarm, son dossier local n'existe pas encore.
    # On crée le répertoire, on y place le HEX pour l'API Python, 
    # et SURTOUT on place le flag .roaming pour éviter que NOSTRCARD.refresh.sh
    # ne tente de traiter ce profil.
    if [[ ! -d "$MARKER_DIR" ]]; then
        mkdir -p "$MARKER_DIR"
        echo "$pubkey" > "$MARKER_DIR/HEX"
        touch "$MARKER_DIR/.roaming"
        if [[ "$SOURCE" == "amisOfAmis_roaming" ]]; then
            echo "AMIS_ROAMING" > "$MARKER_DIR/SOURCE"
        else
            echo "SWARM_ROAMING" > "$MARKER_DIR/SOURCE"
        fi
        log_event "ROAMING: Création du profil local éphémère pour $EMAIL (source: $SOURCE)"
    fi
    
    # ── A. pubkey-bound filename ─────────────────────────────────────────────
    # New secure name: .nip42_auth_<hex_pubkey>
    NIP42_MARKER="${MARKER_DIR}/.nip42_auth_${pubkey}"

    # ── C. JSON content with pubkey + event_hash + timestamp ─────────────────
    NOW_TS=$(date +%s)
    MARKER_JSON="{\"pubkey\":\"${pubkey}\",\"event_hash\":\"${event_id}\",\"created_at\":${NOW_TS}}"

    if printf '%s' "$MARKER_JSON" > "$NIP42_MARKER" 2>/dev/null; then
        log_event "MARKER: Secure NIP-42 auth marker written for $EMAIL → ${NIP42_MARKER##*/}"
    else
        log_event "MARKER_WARN: Could not write NIP-42 auth marker for $EMAIL (path: $NIP42_MARKER)"
    fi

    # ── Remove any stale generic (old-format) marker if it still exists ──────
    OLD_MARKER="${MARKER_DIR}/.nip42_auth"
    [[ -f "$OLD_MARKER" ]] && rm -f "$OLD_MARKER" 2>/dev/null && \
        log_event "CLEANUP: Removed legacy .nip42_auth marker for $EMAIL"

    # ── ROAMING CONTEXT : Sauvegarde des métadonnées pour la home station ──────
    # Si le player vient du swarm, sauvegarder NOSTRNS + G1PUBNOSTR pour que
    # NOSTRCARD.refresh.sh puisse router les DMs de sync vers la home station.
    # La publication IPNS reste EXCLUSIVEMENT sur la home station via DM NIP-04.
    if [[ "$SOURCE" == "swarm" ]]; then
        (
        _ROAM_NOSTRNS=$(cat "${HOME}/.zen/tmp/swarm/"*/TW/"${EMAIL}"/NOSTRNS 2>/dev/null | head -1)
        _ROAM_G1PUB=$(cat "${HOME}/.zen/tmp/swarm/"*/TW/"${EMAIL}"/G1PUBNOSTR 2>/dev/null | head -1)

        if [[ -n "$_ROAM_NOSTRNS" ]]; then
            echo "$_ROAM_NOSTRNS" > "${MARKER_DIR}/NOSTRNS"
            log_event "ROAMING_CONTEXT: NOSTRNS sauvegardé pour ${EMAIL}"
        fi
        if [[ -n "$_ROAM_G1PUB" ]]; then
            echo "$_ROAM_G1PUB" > "${MARKER_DIR}/G1PUBNOSTR"
            log_event "ROAMING_CONTEXT: G1PUBNOSTR sauvegardé pour ${EMAIL}"
        fi

        if [[ -n "$_ROAM_NOSTRNS" ]]; then
            log_event "ROAMING_CONTEXT: ${EMAIL} enregistré pour sync DM via home station"
        else
            log_event "ROAMING_CONTEXT: NOSTRNS introuvable pour ${EMAIL} dans le swarm"
        fi
        ) &
    fi
fi

# Log the successful event
log_event "ACCEPTED: Kind 22242 event from ${pubkey:0:8}... (event: ${event_id:0:16}..., Email: $EMAIL, Source: $SOURCE)"

exit 0