#!/usr/bin/env python3
import json
import os
import subprocess
import sys

KEY_DIR = os.path.join(os.path.expanduser("~"), ".zen", "game", "nostr")
TRUST_RATING_KIND = 33  # Define the new event kind for trust ratings

def is_key_authorized(pubkey):
    """
    Check if a given public key is authorized by searching for it in the specified directory.
    """
    for root, _, files in os.walk(KEY_DIR):
        for filename in files:
            if filename == "HEX":
                filepath = os.path.join(root, filename)
                try:
                    with open(filepath, 'r') as f:
                        if pubkey in f.read():
                            return True
                except FileNotFoundError:
                    print(f"Warning: File not found: {filepath}", file=sys.stderr)
                except Exception as e:
                    print(f"Error reading {filepath}: {e}", file=sys.stderr)
    return False


def create_trust_rating_event(rater_pubkey, rated_pubkey, rating, triggering_event_id=None, category=None, lang=None):
    """
    Create a trust rating event (kind 33) as defined in NIP-101.
    """
    tags = [["p", rated_pubkey], ["rating", str(rating)]]
    if triggering_event_id:
        tags.append(["e", triggering_event_id])
    if category:
        tags.append(["category", category])
    if lang:
        tags.append(["lang", lang])

    event = {
        "kind": TRUST_RATING_KIND,
        "content": "",  # Content remains empty
        "tags": tags,
        "pubkey": rater_pubkey,
        # The 'sig' field is typically added by the client or relay after signing the event.
    }
    return event


def process_kind_0(event_json):
    """
    Process events of kind 0 (metadata).
    """
    pubkey = event_json['event']['pubkey']
    content = event_json['event']['content']

    if not is_key_authorized(pubkey):
        print(f"Unauthorized pubkey for kind 0: {pubkey}", file=sys.stderr)
        return None  # Reject

    print(f"Processing kind 0 event. pubkey: {pubkey}", file=sys.stderr)

    return {"id": event_json['event']['id'], "action": "accept"}  # Accept


def process_kind_1(event_json):
    """
    Process events of kind 1 (note).
    """
    pubkey = event_json['event']['pubkey']
    content = event_json['event']['content']

    if not is_key_authorized(pubkey):
        print(f"Unauthorized pubkey for kind 1: {pubkey}", file=sys.stderr)
        return None  # Reject

    print(f"Processing kind 1 event, pubkey: {pubkey}, content: {content}", file=sys.stderr)
    return {"id": event_json['event']['id'], "action": "accept"}  # Accept


def process_kind_3(event_json):
    """
    Process events of kind 3 (contact list). Also create a trust rating event based on this.
    """
    pubkey = event_json['event']['pubkey']

    if not is_key_authorized(pubkey):
        print(f"Unauthorized pubkey for kind 3: {pubkey}", file=sys.stderr)
        return None  # Reject

    print(f"Processing kind 3 event, pubkey: {pubkey}", file=sys.stderr)

    # NIP-101 logic: Create a trust rating based on the contact list.
    # Assuming we want to give a positive rating to contacts.

    trust_rating_events = []
    for tag in event_json['event']['tags']:
        if tag and tag[0] == 'p':  # Check if the tag is a 'p' tag (contact)
            rated_pubkey = tag[1]
            # Assuming we want to add create a trust rating event for each contact
            trust_event = create_trust_rating_event(rater_pubkey=pubkey, rated_pubkey=rated_pubkey, rating=50) # Default trust rating of 50
            trust_rating_events.append(trust_event)

    result = {"id": event_json['event']['id'], "action": "accept"}  # Accept Original
    return (result, trust_rating_events)  # Added trust rating to the returns


def process_kind_7(event_json):
    """
    Process events of kind 7 (reaction).
    """
    pubkey = event_json['event']['pubkey']

    if not is_key_authorized(pubkey):
        print(f"Unauthorized pubkey for kind 7: {pubkey}", file=sys.stderr)
        return None  # Reject

    print(f"Processing kind 7 event, pubkey: {pubkey}", file=sys.stderr)
    return {"id": event_json['event']['id'], "action": "accept"}  # Accept


# Main loop to read events from stdin
for line in sys.stdin:
    line = line.strip()

    if not line:
        continue

    try:
        event_json = json.loads(line)

        if 'event' in event_json and 'kind' in event_json['event']:
            kind = event_json['event']['kind']

            if kind == 0:
                result = process_kind_0(event_json)
            elif kind == 1:
                result = process_kind_1(event_json)
            elif kind == 3:
                result = process_kind_3(event_json)
            elif kind == 7:
                result = process_kind_7(event_json)
            else:
                print(f"Processing kind {kind} event", file=sys.stderr)
                result = {"id": event_json['event']['id'], "action": "accept"} # Accept

            if result:
                if isinstance(result, tuple):  # Process the returning trust event
                    print(json.dumps(result[0]))
                    if result[1]:
                        for trust_event in result[1]:
                            print(json.dumps(trust_event)) # Adding this to show a good example of pushing it to the relays


                else:
                    print(json.dumps(result))

        else:
            print(f"Non-Nostr event input received: {line}", file=sys.stderr)

    except json.JSONDecodeError:
        print(f"Invalid JSON input received: {line}", file=sys.stderr)
    except Exception as e:
        print(f"An error occurred processing event: {e}", file=sys.stderr)
