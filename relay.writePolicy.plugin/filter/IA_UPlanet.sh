#!/bin/bash
# IA_UPlanet.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$content" "$url"
# Analyse du message et de l'image Uplanet reçu
# Publie la réponse Ollama sur la GeoKey UPlanet 0.01 et 0.1
# et sur la clef NOSTR du Capitaine ?

MY_PATH="$(dirname "$0")"
MY_PATH="$( cd "$MY_PATH" && pwd )"

[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] && echo "ERROR. Astroport.ONE is missing !!" && exit 1
source ~/.zen/Astroport.ONE/tools/my.sh ## finding UPLANETNAME

## Maintain Ollama : lsof -i :11434
$MY_PATH/ollama.me.sh

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
get_key_directory() {
    local pubkey="$1"
    local key_file
    local found_dir=""

    while IFS= read -r -d $'\0' key_file; do
        if [[ "$pubkey" == "$(cat "$key_file")" ]]; then
            # Extraire le dernier répertoire du chemin
            KNAME=$(basename "$(dirname "$key_file")")
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

## DEMO TIME
#~ # Vérifier si la clé publique est autorisée
#~ if ! get_key_directory "$PUBKEY"; then
    #~ echo "Unauthorized pubkey for kind $kind: $pubkey" >&2
    #~ echo "This NOSTR CARD $PUBKEY is not registered on this Astroport"
    #~ exit 0
#~ fi

echo "  KNAME: $KNAME"

## CHECK if $UMAPNPUB = $PUBKEY Then DO not reply
UMAPNPUB=$($HOME/.zen/Astroport.ONE/tools/keygen -t nostr "${UPLANETNAME}${LAT}" "${UPLANETNAME}${LON}")
UMAPHEX=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$UMAPNPUB")
[[ $PUBKEY == $UMAPHEX ]] && exit 0

##################################################################""
## Authorize UMAP to publish (nostr whitelist)
mkdir -p ~/.zen/game/nostr/UMAP_${LAT}_${LON}
if [ "$(cat ~/.zen/game/nostr/UMAP_${LAT}_${LON}/HEX 2>/dev/null)" != "$UMAPHEX" ]; then
  echo "$UMAPHEX" > ~/.zen/game/nostr/UMAP_${LAT}_${LON}/HEX
fi
##################################################################""

### Extract message
message_text=$(echo "$MESSAGE" | sed 's/\n.*//')
echo "Message text from message: '$message_text'"

#######################################################################
if [[ ! -z $URL ]]; then
    echo "Looking at the image (using ollama + llava)..."
    DESC="IMAGE : $("$MY_PATH/describe_image.py" "$URL" --json | jq -r '.description')"
fi
#~ if [[ -z "$DESC" ]]; then
  #~ echo "Error: Failed to get image description from describe_image.py"
  #~ exit 1
#~ fi
#~ echo "Image description received."

#######################################################################
echo "Generating Ollama answer..."
ANSWER=$($MY_PATH/question.py "$DESC + MESSAGE : $message_text (reformulate or reply if any question is asked, always using the same language as MESSAGE). Sign as 'ASTROBOT' :")

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
echo "Sending NOSTR message... copying to IPFS Vault ! DEBUG !! "
if [[ ! -z $KNAME ]]; then
    MOATS=$(date -u +"%Y%m%d%H%M%S%4N") && mkdir -p ~/.zen/game/nostr/$KNAME/MESSAGE
    echo "$ANSWER\nASTROBOT_$LAT_$LON\n$URL" > ~/.zen/game/nostr/$KNAME/MESSAGE/$MOATS.txt ## to IPFS (with NOSTR.refresh.sh)
    echo "LAT=$LAT; LON=$LON" > ~/.zen/game/nostr/$KNAME/UMAP
fi

#######################################################################
echo "Converting NSEC to HEX for nostpy-cli..."
NPRIV_HEX=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$UMAPNSEC")
if [[ -z "$NPRIV_HEX" ]]; then
  echo "Error: Failed to convert NSEC to HEX."
  exit 1
fi
echo "NSEC converted to HEX."

#######################################################################
echo "Sending Nostr Event (Kind 1) using nostpy-cli..."

nostpy-cli send_event \
  -privkey "$NPRIV_HEX" \
  -kind 1 \
  -content "$ANSWER\n\nUMAP_$LAT_$LON" \
  -tags "[['e', '$EVENT'], ['p', '$PUBKEY']]" \
  --relay "$myRELAY"

## UMAP follow PUBKEY
nostpy-cli send_event \
    -privkey "$NPRIV_HEX" \
    -kind 3 \
    -content "" \
    -tags "[['p', '$PUBKEY']]" \
    --relay "$myRELAY"

#######################################################################
echo ""
echo "--- Summary ---"
echo "PUBKEY: $PUBKEY"
echo "LAT: $LAT"
echo "LON: $LON"
echo "Message Text: $message_text"
echo "Image Description: $DESC"
echo "Ollama Answer: $ANSWER"

echo ""
echo "Script execution completed."

exit 0
