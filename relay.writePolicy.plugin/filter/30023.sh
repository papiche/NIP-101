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

_log_30023() { :; }  # silent logger for check_authorization
if ! check_authorization "$pubkey" "_log_30023"; then
    echo ">>> (30023) REJECTED: Blog article from unauthorized ${pubkey:0:8}..."
    exit 1
fi

echo ">>> (30023) BLOG: ${title:-'Untitled Article'} (ID: ${article_id:-'no-id'}) from ${pubkey:0:8}... (${EMAIL})"

exit 0
