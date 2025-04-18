#!/bin/bash
## Install workspace NIP-101 + strfry from ipfs + strfry.conf
#####################################################################
## CHECK DEPENDANCIES
[[ ! $(which ipfs) ]] && echo "MISSING IPFS - EXIT" && exit 1
[[ ! -d ~/.zen/Astroport.ONE ]] && echo "MISSING ~/.zen/Astroport.ONE - EXIT" && exit 1

####################### IPFS links
#~ strfry_amd64="/ipfs/QmPq6nbDDXP33n8XG7jJsc5j92xJ7tqsZSeVqkhTYt4V8D"
strfry_amd64="/ipfs/QmXLi3kMQSPc9JdxswBzFn2rVLjw7MArKcBN2HfRPTjDdW"
#~ strfry_arm64="/ipfs/Qmb2TNyXhdvaUxec69W7UPQ1yfBAmXpR6TyhXWopzwWi9X"
strfry_arm64="/ipfs/QmTzXxEaeHFkwrNmRAj88QCX1faWQenQnj2RZHFuQ8wMKx"

# Définition des chemins
WORKSPACE_DIR="$HOME/.zen/workspace"
STRFRY_INSTALL_DIR="$HOME/.zen/strfry"

[[ -x $STRFRY_INSTALL_DIR/strfry ]] && echo "strfry already installed - EXIT" && exit 1

# Création des répertoires nécessaires
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$STRFRY_INSTALL_DIR/strfry-db/"

## NIP-101 git clone (contains filter rules)
cd "$WORKSPACE_DIR"
git clone https://github.com/papiche/NIP-101
cd NIP-101
## Copy start script
cp start_strfry-relay.sh "$STRFRY_INSTALL_DIR/start.sh"

## Install binary from ipfs
architecture=$(uname -m)

echo "Install $architecture strfry binary from ipfs"

if [ "$architecture" == "x86_64" ]; then
    ipfs get -o $STRFRY_INSTALL_DIR/strfry $strfry_amd64
elif [ "$architecture" == "aarch64" ]; then
    ipfs get -o $STRFRY_INSTALL_DIR/strfry $strfry_arm64
fi

echo "Strfry est installé dans $STRFRY_INSTALL_DIR"

## SETUP strfry configuration (with name & NIP-101 filter rules)
$WORKSPACE_DIR/NIP-101/setup.sh

## Adding to systemd
$WORKSPACE_DIR/NIP-101/systemd.setup.sh

