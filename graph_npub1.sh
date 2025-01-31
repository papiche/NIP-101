#!/bin/bash

# Vérifier si la clé publique est fournie
if [ $# -eq 0 ]; then
    echo "Usage: $0 <clé_publique_bech32> (<hex only>)"
    exit 1
fi

# Convertir la clé bech32 en format hexadécimal en utilisant nostr-commander-rs
HEX_KEY=$(nostr-commander-rs --npub-to-hex "$1" -o json 2>/dev/null | jq .hex)

# Vérifier si la conversion a réussi
if [ -z "$HEX_KEY" ]; then
    echo "Erreur : Impossible de convertir la clé publique."
    exit 1
fi

## Simple npub1 to hex conversion
[[ ! -z "$2" ]] && echo "$HEX_KEY" && exit 0

echo "Clé hexadécimale : $HEX_KEY"
mkdir -p tmp/$HEX_KEY/
/²
# Extraire les données avec strfry
echo "Extraction des données..."
strfry scan "{\"authors\":[\"$HEX_KEY\"],\"kinds\":[0,1,3]}" > tmp/$HEX_KEY/data.json

# Créer un fichier pour le graphe
echo "digraph G {" > tmp/$HEX_KEY/graph.dot

# Traiter les données et créer le graphe
echo "Création du graphe..."
jq -c '.[]' tmp/$HEX_KEY/data.json | while read -r event; do
    kind=$(echo $event | jq -r '.kind')
    case $kind in
        0)  # Métadonnées
            name=$(echo $event | jq -r '.content | fromjson | .name')
            echo "  \"$HEX_KEY\" [label=\"$name\"];" >> tmp/$HEX_KEY/graph.dot
            ;;
        3)  # Liste de contacts
            echo $event | jq -r '.tags[] | select(.[0] == "p") | .[1]' | while read -r contact; do
                echo "  \"$HEX_KEY\" -> \"$contact\";" >> tmp/$HEX_KEY/graph.dot
            done
            ;;
    esac
done

echo "}" >> tmp/$HEX_KEY/graph.dot

# Générer l'image du graphe
echo "Génération de l'image du graphe..."
dot -Tpng tmp/$HEX_KEY/graph.dot -o tmp/$HEX_KEY/graph.png

echo "Terminé. Le graphe a été sauvegardé dans tmp/$HEX_KEY/graph.png"

