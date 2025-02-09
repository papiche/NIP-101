#!/usr/bin/env python3

import argparse
import base64
import json
import os
import sys
import bech32

from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

from pynostr.key import PrivateKey
from pynostr.event import Event
from pynostr.relay_manager import RelayManager
import time
import hashlib

# ---- Conversion des clés Nostr (npub/nsec) ----
def decode_nostr_key(nkey):
    """ Convertit une clé Nostr (npub/nsec) en bytes utilisables """
    hrp, data = bech32.bech32_decode(nkey)
    if data is None:
        raise ValueError("Clé Nostr invalide ou mal formée")

    key_bytes = bytes(bech32.convertbits(data, 5, 8, False))  # Convertit en octets
    if hrp == "npub":
        return key_bytes  # Clé publique (32 octets)
    elif hrp == "nsec":
        return hashlib.sha256(key_bytes).digest()  # Transforme en 32 octets pour AES
    else:
        raise ValueError("Format de clé Nostr inconnu")


# ---- Chiffrement AES-256-CBC (NIP-04) ----
def encrypt_nip04(data, pubkey):
    print(f"🔑 Pubkey utilisé pour la dérivation : {pubkey}")

    # Utilisation de HKDF pour dériver une clé à partir du pubkey
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=pubkey,  # Pubkey est déjà un bytes, pas besoin de l'encoder
        backend=default_backend()
    )
    key = hkdf.derive(b"")  # La clé dérivée de la pubkey
    iv = os.urandom(16)

    print(f"🔑 Clé dérivée pour le chiffrement : {key.hex()}")
    print(f"🔹 IV généré pour le chiffrement : {iv.hex()}")

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()

    # Padding standard avec PKCS7
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(data.encode()) + padder.finalize()  # Utilisation directe de data (en bytes)

    print(f"🔹 Données après padding : {padded_data.hex()}")

    encrypted_data = encryptor.update(padded_data) + encryptor.finalize()

    # Encrypted data en base64
    encrypted_b64 = base64.b64encode(iv + encrypted_data).decode()

    print(f"✅ Données chiffrées (base64) : {encrypted_b64}")

    return encrypted_b64


# ---- Déchiffrement AES-256-CBC (NIP-04) ----
def decrypt_nip04(encrypted_b64, privkey):
    print(f"🔑 Privkey utilisé pour la dérivation : {privkey}")

    # Utilisation de HKDF pour dériver une clé à partir du privkey
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=privkey.encode(),  # Assurez-vous que privkey est encodé en bytes
        backend=default_backend()
    )
    key = hkdf.derive(b"")  # La clé dérivée du privkey
    encrypted_data = base64.b64decode(encrypted_b64)

    iv = encrypted_data[:16]  # Extraire l'IV
    encrypted_text = encrypted_data[16:]  # Le reste est le texte chiffré

    print(f"🔹 Données chiffrées (hex) : {encrypted_data.hex()}")
    print(f"🔹 IV utilisé pour le déchiffrement : {iv.hex()}")

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()

    # Déchiffrement avec padding
    decrypted_padded = decryptor.update(encrypted_text) + decryptor.finalize()

    print(f"🔹 Données après déchiffrement (avec padding) : {decrypted_padded.hex()}")

    # Tentative de supprimer le padding, avec une gestion de l'erreur de padding
    try:
        unpadder = padding.PKCS7(128).unpadder()
        decrypted_data = unpadder.update(decrypted_padded) + unpadder.finalize()
        print(f"🔹 Données après dépadding : {decrypted_data.hex()}")
    except ValueError as e:
        print(f"Erreur de padding : {e}")
        # En cas d'erreur de padding, tentons de nettoyer les données
        decrypted_data = None

    if decrypted_data is None:
        print("Les données ne peuvent pas être décryptées correctement.")
        return None

    return decrypted_data.decode()



# ---- Chiffrement XChaCha20-Poly1305 (NIP-44) ----
def encrypt_nip44(data, pubkey):
    from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

    key = os.urandom(32)
    nonce = os.urandom(24)
    cipher = ChaCha20Poly1305(key)
    encrypted_data = cipher.encrypt(nonce, data, None)

    return base64.b64encode(nonce + encrypted_data).decode()

# ---- Déchiffrement XChaCha20-Poly1305 (NIP-44) ----
def decrypt_nip44(encrypted_b64, privkey):
    from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

    encrypted_data = base64.b64decode(encrypted_b64)
    nonce = encrypted_data[:24]
    encrypted_text = encrypted_data[24:]

    cipher = ChaCha20Poly1305(privkey)
    return cipher.decrypt(nonce, encrypted_text, None)

# ---- Envoi sur Nostr ----
def send_encrypted_file(relay_url, privkey, pubkey, encrypted_file):
    relay_manager = RelayManager()
    relay_manager.add_relay(relay_url)
    relay_manager.open_connections()

    with open(encrypted_file, "r") as f:
        encrypted_data = f.read()

    event = Event(content=encrypted_data)
    event.sign(privkey)

    relay_manager.publish_event(event)
    time.sleep(1)
    relay_manager.close_connections()

    print("✅ Fichier chiffré envoyé sur Nostr.")

# ---- Lecture des messages sur Nostr ----
def receive_encrypted_message(relay_url, privkey):
    relay_manager = RelayManager()
    relay_manager.add_relay(relay_url)
    relay_manager.open_connections()

    time.sleep(1)
    messages = relay_manager.get_events()
    relay_manager.close_connections()

    for msg in messages:
        print("🔐 Message reçu :", msg.content)

# ---- Fonction principale ----
def main():
    parser = argparse.ArgumentParser(description="Outil de chiffrement Nostr (NIP-04 et NIP-44)")
    parser.add_argument("--encrypt", action="store_true", help="Chiffrer un fichier")
    parser.add_argument("--decrypt", action="store_true", help="Déchiffrer un fichier")
    parser.add_argument("--send", action="store_true", help="Envoyer un fichier chiffré sur Nostr")
    parser.add_argument("--receive", action="store_true", help="Recevoir un message chiffré de Nostr")
    parser.add_argument("-p", "--pubkey", type=str, help="Clé publique du destinataire (npub1...)")
    parser.add_argument("-k", "--privkey", type=str, help="Clé privée (nsec1...)")
    parser.add_argument("-i", "--input", type=str, help="Fichier d'entrée")
    parser.add_argument("-o", "--output", type=str, help="Fichier de sortie")
    parser.add_argument("-r", "--relay", type=str, help="URL du relais Nostr")
    parser.add_argument("-m", "--method", choices=["nip04", "nip44"], default="nip04", help="Méthode de chiffrement")

    args = parser.parse_args()

    if args.encrypt:
        if not args.pubkey or not args.input or not args.output:
            parser.error("--encrypt nécessite -p (pubkey), -i (input) et -o (output)")

        with open(args.input, "rb") as f:
            plaintext = f.read()

        pubkey_bytes = decode_nostr_key(args.pubkey)

        if args.method == "nip04":
            encrypted_data = encrypt_nip04(plaintext, pubkey_bytes)
        else:
            encrypted_data = encrypt_nip44(plaintext, pubkey_bytes)

        with open(args.output, "w") as f:
            f.write(encrypted_data)

        print(f"✅ Fichier chiffré avec {args.method} et sauvegardé dans {args.output}")

    elif args.decrypt:
        if not args.privkey or not args.input or not args.output:
            parser.error("--decrypt nécessite -k (privkey), -i (input) et -o (output)")

        with open(args.input, "r") as f:
            encrypted_data = f.read()

        privkey_bytes = decode_nostr_key(args.privkey)
        print(f"🔑 Clé privée dérivée (32 bytes) : {privkey_bytes.hex()}")

        if args.method == "nip04":
            decrypted_data = decrypt_nip04(encrypted_data, privkey_bytes)
        else:
            decrypted_data = decrypt_nip44(encrypted_data, privkey_bytes)

        with open(args.output, "wb") as f:
            f.write(decrypted_data)

        print(f"✅ Fichier déchiffré et sauvegardé dans {args.output}")

    elif args.send:
        send_encrypted_file(args.relay, args.privkey, args.pubkey, args.input)

    elif args.receive:
        receive_encrypted_message(args.relay, args.privkey)

if __name__ == "__main__":
    main()
