# Nostr Crypto Tool

## NOT WORKING : Job in progress

A command-line tool for encrypting and decrypting files, optionally sending them as direct messages to Nostr relays, supporting NIP-04 and NIP-44.

## Overview

This Python script provides a command-line interface for encrypting and decrypting files using NIP-04 and NIP-44 compatible methods. It also supports sending the encrypted file as a direct message to Nostr relays using the `pynostr` library.

## Features

-   Encrypt files using the recipient's Nostr public key, compatible with NIP-04 and NIP-44.
-   Decrypt files using your Nostr private key, compatible with NIP-04 and NIP-44.
-   Send the encrypted file as a direct message to Nostr relays (requires `pynostr`).
-   Supports keys in Bech32 format.
-   Provides detailed logging for debugging.

## Dependencies

-   Python 3.6 or higher
-   `cryptography` library: For encryption and decryption.
-   `bech32` library: For decoding Bech32-encoded keys.
-   `pynostr` library: For sending direct messages to Nostr relays (optional).

Install the dependencies using pip:

```bash
pip install cryptography bech32
pip install pynostr  # Only if you plan to use the --send feature
```

## Installation

1.  Clone the repository or download the script.
2.  Install the dependencies.
3.  Ensure the script has execute permissions:

```bash
chmod +x nostr_crypto.py
```

## Usage

```
./nostr_crypto.py --help
```

The tool supports the following operations:

### Encryption

To encrypt a file, use the `--encrypt` option, along with:

-   `-p`: The recipient's Nostr public key (in npub1... format).
-   `-i`: The input file to encrypt.
-   `-o`: The output file to write the encrypted data.
-   `--nip`: (Optional) Specify either 4 (default) or 44 to select the encryption protocol.
-   `--send` and `--relays`: (Optional) To send the encrypted file as a direct message to Nostr relays (see Sending Encrypted Files below).

Example:

```bash
./nostr_crypto.py --encrypt -p npub1yourrecipientpubkey -i input.txt -o encrypted.enc
```

To use NIP-44:

```bash
./nostr_crypto.py --encrypt -p npub1yourrecipientpubkey -i input.txt -o encrypted.enc --nip 44
```

### Decryption

To decrypt a file, use the `--decrypt` option, along with:

-   `-k`: Your Nostr private key (in nsec1... format).
-   `-i`: The input file to decrypt.
-   `-o`: The output file to write the decrypted data.
-   `--nip`: (Optional) Specify either 4 (default) or 44 to select the encryption protocol. The same NIP version must be used to decrypt the file

Example:

```bash
./nostr_crypto.py --decrypt -k nsec1yourprivatekey -i encrypted.enc -o output.txt
```

To use NIP-44:

```bash
./nostr_crypto.py --decrypt -k nsec1yourprivatekey -i encrypted.enc -o output.txt --nip 44
```

### Sending Encrypted Files as Direct Messages

To send the encrypted file as a Nostr direct message, add the `--send` option and the `--relays` option:

```bash
./nostr_crypto.py --encrypt -p npub1yourrecipientpubkey -i input.txt -o encrypted.enc --send --relays wss://relay.damus.io,wss://relay.snort.social
```

You need to install the `pynostr` library to send the encrypted content, for now if fails, the tool will log as plain text.

**Important:** When using `--send`, you must also provide:

-   A valid Nostr private key with which to sign the event. The tool prompts the user for the private key.
-   A comma-separated list of valid relay URLs.

## NIP Compliance

This tool implements the following Nostr Improvement Proposals (NIPs):

-   **NIP-04: Encrypted Direct Message:** The tool implements NIP-04 encryption using AES-256-CBC. It generates a shared secret key using Elliptic-curve Diffie-Hellman (ECDH). The tool then encrypts the message with the key and IV. The receiver may then use their private key along with the sender's public key and IV to decrypt the message.
-   **NIP-44: ChaCha20-Poly1305 Encryption for Direct Messages:** The tool implements NIP-44 encryption using XChaCha20-Poly1305. It generates a shared secret key using Elliptic-curve Diffie-Hellman (ECDH). The tool then encrypts the message with the key and nonce. The receiver may then use their private key along with the sender's public key and nonce to decrypt the message.

## Security Considerations

-   **Private Key Security:** Treat your private key with extreme care. Do not share it and store it securely.
-   **Ephemeral Keys:** The tool uses ephemeral keys to derive each shared secret, providing forward secrecy.

## Thanks

This file uses libs, keys and tools by all the NOSTR community.
