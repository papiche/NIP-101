#!/bin/bash
# filter/30023.sh
# This script is designed to handle Nostr events of kind:30023,
# which are used for long-form text content such as articles or blog posts.
#
# NIP-23 Overview:
# - kind:30023 is used for published long-form content.
# - kind:30024 is used for drafts of long-form content.
# - The content must be in Markdown syntax without HTML and without hard line-breaks.
# - Metadata can include title, image, summary, and published_at timestamp.
# - Articles are editable and should include a 'd' tag for identification.
# - Linking is done using NIP-19 naddr code and the 'a' tag.
# - References to other Nostr notes, articles, or profiles must follow NIP-27 and NIP-21.
# - Replies to kind:30023 must use kind:1111 comments as per NIP-22.
#
# Example Event Structure:
# {
#   "kind": 30023,
#   "created_at": 1675642635,
#   "content": "Markdown content here...",
#   "tags": [
#     ["d", "article-identifier"],
#     ["title", "Article Title"],
#     ["published_at", "1296962229"],
#     ["t", "topic"],
#     ["e", "event-id", "relay-url"],
#     ["a", "naddr-code", "relay-url"]
#   ],
#   "pubkey": "...",
#   "id": "..."
# }
event_json="$1"
# Script logic starts here
# ...
title=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "title") | .[1]')
echo ">>> (30023) BLOG: $title"

exit 0
