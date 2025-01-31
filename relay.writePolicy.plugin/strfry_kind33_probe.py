#!/usr/bin/env python3
import sys
import json
import subprocess
import re
import os

# Définition du chemin du dossier de logs
LOG_DIR = os.path.expanduser("~/.zen/tmp/nostr")
LOG_FILE = os.path.join(LOG_DIR, "kind_33_events.log")

# Commandes externes et configuration
NOSTR_CMD = "nostr-commander-rs"
NSEC_FILE = "nostr_private_key.txt"
RELAY = "ws://127.0.0.1:7777"
IPFS_GATEWAY = "https://ipfs.copylaradi.com"  # URL du nœud IPFS local

# Création du dossier de logs s'il n'existe pas
os.makedirs(LOG_DIR, exist_ok=True)

def get_original_event(event_id):
    """Récupère un événement Nostr par son ID."""
    try:
        result = subprocess.run(
            [NOSTR_CMD, "--relay", RELAY, "--limit-number", "1", "--subscribe-channel", event_id],
            capture_output=True, text=True
        )
        events = json.loads(result.stdout.strip())
        if events:
            return events[0]  # Retourne l'événement correspondant
    except Exception as e:
        print(f"Error fetching event {event_id}: {e}", file=sys.stderr)
    return None


def download_and_add_to_ipfs(url):
    """Télécharge un fichier et l'ajoute à IPFS, puis retourne son CID."""
    filename = "downloaded_file"

    if "youtube.com" in url or "youtu.be" in url:
        subprocess.run(["youtube-dl", "-o", "downloaded_video.%(ext)s", url], check=True)
        filename = next(f for f in os.listdir() if f.startswith("downloaded_video."))
    else:
        subprocess.run(["wget", "-q", "-O", filename, url], check=True)

    result = subprocess.run(["ipfs", "add", "-Q", filename], capture_output=True, text=True)
    CID = result.stdout.strip()
    os.remove(filename)
    return f"{IPFS_GATEWAY}/ipfs/{CID}"

def replace_links_with_ipfs(content):
    """Remplace les liens vers images/vidéos par leurs CID IPFS."""
    urls = re.findall(r'(https?://[^ ]+\.(jpg|png|gif|mp4|webm|avi|mkv)|https?://www\.youtube\.com/watch\?v=[^ ]+)', content)
    modified_content = content

    for url, _ in urls:
        ipfs_url = download_and_add_to_ipfs(url)
        modified_content = modified_content.replace(url, ipfs_url)

    return modified_content

def publish_new_event(content):
    """Publie un nouvel événement Nostr."""
    try:
        nsec = open(NSEC_FILE).read().strip()
        subprocess.run([NOSTR_CMD, "--nsec", nsec, "--add-relay", RELAY, "--publish", content])
    except Exception as e:
        print(f"Error publishing event: {e}", file=sys.stderr)

def main():
    for line in sys.stdin:
        try:
            req = json.loads(line.strip())
            event_id = req["event"]["id"]
            kind = req["event"]["kind"]
            pubkey = req["event"]["pubkey"]
            tags = req["event"].get("tags", [])

            event_ref = next((tag[1] for tag in tags if tag[0] == "e"), None)

            if kind == 33:
                with open(LOG_FILE, "a") as f:
                    f.write(json.dumps(req) + "\n")

                if event_ref:
                    original_event = get_original_event(event_ref)

                    if original_event:
                        content = original_event.get("content", "")
                        modified_content = replace_links_with_ipfs(content)
                        publish_new_event(modified_content)

            response = {"id": event_id, "action": "accept"}
            print(json.dumps(response), flush=True)

        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
