#!/usr/bin/env python3
import argparse
import json
import asyncio
import websockets
import hashlib
import base64
import logging

# Configuration des logs
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

# Liste des types d'événements courants sur NOSTR
EVENT_TYPES = {
    0: "Mise à jour de profil",
    1: "Message texte",
    3: "Liste des contacts",
    4: "Message privé",
    7: "Reaction (like/dislike)",
    40: "Début d'une communauté",
    41: "Mise à jour de communauté",
    42: "Post dans une communauté"
}

def npub_to_hex(npub: str) -> str:
    """ Convertit une clé publique NOSTR (npub1...) en format hexadécimal. """
    try:
        if npub.startswith("npub1"):
            decoded = base64.b32decode(npub[5:] + "====", True)
            hex_key = decoded.hex()
            logging.info(f"Clé publique convertie en hex: {hex_key}")
            return hex_key
        raise ValueError("Format npub invalide")
    except Exception as e:
        logging.error(f"Erreur de conversion npub -> hex: {e}")
        raise

async def fetch_events(npub: str, relay_url: str):
    """ Récupère et affiche les messages NOSTR d'un utilisateur """
    try:
        public_key = npub_to_hex(npub)
        filters = {
            "kinds": list(EVENT_TYPES.keys()),
            "authors": [public_key],
            "limit": 50
        }
        subscription_id = hashlib.sha256(public_key.encode()).hexdigest()[:8]
        request = ["REQ", subscription_id, filters]

        logging.info(f"Connexion au relais: {relay_url}")
        async with websockets.connect(relay_url) as ws:
            logging.info(f"Envoi de la requête: {json.dumps(request)}")
            await ws.send(json.dumps(request))

            event_dict = {}

            while True:
                response = await ws.recv()
                logging.info(f"Réponse reçue: {response[:200]}...")  # Log limité à 200 caractères pour éviter le flood
                data = json.loads(response)

                if data[0] == "EVENT":
                    event = data[2]
                    event_type = EVENT_TYPES.get(event["kind"], f"Type inconnu ({event['kind']})")
                    
                    if event_type not in event_dict:
                        event_dict[event_type] = []
                    event_dict[event_type].append(event["content"])

                    logging.info(f"Événement reçu: {event_type} -> {event['content'][:100]}...")  # Tronque le contenu

                elif data[0] == "EOSE":  # Fin de l'envoi des événements
                    logging.info("Fin de l'envoi des événements (EOSE)")
                    break

        if event_dict:
            logging.info("Événements classés par type:")
            print(json.dumps(event_dict, indent=4, ensure_ascii=False))
        else:
            logging.warning("Aucun événement trouvé pour cet utilisateur.")

    except Exception as e:
        logging.error(f"Erreur lors de la récupération des événements: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Lister les messages NOSTR d'un utilisateur et les classer par type.")
    parser.add_argument("npub", help="Clé publique NOSTR (npub1...)")
    parser.add_argument("--relay", default="wss://relay.copylaradio.com", help="URL du relais NOSTR (par défaut : wss://relay.copylaradio.com)")

    args = parser.parse_args()

    asyncio.run(fetch_events(args.npub, args.relay))


