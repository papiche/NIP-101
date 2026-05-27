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

if [[ "${DEBUG:-0}" == "1" ]]; then
    RELAY_TAG=$(echo "$event_json" | jq -r '(.event.tags // [])[] | select(.[0]=="relay") | .[1]' 2>/dev/null || true)
    CHALLENGE_TAG=$(echo "$event_json" | jq -r '(.event.tags // [])[] | select(.[0]=="challenge") | .[1]' 2>/dev/null || true)
    log_event "DEBUG: Challenge=${CHALLENGE_TAG:-<vide>}"
    log_event "DEBUG: RelayTag=${RELAY_TAG:-<vide>}"
    log_event "DEBUG: Pubkey=${pubkey:-<vide>}"
fi

# Extract event_id (= the 'id' field of the event – sha256 of the serialised event)
event_id="${id:-}"

# Check authorization using common function
# Sets global: AUTHORIZED, EMAIL, SOURCE
if ! check_authorization "$pubkey" "log_event"; then
    log_event "ROAMING_UNKNOWN: ${pubkey:0:8}... non reconnu localement — tentative roaming éphémère"

    if resolve_email_from_kind0 "$pubkey"; then
        EMAIL="$_RESOLVED_EMAIL"
        SOURCE="unknown_roaming"
        log_event "ROAMING_UNKNOWN: email récupéré via kind 0 → $EMAIL (${pubkey:0:8}…)"
        # Continue vers la création du marker (pas d'exit)
    else
        # Fallback pubkey-only : créer un répertoire éphémère minimal
        _PUBKEY_DIR="${HOME}/.zen/game/nostr/.pubkey_${pubkey}"
        mkdir -p "$_PUBKEY_DIR"
        printf '%s\n' "$pubkey" > "$_PUBKEY_DIR/HEX"
        touch "$_PUBKEY_DIR/.roaming"
        printf '%s\n' "UNKNOWN_ROAMING" > "$_PUBKEY_DIR/SOURCE"
        NIP42_MARKER="${_PUBKEY_DIR}/.nip42_auth_${pubkey}"
        NOW_TS=$(date +%s)
        printf '{"pubkey":"%s","event_hash":"%s","created_at":%s}' \
            "$pubkey" "$event_id" "$NOW_TS" > "$NIP42_MARKER" 2>/dev/null
        log_event "ACCEPTED_EPHEMERAL: ${pubkey:0:8}... marker pubkey-only créé (répertoire ${_PUBKEY_DIR##*/})"
        exit 0
    fi
fi

# ── WHITELIST AMIS : marker pubkey-only immédiat ────────────────────────────
# amisOfAmis = whitelist de comptes NOSTR tiers (pas de MULTIPASS, pas d'email).
# Pas de roaming, pas de résolution email — marker minimal et on accepte.
if [[ "$SOURCE" == "amisOfAmis" ]]; then
    _PUBKEY_DIR="${HOME}/.zen/game/nostr/.pubkey_${pubkey}"
    mkdir -p "$_PUBKEY_DIR"
    printf '%s\n' "$pubkey" > "$_PUBKEY_DIR/HEX"
    printf '%s\n' "AMIS" > "$_PUBKEY_DIR/SOURCE"
    NIP42_MARKER="${_PUBKEY_DIR}/.nip42_auth_${pubkey}"
    NOW_TS=$(date +%s)
    printf '{"pubkey":"%s","event_hash":"%s","created_at":%s}' \
        "$pubkey" "$event_id" "$NOW_TS" > "$NIP42_MARKER" 2>/dev/null
    log_event "ACCEPTED_AMIS: ${pubkey:0:8}... marker pubkey-only créé (whitelist amisOfAmis)"
    exit 0
fi

# ── Create / refresh the secure local NIP-42 auth marker ────────────────────
# EMAIL is set by check_authorization (e.g. "fred@example.com").
# Only create the marker for real email addresses (skip "amisOfAmis" sentinel).
if [[ -n "$EMAIL" && "$EMAIL" =~ $EMAIL_REGEX ]]; then

    MARKER_DIR="$KEY_DIR/$EMAIL"

    # ── GESTION DU ROAMING ───────────────────────────────────────────────────
    # Si le joueur vient du Swarm, son dossier local n'existe pas encore.
    # On crée le répertoire, on y place le HEX pour l'API Python, 
    # et SURTOUT on place le flag .roaming pour éviter que NOSTRCARD.refresh.sh
    # ne tente de traiter ce profil.
    if [[ ! -d "$MARKER_DIR" ]]; then
        mkdir -p "$MARKER_DIR"
        printf '%s\n' "$pubkey" > "$MARKER_DIR/HEX"
        touch "$MARKER_DIR/.roaming"
        if [[ "$SOURCE" == "amisOfAmis_roaming" ]]; then
            printf '%s\n' "AMIS_ROAMING" > "$MARKER_DIR/SOURCE"
            [[ -n "$_HOME_IPFSNODEID" ]] && \
                printf '%s\n' "$_HOME_IPFSNODEID" > "$MARKER_DIR/HOME_IPFSNODEID"
        else
            printf '%s\n' "SWARM_ROAMING" > "$MARKER_DIR/SOURCE"
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

    # ── ROAMING CONTEXT : Sauvegarde des métadonnées depuis le cache swarm ──────
    # Si le player vient du swarm, copier tous les fichiers disponibles dans TW/EMAIL/
    # pour que geo.py (/api/myGPS) puisse résoudre le GPS et retourner home_node_hex
    # (nécessaire à BRO_chat.js pour adresser les DMs NIP-44 à la bonne home station).
    if [[ "$SOURCE" == "swarm" ]]; then
        (
        _SWARM_TW_DIR=$(ls -d "${HOME}/.zen/tmp/swarm/"*/TW/"${EMAIL}" 2>/dev/null | head -1)

        for _swarm_file in NOSTRNS G1PUBNOSTR GPS NPUB HEX; do
            _val=$(cat "${_SWARM_TW_DIR}/${_swarm_file}" 2>/dev/null)
            if [[ -n "$_val" ]]; then
                printf '%s\n' "$_val" > "${MARKER_DIR}/${_swarm_file}"
                log_event "ROAMING_CONTEXT: ${_swarm_file} sauvegardé pour ${EMAIL}"
            fi
        done
        # Vérification d'intégrité : HEX swarm doit être identique à la NOSTR pubkey NIP-42
        _swarm_hex=$(cat "${_SWARM_TW_DIR}/HEX" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$_swarm_hex" && "$_swarm_hex" != "$pubkey" ]]; then
            log_event "SECURITY_ALERT: HEX divergence pour ${EMAIL} — NIP42=${pubkey:0:16}… SWARM=${_swarm_hex:0:16}…"
            _captainemail=$(cat "${HOME}/.zen/game/players/.current/.player" 2>/dev/null | tr -d '[:space:]')
            if [[ -n "$_captainemail" ]]; then
                _mailjet="${HOME}/.zen/Astroport.ONE/tools/mailjet.sh"
                _alert_html="<p>⚠️ Divergence HEX détectée lors du roaming NIP-42 pour <strong>${EMAIL}</strong></p>
<table><tr><td>NIP-42 pubkey</td><td><code>${pubkey}</code></td></tr>
<tr><td>HEX swarm TW</td><td><code>${_swarm_hex}</code></td></tr>
<tr><td>Répertoire</td><td><code>${MARKER_DIR}</code></td></tr></table>
<p>La clé NIP-42 a été imposée comme référence.</p>"
                [[ -x "$_mailjet" ]] && \
                    "$_mailjet" --template "$0" --expire 48h \
                        "$_captainemail" "$_alert_html" \
                        "🚨 HEX divergence roaming ${EMAIL}" 2>/dev/null &
            fi
            # Imposer la NOSTR pubkey NIP-42 comme référence (les deux doivent être identiques)
            printf '%s\n' "$pubkey" > "${MARKER_DIR}/HEX"
        fi

        # ── Résoudre HOME_IPFSNODEID + HOME_NODEHEX depuis le path swarm ──────
        # Le répertoire swarm est ~/.zen/tmp/swarm/<HOME_IPFSNODEID>/TW/<email>/
        # Le NODEHEX de la home station est dans son 12345.json.
        # Ces deux valeurs sont nécessaires à BRO_chat.js pour router les DMs
        # via le relay constellation (wss://relay.copylaradio.com) vers le bon NODE.
        if [[ -n "$_SWARM_TW_DIR" ]]; then
            _HOME_IPFSNODEID=$(echo "$_SWARM_TW_DIR" | sed 's|.*/swarm/\([^/]*\)/TW/.*|\1|')
            if [[ -n "$_HOME_IPFSNODEID" ]]; then
                printf '%s\n' "$_HOME_IPFSNODEID" > "${MARKER_DIR}/HOME_IPFSNODEID"
                log_event "ROAMING_CONTEXT: HOME_IPFSNODEID=$_HOME_IPFSNODEID sauvegardé pour ${EMAIL}"

                _HOME_12345="${HOME}/.zen/tmp/swarm/${_HOME_IPFSNODEID}/12345.json"
                if [[ -s "$_HOME_12345" ]]; then
                    _HOME_NODEHEX=$(jq -r '.NODEHEX // ""' "$_HOME_12345" 2>/dev/null)
                    if [[ -n "$_HOME_NODEHEX" && ${#_HOME_NODEHEX} -eq 64 ]]; then
                        printf '%s\n' "$_HOME_NODEHEX" > "${MARKER_DIR}/HOME_NODEHEX"
                        log_event "ROAMING_CONTEXT: HOME_NODEHEX=${_HOME_NODEHEX:0:12}… sauvegardé pour ${EMAIL}"
                    fi
                fi
            fi
        fi

        if [[ -s "${MARKER_DIR}/NOSTRNS" ]]; then
            _NOSTRNS_PATH=$(cat "${MARKER_DIR}/NOSTRNS")
            log_event "ROAMING_IPNS: ipfs get ${_NOSTRNS_PATH}/${EMAIL} → ${HOME}/.zen/game/nostr"
            ipfs get --timeout=60s \
                --output="${HOME}/.zen/game/nostr/${EMAIL}" \
                "${_NOSTRNS_PATH}/${EMAIL}" 2>/dev/null \
                && log_event "ROAMING_IPNS: vault récupéré OK pour ${EMAIL}" \
                || log_event "ROAMING_IPNS_WARN: ipfs get échoué (${_NOSTRNS_PATH}/${EMAIL})"
            # Préserver le flag .roaming pour que NOSTRCARD.refresh.sh ignore ce profil
            touch "${MARKER_DIR}/.roaming"
        else
            log_event "ROAMING_CONTEXT: NOSTRNS introuvable pour ${EMAIL} dans le swarm"
        fi
        ) &
        disown
    fi
fi

# Log the successful event
log_event "ACCEPTED: Kind 22242 event from ${pubkey}... (event: ${event_id:0:16}..., Email: $EMAIL, Source: $SOURCE)"

exit 0