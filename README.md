# NIP-101: UPlanet Hierarchical Geographic Keys and Tagging

`draft` `optional`

This NIP describes a method for generating Nostr keypairs deterministically based on geographic coordinates and a namespace, creating hierarchical "GeoKeys". It also specifies event tags used by the UPlanet application to associate notes with specific locations and grid levels.

## Abstract

UPlanet extends Nostr by enabling geographically localized communication. It achieves this through:

1.  **Hierarchical GeoKeys:** Nostr keypairs (`npub`/`nsec`) are derived from a combination of a fixed namespace string (e.g., "UPlanetV1") and geographic coordinates formatted to specific precision levels (e.g., 0.01°, 0.1°, 1.0°). This creates distinct identities for different geographic grid cells.
2.  **Geographic Tags:** Events published using these GeoKeys, or referencing a location, include specific tags (`latitude`, `longitude`) to indicate the precise point of interest.
3.  **Application Tag:** An `application` tag identifies events specifically intended for or generated by the UPlanet system.

This allows users and applications to subscribe to messages relevant to specific geographic areas by knowing the corresponding GeoKey `npub` or by filtering events based on location tags within a certain radius.

## Motivation

-   **Localized Feeds:** Create Nostr feeds relevant only to specific neighborhoods (UMAP), sectors (SECTOR), or regions (REGION).
-   **Geo-fencing:** Allow applications to filter or react to events occurring within defined geographic boundaries.
-   **Mapping Integration:** Provide a layer of Nostr events that can be easily displayed on maps.
-   **Decentralized Location-Based Services:** Enable discovery and interaction based on proximity without relying on centralized servers.
-   **Application-Specific Context:** The `application` tag allows UPlanet messages to be distinguished from general Nostr traffic.

## UPlanet's Unified Identity & Storage Model

This NIP describes how UPlanet integrates Nostr identities with IPFS storage, building upon the geographic key derivation.

### Authentication via NIP-42

UPassport services (`54321.py`) leverage Nostr for user authentication for privileged operations such as file uploads, deletions, and synchronization. This is achieved by:

1.  **Client-side Authentication Event:** When a user attempts a privileged action, their UPlanet web interface (or client) interacts with a Nostr extension ([NIP-07](https://github.com/nostr-protocol/nips/blob/master/07.md)) or directly with their `nsec` to sign an event of `kind: 22242` ([NIP-42: Authentication](https://github.com/nostr-protocol/nips/blob/master/42.md)). This event asserts the user's public key (`pubkey`) and typically includes a `relay` tag indicating the relay it was sent to, and a `challenge` tag.
2.  **Server-side Verification:** The UPlanet UPassport backend (`54321.py`) connects to a local Nostr relay (e.g., `ws://127.0.0.1:7777`). Upon receiving an authenticated request from a user (`npub`), the backend queries the relay for recent (e.g., last 24 hours) `kind: 22242` events authored by that `npub`. If a valid, recent event is found, the user's identity is authenticated. This mechanism ensures the user is indeed the owner of the `npub` without the server ever holding the private key.

### Twin-Key Mechanism and IPFS Drive Ownership

UPlanet's core innovation lies in its "Twin-Key" mechanism, which inextricably links a user's Nostr identity to their personal IPFS drive and other digital assets (G1, Bitcoin keys, as described in Specification 1: GeoKey Derivation).

-   **Deterministic Drive Association:** Each UPlanet user is associated with a unique IPFS drive located in their home directory (e.g., `~/.zen/game/nostr/<user_email>/APP`). The `manifest.json` file within this drive explicitly records the `owner_hex_pubkey`.
-   **Ownership Enforcement:**
    -   When a user attempts to modify their IPFS drive (uploading, deleting files), the UPlanet backend verifies that their authenticated Nostr `npub` (converted to `hex_pubkey`) matches the `owner_hex_pubkey` declared in the target drive's `manifest.json`.
    -   If the `npub` matches, the operation proceeds, and the IPFS drive is regenerated, yielding a new CID.
    -   If the `npub` does not match (i.e., it's a "foreign drive"), write operations are strictly disallowed. However, users can "sync" files from a foreign drive to their *own* authenticated drive, effectively copying public content.
-   **Structured IPFS Content:** Unlike general blob storage, UPlanet organizes files into a hierarchical structure within the IPFS drive (`Images/`, `Music/`, `Videos/`, `Documents/`), and generates a human-readable web interface (`_index.html`) for exploration. This provides a user-friendly "drive" experience rather than just raw blob access.

### Comparison to Generic Blob Storage (e.g., Blossom)

While sharing the fundamental use of Nostr for authentication, UPlanet differentiates itself from more generic Nostr-based blob storage specifications like [Blossom](https://github.com/hzrd149/blossom) (BUDs) in its scope and approach:

-   **Blossom:** Focuses on a low-level HTTP API for storing and retrieving arbitrary "blobs" addressed by SHA256 hashes on media servers. It is a fundamental building block for content distribution on Nostr.
-   **UPlanet:** Operates at a higher application layer. It is a structured "Personal IPFS Drive" system that *uses* IPFS for storage and *uses* Nostr for identity and authentication. Its "Twin-Key" mechanism (NIP-101 GeoKeys and other associated keys) provides a holistic, unified identity across geographic data, IPFS content, and potential other blockchain assets. It provides a complete user experience with a pre-built web interface and specific features like incremental updates and structured content organization.

### Dedicated Nostr Relay with Strfry and Custom Filters

UPlanet leverages a dedicated `strfry` Nostr relay, configured with custom write policies to integrate seamlessly with the UPlanet ecosystem, enabling authenticated actions and AI-driven responses.

#### 1. Strfry Compilation and Installation (`install_strfry.sh`)

The `install_strfry.sh` script automates the setup of the `strfry` Nostr relay:

*   **Dependency Installation:** It ensures all necessary system dependencies (e.g., `git`, `g++`, `make`, `libssl-dev`, `liblmdb-dev`) are installed on Debian/Ubuntu-based systems.
*   **Source Management:** The script clones the `strfry` repository from GitHub into `~/.zen/workspace/strfry` or updates it if already present.
*   **Compilation:** It compiles `strfry` from source, ensuring the latest features and optimizations.
*   **Installation:** The compiled `strfry` binary and its default `strfry.conf` are copied to `~/.zen/strfry/`, with the configuration adapted for broader network access (`bind = "0.0.0.0"`). This setup allows `strfry` to be a local relay dedicated to the UPlanet instance.

#### 2. Systemd Installation and Setup (`setup.sh`)

After `strfry` is compiled, the `setup.sh` script configures the `strfry` relay and prepares it for Systemd management:

*   **Configuration Generation:** It dynamically generates the `strfry.conf` file in `~/.zen/strfry/strfry.conf` based on variables from the UPlanet environment (e.g., `UPLANETG1PUB`, `IPFSNODEID`, `CAPTAINHEX`, `CAPTAINEMAIL`).
*   **Relay Information:** The `strfry.conf` includes NIP-11 metadata such as the relay's `name` (e.g., "♥️BOX `IPFSNODEID`"), `description` (highlighting its role in UPlanet), `pubkey` (the UPlanet Captain's public key for administration), and an `icon` URL.
*   **Write Policy Plugin:** Crucially, it sets the `writePolicy.plugin` parameter in `strfry.conf` to point to `"$HOME/.zen/workspace/NIP-101/relay.writePolicy.plugin/all_but_blacklist.sh"`. This delegates the event acceptance/rejection logic to a custom script, enabling UPlanet's specific filtering rules.

#### 3. Specific Filters and AI Integration

UPlanet's relay implements several layers of filtering to manage events and trigger AI responses:

*   **`relay.writePolicy.plugin/all_but_blacklist.sh` (Main Write Policy):**
    *   This is the primary script executed by `strfry` for every incoming event.
    *   Its core function is to implement a "whitelist by default, with blacklist exceptions" policy: it accepts all events unless the `pubkey` of the event's author is found in `~/.zen/strfry/blacklist.txt`.
    *   For `kind 1` (text) events, it dynamically calls `filter/1.sh` to apply more specific UPlanet-related logic.
    *   Events from blacklisted public keys are immediately rejected.

*   **`relay.writePolicy.plugin/filter/1.sh` (Kind 1 Event Filter):**
    *   This script specifically handles `kind 1` Nostr events, which are primarily text notes.
    *   **Visitor Management:** For `pubkey`s not registered as UPlanet "players," it implements a "Hello NOSTR visitor" mechanism. New visitors receive a warning message from the UPlanet Captain's key, explaining the system and limiting the number of messages they can send before being blacklisted. This encourages users to join the UPlanet Web of Trust.
    *   **Memory Management:** It uses `short_memory.py` to store conversation history for Nostr players, but only when messages contain the `#rec` tag. This allows users to control what gets stored in their AI memory, providing privacy and storage efficiency.
    *   **AI Triggering:** It acts as an orchestrator for the `UPlanet_IA_Responder.sh` script. If the `UPlanet_IA_Responder.sh` is already running, it queues incoming messages (especially those with `#BRO` or `#BOT` tags) to prevent overwhelming the AI. If the AI is not active, it directly invokes `UPlanet_IA_Responder.sh` with a timeout.

*   **`Astroport.ONE/IA/UPlanet_IA_Responder.sh` (AI Backend):**
    *   This is the core AI logic script, responsible for generating responses based on incoming `kind 1` messages, typically triggered by `filter/1.sh`.
    *   **Tag-Based Actions:** It parses specific hashtags within the message content to trigger various AI functionalities:
        *   `#search`: Integrates with a search engine (e.g., Perplexica) to retrieve information.
        *   `#image`: Commands an image generation AI (e.g., ComfyUI) to create images based on the prompt.
        *   `#video`: Utilizes text-to-video models (e.g., ComfyUI) to generate short video clips.
        *   `#music`: Triggers music generation.
        *   `#youtube`: Downloads YouTube videos (or extracts audio with `#mp3` tag) via `process_youtube.sh`.
        *   `#pierre` / `#amelie`: Converts text to speech using specific voice models (e.g., Orpheus TTS).
        *   `#mem`: Displays the current conversation history.
        *   `#rec`: Records the message in AI memory (both user and UMAP memory). This tag is required for any message to be stored in the conversation history.
        *   `#reset`: Clears the user's conversation memory.
    *   **Ollama Integration:** For general questions without specific tags, it uses Ollama with a context-aware `question.py` script to generate conversational AI responses, leveraging the stored memory (only messages tagged with `#rec` are available for context). The `question.py` script loads conversation history from either UMAP memory (based on latitude/longitude) or user memory (based on pubkey) and includes it as context in the AI prompt.
    *   **Response Publishing:** AI-generated responses are signed by the UPlanet Captain's key (or the `KNAME`'s key if specified and available) and published back to the Nostr relay as `kind 1` events, specifically tagging the original event and public key to maintain thread context (`e` and `p` tags).

This integrated system allows UPlanet to provide a dynamic, interactive experience where user actions and queries on Nostr can trigger complex AI operations and content generation, all while maintaining the integrity and ownership model of the IPFS drives.

### Memory Control Tags

UPlanet implements a privacy-conscious memory system where users have explicit control over what gets stored in their AI conversation history:

-   **`#rec` (Record):** This tag is **required** for any message to be stored in the AI memory. Messages without this tag are processed normally but not recorded for future context. This provides users with granular control over their privacy and storage usage.

-   **`#mem` (Memory):** Displays the current conversation history without recording the current message. This allows users to review their stored conversations without adding new entries.

-   **`#reset` (Reset):** Clears the user's conversation memory, providing a fresh start for AI interactions.

**Example Usage:**
```
# Message will be processed but NOT stored in memory
"Hello, how are you?"

# Message will be processed AND stored in memory for future context
"Hello, how are you? #rec"

# Message will display current memory without recording this message
"Show me our conversation history #mem"

# Message will clear all stored memory
"Clear our conversation #reset"
```

This approach ensures that users maintain full control over their digital footprint while still benefiting from contextual AI interactions when desired.

### Memory Usage in AI Responses

The `UPlanet_IA_Responder.sh` script utilizes the stored memory in several ways to provide contextual AI responses:

#### 1. Memory Display (`#mem` tag)
When a user includes the `#mem` tag, the script:
- Loads the user's conversation history from `~/.zen/strfry/uplanet_memory/pubkey/{pubkey}.json`
- Formats the last 30 messages with timestamps and cleaned content (removing #BOT/#BRO tags)
- Returns a human-readable conversation history without recording the current message

#### 2. Memory Reset (`#reset` tag)
When a user includes the `#reset` tag, the script:
- Deletes the user's memory file completely
- Returns a welcome message explaining available AI features
- Provides a fresh start for AI interactions

#### 3. Contextual AI Responses (Default behavior)
For general questions without specific tags, the script:
- Calls `question.py` with the user's `pubkey` parameter
- `question.py` loads conversation history from the user's memory file
- Constructs a context-aware prompt including previous messages
- Sends the enhanced prompt to Ollama for AI response generation
- Logs both the prompt and response to `~/.zen/tmp/IA.log`

#### 4. Memory Structure and Access
The memory system provides two types of context:

**User Memory (`pubkey/{pubkey}.json`):**
```json
{
  "pubkey": "user_public_key",
  "messages": [
    {
      "timestamp": "2024-01-01T12:00:00Z",
      "event_id": "event_hash",
      "latitude": "48.8534",
      "longitude": "-2.3412",
      "content": "User message content"
    }
  ]
}
```

**UMAP Memory (`{latitude}_{longitude}.json`):**
```json
{
  "latitude": "48.8534",
  "longitude": "-2.3412",
  "messages": [
    {
      "timestamp": "2024-01-01T12:00:00Z",
      "event_id": "event_hash",
      "pubkey": "user_public_key",
      "content": "Message content at this location"
    }
  ]
}
```

#### 5. Context Integration in AI Prompts
The `question.py` script enhances AI responses by:
- Loading relevant conversation history (up to 50 messages)
- Formatting previous messages as context
- Including location information when available
- Constructing a comprehensive prompt for Ollama
- Maintaining conversation continuity across sessions

This memory system enables the AI to provide personalized, context-aware responses while respecting user privacy through explicit consent via the `#rec` tag.

### Zen Economy and Reaction-Based Payments

UPlanet implements a unique economic system where social interactions (reactions/likes) trigger automatic micro-payments in the Ğ1 currency, creating a circular economy within the ecosystem.

#### 1. Reaction Processing (`filter/7.sh`)

The `filter/7.sh` script handles Nostr events of kind:7 (reactions/likes) and implements the Zen economy:

**Reaction Types:**
- **Positive Reactions:** `+`, `👍`, `❤️`, `♥️` (empty content is treated as positive)
- **Negative Reactions:** `-`, `👎`, `💔`
- **Custom Reactions:** Any other emoji or content

**Processing Flow:**
1. **Authorization Check:** Verifies the reaction sender is an authorized UPlanet player or in `amisOfAmis.txt`
2. **UPlanet Member Detection:** Uses `search_for_this_hex_in_uplanet.sh` to check if the reacted-to author is part of UPlanet
3. **Automatic Payment:** If both conditions are met, triggers a 0.1 Ğ1 payment from the reactor to the content creator

**Payment Implementation:**
```bash
# Extract G1PUBNOSTR for the reacted-to author
G1PUBNOSTR=$(~/.zen/Astroport.ONE/tools/search_for_this_hex_in_uplanet.sh $reacted_author_pubkey)

# Send 0.1 Ğ1 payment if both users are UPlanet members
if [[ -n "$G1PUBNOSTR" && -s "${PLAYER_DIR}/.secret.dunikey" ]]; then
    ~/.zen/Astroport.ONE/tools/PAYforSURE.sh "${PLAYER_DIR}/.secret.dunikey" "0.1" "$G1PUBNOSTR" "_like_${reacted_event_id}_from_${pubkey}"
fi
```

#### 2. Economic Ecosystem (`ZEN.ECONOMY.sh`)

The `ZEN.ECONOMY.sh` script manages the broader economic system:

**Actors and Balances:**
- **UPlanet:** Cooperative "central bank" managing the ecosystem
- **Node:** Physical server (PC Gamer or RPi5) hosting the relay
- **Captain:** Node manager and administrator

**Weekly Costs:**
- **NOSTR Card:** 1 Ẑen/week (users with Nostr cards)
- **ZEN Card:** 4 Ẑen/week (users with ZEN cards)
- **PAF (Participation Aux Frais):** 14 Ẑen/week (operational costs)

**Payment Logic:**
```bash
# Daily PAF calculation
DAILYPAF=$(echo "$PAF / 7" | bc -l)  # 2 Ẑen/day

# Captain pays PAF if sufficient balance, otherwise UPlanet pays
if [[ $CAPTAINZEN > $DAILYPAF ]]; then
    # Captain pays Node (economy positive)
    PAYforSURE.sh "$CAPTAIN_DUNIKEY" "$DAILYG1" "$NODEG1PUB" "PAF"
else
    # UPlanet pays Node (economy negative)
    PAYforSURE.sh "$UPLANET_DUNIKEY" "$DAILYG1" "$NODEG1PUB" "PAF"
fi
```

#### 3. Economic Incentives

**Content Creation Incentives:**
- **Micro-payments:** Each positive reaction generates 0.1 Ğ1 for content creators
- **Quality Content:** Encourages valuable contributions to the ecosystem
- **Community Building:** Rewards engagement and interaction

**Infrastructure Support:**
- **Node Sustainability:** PAF ensures relay servers remain operational
- **Captain Compensation:** Captains are incentivized to maintain quality infrastructure
- **UPlanet Stability:** Cooperative model distributes costs across the ecosystem

**Economic Flow:**
```
User A posts content → User B likes content → 0.1 Ğ1 payment to User A
                                                    ↓
Node provides relay service → Captain pays PAF → Node receives operational funding
                                                    ↓
UPlanet cooperative → Manages ecosystem → Distributes costs and benefits
```

This economic model creates a self-sustaining ecosystem where social interactions directly fund infrastructure and reward content creators, fostering a circular economy within the UPlanet network.

## Specification

### 1. GeoKey Derivation

A Nostr keypair (secp256k1) is deterministically derived from a seed string. The seed is constructed by concatenating:

1.  `UPLANETNAME`: A secret string identifying the application and used as ```~/.ipfs/swarm.key``` and creates the private IPFS swarm dedicated to UPlanet Application.
2.  `FORMATTED_LATITUDE`: The latitude, formatted as a string to a specific number of decimal places corresponding to the desired grid level.
3.  `FORMATTED_LONGITUDE`: The longitude, formatted as a string to the same number of decimal places as the latitude, corresponding to the grid level.

**Seed Format:** `"{UPLANETNAME}_{FORMATTED_LATITUDE}" "{UPLANETNAME}_{FORMATTED_LONGITUDE}"` used as [libsodium](https://doc.libsodium.org/libsodium_users) salt & pepper
**Key Generation:** Implement the deterministic key generation logic specified ([access to the `keygen` tool code](https://github.com/papiche/Astroport.ONE/blob/master/tools/keygen)).

**Grid Levels & Formatting:**

UPlanet defines the following initial grid levels:

-   **UMAP (Micro-Area):** 0.01° precision.
    -   Latitude/Longitude Formatting: String representation with exactly **two** decimal places (e.g., `sprintf("%.2f", coordinate)` in C, or equivalent). Coordinates should likely be truncated or rounded consistently *before* formatting.
    -   Example Seed: `"UPlanetV148.85-2.34"` (for Lat 48.853, Lon -2.341)
-   **SECTOR:** 0.1° precision.
    -   Latitude/Longitude Formatting: String representation with exactly **one** decimal place.
    -   Example Seed: `"UPlanetV148.8-2.3"` (for Lat 48.853, Lon -2.341)
-   **REGION:** 1.0° precision.
    -   Latitude/Longitude Formatting: String representation with exactly **zero** decimal places (integer part).
    -   Example Seed: `"UPlanetV148-2"` (for Lat 48.853, Lon -2.341)

**Key Generation Algorithm:**
The specific algorithm used by the `keygen` used in `IA_UPlanet.sh` is "Astroport" tool, providing deterministic method for deriving a secp256k1 keypair from a unique seed string (and other twin keys: IPFS, G1, Bitcoin). The chosen method IS consistent across the UPlanet ecosystem.

### 2. Event Tags

Events related to UPlanet locations SHOULD include the following tags:

-   **Latitude Tag:** `["latitude", "FLOAT_STRING"]`
    -   Value: The latitude as a string, optionnaly with higher precision (e.g., 6+ decimal places) than the GeoKey grid level. Example: `"48.8534"`
-   **Longitude Tag:** `["longitude", "FLOAT_STRING"]`
    -   Value: The longitude as a string, optionnaly with higher precision. Example: `"-2.3412"`
-   **Application Tag:** `["application", "UPlanet*"]`
    -   Value: Identifies the event as belonging to the UPlanet system. Allows differentiation (e.g., `UPlanet_AppName`).

**Note:** While GeoKeys provide identity for grid cells, the `latitude` and `longitude` tags specify the precise point of interest *within* or related to that cell. Events published *from* a UMAP GeoKey might contain tags pointing to a very specific coordinate within that 0.01°x0.01° cell.

### 3. Publishing

-   To post **as** a specific location grid cell (e.g., an automated bot reporting for a UMAP cell), derive the appropriate GeoKey `nsec` using the method in Specification 1 and publish a kind 1 event signed with it. The event SHOULD include the `latitude`, `longitude`, and `application` tags.
-   Regular users posting *about* ahve a default a location recorded with their personal key provided during Astroport registration. This location is used when geo data is found in event.

### 4. Subscribing and Filtering

Clients can discover UPlanet content in several ways:

-   **Subscribe by GeoKey:** Subscribe directly to the `npub` of the desired UMAP, SECTOR, or REGION GeoKey(s).
-   **Filter by Tags:** Subscribe to `kind: 1` events filtered by the `application` tag (`#a`: `["UPlanet"]`) and optionally filter client-side based on the `latitude` and `longitude` tags to find events within a specific geographic radius.
-   **Filter by Geo-Reference:** Subscribe to events that tag (`#p`) specific GeoKey `npub`s.

## Client Implementation Guide

-   **Posting:** When posting, determine the relevant coordinates. Include `latitude`, `longitude`, and `application` tags. Optionally derive and include `p` tags for relevant GeoKeys. If posting *as* a location, use the derived GeoKey `nsec` for signing.
-   **Receiving:** Filter incoming events based on subscribed GeoKeys or tags. Display location information, potentially on a map. Parse `latitude` and `longitude` tags for precise positioning.
-   **Coordinate Formatting:** Strictly adhere to the specified decimal places for each grid level when deriving keys. Use standard functions for formatting (e.g., `sprintf("%.2f", coord)`). Consistency in truncation or rounding is crucial.

## Use Cases Illustrated

-   **Local Chat:** Alice posts from her phone using her personal key but tags the UMAP GeoKey `npub` for her current block and includes `latitude`/`longitude` tags. Bob, subscribed to that UMAP GeoKey, sees her message.
-   **Automated Weather Alert:** An automated service derives the REGION GeoKey for Paris (`"UPlanetV1482"`), signs a weather alert using that key's `nsec`, and includes precise `latitude`/`longitude` tags for the storm's center. Users subscribed to the Paris REGION GeoKey receive the alert.
-   **AI Responder:** An AI service monitors messages tagged with `application: UPlanet`. When it sees a message from a user (`pubkey_A`) tagged with `latitude`/`longitude`, it derives the corresponding UMAP GeoKey (`pubkey_UMAP`), generates a response, signs it with the UMAP GeoKey's `nsec`, and includes `e` and `p` tags referencing the original event (`event_id`) and the user (`pubkey_A`).

## Security and Privacy Considerations

-   **Location Disclosure:** Publishing with precise `latitude`/`longitude` tags reveals location. Users must be aware of this. Using broader grid keys (SECTOR, REGION) for posting offers less precision.
-   **Tracking:** Consistent use of GeoKeys or tags could allow tracking of users' movements if they post frequently from different locations using their personal key with geo-tags.
-   **Namespace Security:** Control over the `UPLANETNAME` string is important. If compromised or changed, it could disrupt the system or lead to impersonation of locations.
-   **Key Management:** Managing potentially 654 Millions GeoKey `nsec`s, Astroport storage can choose the closest node.

## Compatibility

This NIP is compatible with existing Nostr concepts:
-   Uses standard kind 1 events.
-   Uses standard `e` and `p` tags for replies and user references (NIP-10).
-   Can be used alongside other NIPs defining content or tags.

## References

-   NIP-01: Basic protocol flow description
-   NIP-10: Conventions for use of `e` and `p` tags in text events
-   *(Implied)*: secp256k1, SHA256

## Documentation en Français

Pour une documentation complète en français incluant les services et avantages pour les locataires et sociétaires CopyLaRadio, consultez :

- **[Guide d'Entrée et d'Utilisation UPlanet](UPlanet/UPlanet_Enter_Help.md)** : Guide complet pour les nouveaux utilisateurs
- **[README.fr.md](README.fr.md)** : Version française de cette documentation technique
