#!/usr/bin/env python3

import argparse
import base64
import json
import logging
import os
import hashlib
import binascii
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from bech32 import bech32_decode, convertbits

try:
    from pynostr.event import Event
    from pynostr.key import PrivateKey
    from pynostr.relay_manager import RelayManager

    PYNOSTR_AVAILABLE = True
except ImportError:
    PYNOSTR_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def decode_bech32(bech32_str):
    """Decode a Bech32 string and return the data part as a hexadecimal string."""
    hrp, data = bech32_decode(bech32_str)
    if data is None:
        raise ValueError("Invalid Bech32 string")
    # Convert data (list of 5-bit integers) to bytes
    decoded = convertbits(data, 5, 8, False)
    return bytes(decoded)


def pubkey_to_hex(pubkey):
    """Convert the pubkey to hex using x25519 and back"""
    decoded = decode_bech32(pubkey)
    return binascii.hexlify(decoded[1:]).decode('utf-8')


def encrypt_file_nip04(public_key, input_file, output_file):
    with open(input_file, 'rb') as f:
        plaintext = f.read()

    # Convert Bech32 public key to hex
    pubkey_hex = pubkey_to_hex(public_key)

    # NIP-04 uses X25519
    ephemeral_private_key = x25519.X25519PrivateKey.generate()
    ephemeral_public_key = ephemeral_private_key.public_key()
    pubkey_point = x25519.X25519PublicKey.from_public_bytes(bytes.fromhex(pubkey_hex))

    # Perform key exchange
    shared_key = ephemeral_private_key.exchange(pubkey_point)
    # Use SHA256 for key derivation
    derived_key = hashes.Hash(hashes.SHA256(), backend=default_backend())
    derived_key.update(shared_key)
    key = derived_key.finalize()

    iv = os.urandom(16)
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    ciphertext = encryptor.update(plaintext) + encryptor.finalize()
    encrypted_data = {
        'ephemeral_pubkey': base64.b64encode(ephemeral_public_key.public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw
        )).decode(),
        'ciphertext': base64.b64encode(ciphertext).decode(),
        'iv': base64.b64encode(iv).decode()
    }
    with open(output_file, 'w') as f:
        json.dump(encrypted_data, f)

    logger.info(f"File encrypted using NIP-04 and saved to {output_file}")


def encrypt_file_nip44(public_key, input_file, output_file):
    with open(input_file, 'rb') as f:
        plaintext = f.read()

    # Convert Bech32 public key to hex
    pubkey_hex = pubkey_to_hex(public_key)

    # NIP-44 uses X25519
    ephemeral_private_key = x25519.X25519PrivateKey.generate()
    ephemeral_public_key = ephemeral_private_key.public_key()
    pubkey_point = x25519.X25519PublicKey.from_public_bytes(bytes.fromhex(pubkey_hex))

    # Perform key exchange
    shared_key = ephemeral_private_key.exchange(pubkey_point)

    # HKDF algorithm and the NIP-44 identifier b"nip44-v2-encryption"
    derived_key = hashes.HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=b"nip44-v2-encryption",
        backend=default_backend()
    ).derive(shared_key)

    nonce = os.urandom(12)
    chacha = ChaCha20Poly1305(derived_key)
    ciphertext = chacha.encrypt(nonce, plaintext, None)

    encrypted_data = {
        'ephemeral_pubkey': base64.b64encode(ephemeral_public_key.public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw
        )).decode(),
        'ciphertext': base64.b64encode(ciphertext).decode(),
        'nonce': base64.b64encode(nonce).decode()
    }

    with open(output_file, 'w') as f:
        json.dump(encrypted_data, f)

    logger.info(f"File encrypted using NIP-44 and saved to {output_file}")

def decrypt_file_nip04(private_key, input_file, output_file):
    with open(input_file, 'r') as f:
        encrypted_data = json.load(f)

    ephemeral_pubkey_bytes = base64.b64decode(encrypted_data['ephemeral_pubkey'])
    ciphertext = base64.b64decode(encrypted_data['ciphertext'])
    iv = base64.b64decode(encrypted_data['iv'])

    # Decode private key
    private_key_hex = pubkey_to_hex(private_key)

    # Create the private key object to derive
    secp_privkey = x25519.X25519PrivateKey.from_private_bytes(bytes.fromhex(private_key_hex))

    #Get public key from the string
    ephemeral_pubkey = x25519.X25519PublicKey.from_public_bytes(ephemeral_pubkey_bytes)

    # Perform key exchange
    shared_key = secp_privkey.exchange(ephemeral_pubkey)
    # Use SHA256 for key derivation
    derived_key = hashes.Hash(hashes.SHA256(), backend=default_backend())
    derived_key.update(shared_key)
    key = derived_key.finalize()

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()
    plaintext = decryptor.update(ciphertext) + decryptor.finalize()
    with open(output_file, 'wb') as f:
        f.write(plaintext)

    logger.info(f"File decrypted using NIP-04 and saved to {output_file}")

def decrypt_file_nip44(private_key, input_file, output_file):
    with open(input_file, 'r') as f:
        encrypted_data = json.load(f)

    ephemeral_pubkey = base64.b64decode(encrypted_data['ephemeral_pubkey'])
    ciphertext = base64.b64decode(encrypted_data['ciphertext'])
    nonce = base64.b64decode(encrypted_data['nonce'])

    # Decode private key
    private_key_hex = pubkey_to_hex(private_key)

    # Create the private key object to derive
    secp_privkey = x25519.X25519PrivateKey.from_private_bytes(bytes.fromhex(private_key_hex))
    ephemeral_pubkey_obj = x25519.X25519PublicKey.from_public_bytes(ephemeral_pubkey)
    # Perform key exchange
    shared_key = secp_privkey.exchange(ephemeral_pubkey_obj)

    # HKDF algorithm and the NIP-44 identifier b"nip44-v2-encryption"
    derived_key = hashes.HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=b"nip44-v2-encryption",
        backend=default_backend()
    ).derive(shared_key)

    chacha = ChaCha20Poly1305(derived_key)
    plaintext = chacha.decrypt(nonce, ciphertext, None)

    with open(output_file, 'wb') as f:
        f.write(plaintext)

    logger.info(f"File decrypted using NIP-44 and saved to {output_file}")

def send_encrypted_file(private_key, public_key, input_file, relays):
    if not PYNOSTR_AVAILABLE:
        raise ImportError(
            "pynostr library is not installed. Please install it to use the send feature.")

    with open(input_file, 'r') as f:
        encrypted_data = json.load(f)

    content = json.dumps(encrypted_data)
    #The content must now be the message for direct sending from nostr direct message
    privkey = PrivateKey(bytes_to_hex(decode_bech32(private_key)[1:]))
    #Use helper to extract pubkey
    pubkey = pubkey_to_hex(public_key)

    event = Event(kind=4, content=content, tags=[["p", pubkey]])
    privkey.sign_event(event)

    relay_manager = RelayManager()
    for relay in relays:
        relay_manager.add_relay(relay)
    relay_manager.open_connections()
    relay_manager.publish_event(event)
    relay_manager.close_connections()
    logger.info(f"Encrypted file sent to relays: {', '.join(relays)}")

def bytes_to_hex(b):
    return b.hex()

def main():
    parser = argparse.ArgumentParser(description="Nostr Crypto Tool")
    parser.add_argument("--encrypt", action="store_true", help="Encrypt a file")
    parser.add_argument("--decrypt", action="store_true", help="Decrypt a file")
    parser.add_argument("-p", "--public-key", help="Recipient's public key (for encryption)")
    parser.add_argument("-k", "--private-key", help="Your private key (for decryption)")
    parser.add_argument("-i", "--input", required=True, help="Input file")
    parser.add_argument("-o", "--output", required=True, help="Output file")
    parser.add_argument("--send", action="store_true", help="Send encrypted file as a direct message")
    parser.add_argument("--relays", help="Comma-separated list of relay URLs")
    parser.add_argument("--nip", choices=['4', '44'], default='4', help="Choose NIP version for encryption/decryption (default: 4)")

    args = parser.parse_args()

    if args.encrypt:
        if not args.public_key:
            parser.error("Public key is required for encryption")
        if args.nip == '4':
            encrypt_file_nip04(args.public_key, args.input, args.output)
        else:
            encrypt_file_nip44(args.public_key, args.input, args.output)
        if args.send:
            if not args.private_key:
                parser.error("Private key is required for sending")
            if not args.relays:
                parser.error("Relay URLs are required for sending")
            send_encrypted_file(args.private_key, args.public_key, args.output, args.relays.split(','))
    elif args.decrypt:
        if not args.private_key:
            parser.error("Private key is required for decryption")
        if args.nip == '4':
            decrypt_file_nip04(args.private_key, args.input, args.output)
        else:
            decrypt_file_nip44(args.private_key, args.input, args.output)
    else:
        parser.error("Either --encrypt or --decrypt must be specified")

if __name__ == "__main__":
    main()
