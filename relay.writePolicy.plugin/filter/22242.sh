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
fi

# Log the successful event
log_event "ACCEPTED: Kind 22242 event from ${pubkey:0:8}... (event: ${event_id:0:16}..., Email: $EMAIL, Source: $SOURCE)"

exit 0