#!/bin/bash

# Chemin du fichier de configuration
config_file="$HOME/.zen/strfry/strfry.conf"

# Vérifier si le fichier existe
if [ ! -f "$config_file" ]; then
    echo "Error: $config_file not found."
    exit 1
fi

# Vérifier si le chemin du plugin est fourni et exécutable
if [ -z "$1" ] || [ ! -x "$1" ]; then
    echo "Error: Provide a valid executable plugin path."
    echo "Usage: $0 <plugin_path>"
    exit 1
fi

plugin_path="$1"

# Modifier directement la ligne correspondant au plugin
sed -i "s|^\(\s*plugin\s*=\s*\).*|\1\"$plugin_path\"|" "$config_file"

echo "relay.writePolicy.plugin updated successfully to \"$plugin_path\"."

