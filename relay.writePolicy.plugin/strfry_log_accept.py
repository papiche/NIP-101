#!/usr/bin/env python3

import sys
import json

def main():
    """Lit les événements Nostr depuis stdin et les accepte systématiquement."""
    while True:
        try:
            # Lire une ligne JSON depuis stdin (représente un événement)
            line = sys.stdin.readline().strip()
            if not line:
                continue

            # Charger l'événement JSON
            event = json.loads(line)

            # Afficher les détails de l'événement
            print("🔹 Event received:")
            print(json.dumps(event, indent=2))

            # Répondre en acceptant l'événement
            response = {"id": event.get("event", {}).get("id"), "action": "accept"}
            print(json.dumps(response), flush=True)

        except Exception as e:
            print(f"❌ Error processing event: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
