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
        echo "SWARM_ROAMING" > "$MARKER_DIR/SOURCE"
        log_event "ROAMING: Création du profil local éphémère pour $EMAIL"
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

    # ── ROAMING PARFAIT : Récupération des secrets depuis IPNS ──────────────
    # Si le player vient du swarm (SOURCE=swarm), télécharger ses secrets
    # chiffrés avec UPLANETNAME depuis son IPNS home, les déchiffrer localement,
    # et importer la clé IPNS pour permettre la publication du manifest uDRIVE.
    # Lancé en background pour ne pas bloquer strfry (writePolicy synchrone).
    if [[ "$SOURCE" == "swarm" ]]; then
        (
        _ASTRO="${HOME}/.zen/Astroport.ONE/tools"

        # Trouver NOSTRNS et G1PUBNOSTR dans les données swarm de la constellation
        _ROAM_NOSTRNS=$(cat "${HOME}/.zen/tmp/swarm/"*/TW/"${EMAIL}"/NOSTRNS 2>/dev/null | head -1)
        _ROAM_G1PUB=$(cat "${HOME}/.zen/tmp/swarm/"*/TW/"${EMAIL}"/G1PUBNOSTR 2>/dev/null | head -1)

        # Secrets déjà présents — rien à re-télécharger
        if [[ -s "${MARKER_DIR}/.secret.ipns" && -s "${MARKER_DIR}/.secret.nostr" ]]; then
            log_event "ROAMING_SECRETS: Secrets déjà présents pour ${EMAIL}"
            exit 0
        fi

        # uplanet.dunikey créé par my.sh — présent si la station est initialisée
        if [[ -n "$_ROAM_NOSTRNS" && -s "${HOME}/.zen/game/uplanet.dunikey" ]]; then

            log_event "ROAMING_SECRETS: ${EMAIL} ← ${_ROAM_NOSTRNS:0:25}..."
            _rk="${HOME}/.zen/game/uplanet.dunikey"
            _ok=0
            for _s in .secret.nostr .secret.dunikey .secret.ipns; do
                _et=$(mktemp)
                # Télécharger le secret chiffré depuis l'IPNS home du player
                if timeout 20 ipfs cat "${_ROAM_NOSTRNS}/${EMAIL}/${_s}.uplanet.enc" \
                        > "$_et" 2>/dev/null && [[ -s "$_et" ]]; then
                    # Déchiffrer avec la clé duniter UPLANET locale
                    if "${_ASTRO}/natools.py" decrypt -f pubsec \
                            -i "$_et" -k "$_rk" \
                            -o "${MARKER_DIR}/${_s}" 2>/dev/null \
                            && [[ -s "${MARKER_DIR}/${_s}" ]]; then
                        chmod 600 "${MARKER_DIR}/${_s}"
                        _ok=$((_ok + 1))
                        log_event "ROAMING_SECRETS: ✅ ${_s} déchiffré"
                    fi
                fi
                rm -f "$_et"
            done

            # Importer la clé IPNS dans le keystore local pour publish du manifest
            if [[ -s "${MARKER_DIR}/.secret.ipns" && -n "$_ROAM_G1PUB" ]]; then
                _kname="${_ROAM_G1PUB}:NOSTR"
                if ! ipfs key list 2>/dev/null | grep -qF "$_kname"; then
                    ipfs key import "$_kname" -f pem-pkcs8-cleartext \
                        "${MARKER_DIR}/.secret.ipns" >/dev/null 2>&1 \
                        && log_event "ROAMING_SECRETS: ✅ Clé IPNS importée: ${_kname}"
                else
                    log_event "ROAMING_SECRETS: Clé IPNS déjà présente: ${_kname}"
                fi
                # Sauvegarder les métadonnées pour NOSTRCARD.refresh.sh roaming loop
                echo "$_ROAM_NOSTRNS" > "${MARKER_DIR}/NOSTRNS"
                echo "$_ROAM_G1PUB"  > "${MARKER_DIR}/G1PUBNOSTR"
            fi

            log_event "ROAMING_SECRETS: ${_ok}/3 secrets récupérés → roaming parfait activé"
        else
            log_event "ROAMING_SECRETS: NOSTRNS/uplanet.dunikey manquant pour ${EMAIL} (roaming partiel)"
        fi
        ) &
    fi
fi

# Log the successful event
log_event "ACCEPTED: Kind 22242 event from ${pubkey:0:8}... (event: ${event_id:0:16}..., Email: $EMAIL, Source: $SOURCE)"

exit 0