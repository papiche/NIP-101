#!/bin/bash
# filter/22242.sh (OPTIMIZED)
# This script handles Nostr events of kind:22242 (NIP-42 Client Authentication)
#
# IMPORTANT – Ephemeral events
# ─────────────────────────────
# Kind 22242 is in the ephemeral range 20000-29999 (NIP-01).  strfry forwards
# these events to live subscribers but does NOT persist them in its database.
# That means a subsequent REQ or `strfry scan` will never find them.
#
# Fix: when this filter ACCEPTS an event it creates (or touches) the file
#   ~/.zen/game/nostr/<EMAIL>/.nip42_auth
# The UPassport API (54321.py → services/nostr.py → check_nip42_auth_local_marker)
# uses that marker as proof of a recent NIP-42 authentication without needing to
# query the relay database.  The marker is valid for 1 hour (TTL enforced on
# the API side).

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
event_json="$1"
extract_event_data "$event_json"

# Check authorization using common function
# Sets global: AUTHORIZED, EMAIL, SOURCE
if ! check_authorization "$pubkey" "log_event"; then
    exit 1
fi

# ── Create / refresh the local NIP-42 auth marker ───────────────────────────
# EMAIL is set by check_authorization (e.g. "fred@example.com").
# Only create the marker for real email addresses (skip "amisOfAmis" sentinel).
if [[ -n "$EMAIL" && "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    NIP42_MARKER="$KEY_DIR/$EMAIL/.nip42_auth"
    if touch "$NIP42_MARKER" 2>/dev/null; then
        log_event "MARKER: Created/refreshed NIP-42 auth marker for $EMAIL → $NIP42_MARKER"
    else
        log_event "MARKER_WARN: Could not create NIP-42 auth marker for $EMAIL (path: $NIP42_MARKER)"
    fi
fi

# Log the successful event
log_event "ACCEPTED: Kind 22242 event from ${pubkey:0:8}... (Email: $EMAIL, Source: $SOURCE)"

exit 0