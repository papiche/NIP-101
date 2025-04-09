#!/bin/bash
# IA_UPlanet.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$content" "$url"
# Analyse du message et de l'image Uplanet reçu
# Publie la réponse Ollama sur la GeoKey UPlanet 0.01 et 0.1
# et sur la clef NOSTR du Capitaine ?

MY_PATH="$(dirname "$0")"
MY_PATH="$( cd "$MY_PATH" && pwd )"

[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] && echo "ERROR. Astroport.ONE is missing !!" && exit 1
source ~/.zen/Astroport.ONE/tools/my.sh ## finding UPLANETNAME

# --- Help function ---
print_help() {
  echo "Usage: $(basename "$0") [--help] <pubkey> <latitude> <longitude> <content> <url>"
  echo ""
  echo "  <pubkey>     Public key (HEX format)."
  echo "  <event_id>   Event ID (HEX format)."
  echo "  <latitude>   Latitude."
  echo "  <longitude>  Longitude."
  echo "  <content>    Text content of the UPlanet message."
  echo "  <url>        URL of the image (e.g., IPFS URL)."
  echo ""
  echo "Options:"
  echo "  --help       Display this help message."
  echo ""
  echo "Description:"
  echo "  This script analyzes a UPlanet message and image, generates an Ollama"
  echo "  response, and prepares to publish it on UPlanet GeoKeys and a NOSTR key."
  echo ""
  echo "Example:"
  echo "  $(basename "$0") pubkey_hex 48.85 2.35 \"This is a message\" https://ipfs.g1sms.fr/ipfs/_image_hash"
}

# --- Handle --help option ---
if [[ "$1" == "--help" ]]; then
  print_help
  exit 0
fi

# Définition du répertoire de stockage des NOSTR Card
KEY_DIR="$HOME/.zen/game/nostr"

# Fonction pour vérifier si une clé est autorisée
is_key_authorized() {
    local pubkey="$1"
    local key_file

    while IFS= read -r -d $'\0' key_file; do
        if [[ "$pubkey" == "$(cat "$key_file")" ]]; then
            #~ echo "___FOUND $pubkey in $key_file" >&2
            return 0 # Clé autorisée
        fi
    done < <(find "$KEY_DIR" -type f -name "HEX" -print0)

    return 1 # Clé non autorisée
}

# --- Check for correct number of arguments ---
if [[ $# -lt 6 ]]; then
  echo "Error: Not enough arguments provided."
  print_help
  exit 1
fi

PUBKEY="$1"
EVENT="$2"
LAT="$3"
LON="$4"
MESSAGE="$5"
URL="$6"

echo "Received parameters:"
echo "  PUBKEY: $PUBKEY"
echo "  EVENT: $EVENT"
echo "  LAT: $LAT"
echo "  LON: $LON"
echo "  MESSAGE: $MESSAGE"
echo "  URL: $URL"
echo ""

# Vérifier si la clé publique est autorisée
if ! is_key_authorized "$PUBKEY"; then
    #~ echo "Unauthorized pubkey for kind $kind: $pubkey" >&2
    echo "This NOSTR CARD $PUBKEY is not registered on this Astroport"
    exit 0
fi

### Extract comment from message
## MESSAGE="this is X box or what\nhttps://ipfs.g1sms.fr/ipfs/QmWh7CtnViKS2cMuFWPLe7ywazrMp8VRg1BPvneBZ5UojX/captured-image.png"
extracted_text=$(echo "$MESSAGE" | sed 's/\n.*//')
echo "Extracted text from message: '$extracted_text'"

#######################################################################
echo "Looking at the image (using ollama llava)..."
DESC=$("$MY_PATH/describe_image.py" "$URL" --json | jq -r '.description')

if [[ -z "$DESC" ]]; then
  echo "Error: Failed to get image description from describe_image.py"
  exit 1
fi
echo "Image description received."

#######################################################################
echo "Generating Ollama answer..."
ANSWER=$(MY_PATH/question.py "Image : $DESC, COMMENT : $extracted_text. (answer in the same language as COMMENT is written)")

if [[ -z "$ANSWER" ]]; then
  echo "Error: Failed to get answer from question.py"
  exit 1
fi
echo "Ollama answer generated."
echo "ANSWER: $ANSWER"

#######################################################################
echo "Creating GEO Key NOSTR secret..."
UMAPNSEC=$($HOME/.zen/Astroport.ONE/tools/keygen -t nostr "${UPLANETNAME}${LAT}" "${UPLANETNAME}${LON}" -s)

if [[ -z "$UMAPNSEC" ]]; then
  echo "Error: Failed to generate NOSTR key."
  exit 1
fi
## Write nostr message
# nostr_send_event.py [-h] [--relay RELAY] [--timeout TIMEOUT] [--tags TAGS] private_key kind content
~/.zen/Astroport.ONE/tools/nostr_send_event.py \
  --relay wss://relay.copylaradio.com \
  "$UMAPNSEC" \
  "1" \
  "$ANSWER" \
  --tags "e:$EVENT" \
  --tags "p:$PUBKEY"
#######################################################################
echo ""
echo "--- Summary ---"
echo "PUBKEY: $PUBKEY"
echo "LAT: $LAT"
echo "LON: $LON"
echo "Extracted Text: $extracted_text"
echo "Image Description: $DESC"
echo "NOSTR Secret (UMAPNSEC): (Generated, not displayed for security)" # Not displaying secret
echo "Ollama Answer: $ANSWER"

echo ""
echo "Script execution completed."

exit 0


