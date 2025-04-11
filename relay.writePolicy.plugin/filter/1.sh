#!/bin/bash
# filter/1.sh
MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Extraire les informations nécessaires de l'événement JSON passé en argument
event_json="$1"
#~ echo "$event_json" >> "$HOME/.zen/strfry/1_messages.log" ## DEBUG

application=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "application") | .[1]')
url=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "url") | .[1]')
latitude=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "latitude") | .[1]')
longitude=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "longitude") | .[1]')
content=$(echo "$event_json" | jq -r '.event.content')
event_id=$(echo "$event_json" | jq -r '.event.id')
pubkey=$(echo "$event_json" | jq -r '.event.pubkey')
created_at=$(echo "$event_json" | jq -r '.event.created_at')
kind=$(echo "$event_json" | jq -r '.event.kind')
tags=$(echo "$event_json" | jq -r '.event.tags')


### PLAYER can add their own script in https://github.com/papiche/NIP-101/tree/main/relay.writePolicy.plugin/filter
# Exécuter le filtre correspondant à pubkey (si le script existe)
if [[ -x $MY_PATH/$pubkey.sh ]]; then
    $MY_PATH/$pubkey.sh "$event_json"
    if [[ $? -ne 0 ]]; then
        # Si le filtre renvoie un code d'erreur, rejeter l'événement
        #~ echo "Rejecting event of type: $event_type" >&2
        echo "{\"id\": \"$event_id\", \"action\": \"reject\"}"
        return
    fi
fi

# Vérifier si l'application est "UPlanet"
if [[ "$application" == "UPlanet" ]]; then
    if [[ -n "$latitude" && -n "$longitude" ]]; then
        # Activation du script AI
        $MY_PATH/IA_UPlanet.sh "$pubkey" "$event_id" "$latitude" "$longitude" "$content" "$url" &
        echo "$(date '+%Y-%m-%d %H:%M:%S') - UPlanet Message - Lat: $latitude, Lon: $longitude, Content: $content" >> "$HOME/.zen/strfry/uplanet_messages.log"
        exit 0 # Indiquer que le filtre UPlanet a réussi (clé générée)
    else
        echo "Latitude ou longitude manquante pour UPlanet" >&2
        exit 1 # Latitude ou longitude manquante
    fi
else

    #~ echo "Creating UPlanet NOSTR response..." sub process
    (
    UMAPNSEC=$($HOME/.zen/Astroport.ONE/tools/keygen -t nostr "${UPLANETNAME}" "${UPLANETNAME}" -s)
    NPRIV_HEX=$($HOME/.zen/Astroport.ONE/tools/nostr2hex.py "$UMAPNSEC")
    echo "Notice: Astroport Relay Usage"

    RESPN="We noticed you're using our Astroport Relay without being registered in our Web of Trust.

Interested in joining our self-hosting community? Register at https://qo-op.com

/UPlanet${UPLANETG1PUB:0:8}"

    nostpy-cli send_event \
      -privkey "$NPRIV_HEX" \
      -kind 1 \
      -content "$RESPN" \
      -tags "[['e', '$event_id'], ['p', '$pubkey']]" \
      --relay "$myRELAY"
    ) &

    exit 0
fi
