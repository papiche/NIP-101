#!/bin/bash
# filter/30023.sh (OPTIMIZED)
# This script handles Nostr events of kind:30023 (long-form content/articles)

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions  
source "$MY_PATH/common.sh"

# Extract event data in one optimized call
event_json="$1"
extract_event_data "$event_json"

# Extract specific tags for kind 30023 events
extract_tags "$event_json" "title" "d" "published_at"
title="$title"
article_id="$d"
published_at="$published_at"

## Ce filtre n'écrivait que sur stdout (capturé par strfry, pas de fichier
## dédié ni d'évènement structuré) — seul autre filtre dans ce cas avec kind 4.
LOG_FILE="$HOME/.zen/tmp/nostr_kind30023.log"
ensure_log_dir "$LOG_FILE"

_log_30023() { :; }  # silent logger for check_authorization
if ! check_authorization "$pubkey" "_log_30023"; then
    echo ">>> (30023) REJECTED: Blog article from unauthorized ${pubkey:0:8}..."
    log_with_timestamp "$LOG_FILE" "REJECTED: Blog article from unauthorized ${pubkey:0:8}..."
    nip101_log_event "30023" "rejected" 0 "{\"pubkey\":\"${pubkey:0:12}\"}"
    exit 1
fi

echo ">>> (30023) BLOG: ${title:-'Untitled Article'} (ID: ${article_id:-'no-id'}) from ${pubkey:0:8}... (${EMAIL})"
log_with_timestamp "$LOG_FILE" "ACCEPTED: ${title:-'Untitled Article'} (ID: ${article_id:-'no-id'}) from ${pubkey:0:8}..."
nip101_log_event "30023" "accepted" 1 "{\"pubkey\":\"${pubkey:0:12}\",\"article_id\":\"${article_id:-}\"}"

exit 0
