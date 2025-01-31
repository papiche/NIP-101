#!/bin/bash
MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Vérifier si la clé publique est fournie
if [ $# -eq 0 ]; then
    echo "Usage: $0 <clé_publique_bech32> (<hex only>)"
    exit 1
fi

# Convertir la clé bech32 en format hexadécimal en utilisant nostr-commander-rs
echo "nostr-commander-rs --npub-to-hex "$1" -o json 2>/dev/null | jq -r .hex"
HEX_KEY=$(nostr-commander-rs --npub-to-hex "$1" -o json 2>/dev/null | jq -r .hex)

# Vérifier si la conversion a réussi
if [ -z "$HEX_KEY" ]; then
    echo "Erreur : Impossible de convertir la clé publique."
    exit 1
fi

## Simple npub1 to hex conversion
[[ ! -z "$2" ]] && echo "$HEX_KEY" && exit 0

echo "Clé hexadécimale : $HEX_KEY"
mkdir -p $MY_PATH/tmp/$HEX_KEY/

# Extraire les données avec strfry
echo "Extraction des données..."
cd $HOME/.zen/strfry/
./strfry scan "{\"authors\":[\"$HEX_KEY\"],\"kinds\":[0,1,3]}" > $MY_PATH/tmp/$HEX_KEY/data.json
cd -

## CONTROL data.json
[[ ! -s $MY_PATH/tmp/$HEX_KEY/data.json ]] \
    && echo "DATA EMPTY" \
    && rm -Rf $MY_PATH/tmp/$HEX_KEY \
    && exit 0

# Créer un fichier pour le graphe
echo "digraph G {" > $MY_PATH/tmp/$HEX_KEY/graph.dot

# Traiter les données et créer le graphe
echo "Création du graphe..."
jq -c '.[]' $MY_PATH/tmp/$HEX_KEY/data.json | while read -r event; do
    kind=$(echo $event | jq -r '.kind')
    case $kind in
        0)  # Métadonnées
            name=$(echo $event | jq -r '.content | fromjson | .name')
            echo "  \"$HEX_KEY\" [label=\"$name\"];" >> $MY_PATH/tmp/$HEX_KEY/graph.dot
            ;;
        3)  # Liste de contacts
            echo $event | jq -r '.tags[] | select(.[0] == "p") | .[1]' | while read -r contact; do
                echo "  \"$HEX_KEY\" -> \"$contact\";" >> $MY_PATH/tmp/$HEX_KEY/graph.dot
            done
            ;;
    esac
done

echo "}" >> $MY_PATH/tmp/$HEX_KEY/graph.dot

# Générer l'image du graphe
echo "Génération de l'image du graphe..."
dot -Tpng $MY_PATH/tmp/$HEX_KEY/graph.dot -o $MY_PATH/tmp/$HEX_KEY/graph.png

echo "Terminé. Le graphe a été sauvegardé dans $MY_PATH/tmp/$HEX_KEY/graph.png"

