#!/bin/bash
## strfry + strfry.conf

## IPFS BINARY SOURCE
ipfs_strfry() {
    architecture=$(uname -m)
    echo "strfry binary ipfs links"
    strfry_amd64="/ipfs/QmPq6nbDDXP33n8XG7jJsc5j92xJ7tqsZSeVqkhTYt4V8D"
    strfry_arm64="/ipfs/Qmb2TNyXhdvaUxec69W7UPQ1yfBAmXpR6TyhXWopzwWi9X"
    if [ "$architecture" == "x86_64" ]; then
        echo "ipfs get -o $STRFRY_INSTALL_DIR/strfry $strfry_amd64"
    elif [ "$architecture" == "aarch64" ]; then
        echo "ipfs get -o $STRFRY_INSTALL_DIR/strfry $strfry_arm64"
    fi
}

# Définition des chemins
WORKSPACE_DIR="$HOME/.zen/workspace"
STRFRY_SRC_DIR="$WORKSPACE_DIR/strfry"
STRFRY_INSTALL_DIR="$HOME/.zen/strfry"

# Création des répertoires nécessaires
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$STRFRY_INSTALL_DIR/strfry-db/"

# Fonction pour installer les dépendances (basée sur Ubuntu/Debian)
install_dependencies() {
    for i in git g++ make libssl-dev zlib1g-dev liblmdb-dev libflatbuffers-dev libsecp256k1-dev libzstd-dev; do
    if [ $(dpkg-query -W -f='${Status}' $i 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
        echo ">>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Installation $i <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
        sudo apt install -y $i
        [[ $? != 0 ]] && echo "INSTALL $i FAILED." && echo "INSTALL $i FAILED." >> /tmp/install.errors.log && continue
    fi
    done
}

# Fonction pour cloner ou mettre à jour le dépôt strfry
clone_or_update_repo() {
    if [ -d "$STRFRY_SRC_DIR" ]; then
        echo "Mise à jour du dépôt strfry..."
        cd "$STRFRY_SRC_DIR"
        git pull
    else
        echo "Clonage du dépôt strfry..."
        git clone https://github.com/hoytech/strfry "$STRFRY_SRC_DIR"
        cd "$STRFRY_SRC_DIR"
    fi
}

# Fonction pour compiler strfry
compile_strfry() {
    echo "Compiling strfry..."
    git submodule update --init
    make setup-golpe
    make -j3
}

# Fonction pour compiler strfry
update_strfry() {
    echo "Updating strfry..."
    make update-submodules
    make -j3
}

# Fonction pour installer ou mettre à jour strfry
install_strfry() {
    if [[ -s "$STRFRY_SRC_DIR/strfry" ]]; then
        if ! cmp -s "$STRFRY_SRC_DIR/strfry" "$STRFRY_INSTALL_DIR/strfry"; then
            echo "Installation strfry..."
            cp -f "$STRFRY_SRC_DIR/strfry" "$STRFRY_INSTALL_DIR/"
            chmod +x "$STRFRY_INSTALL_DIR/strfry"
        else
            echo "strfry binary unchanged..."
        fi
    fi
    # Copie du fichier de configuration s'il n'existe pas déjà
    if [ ! -f "$STRFRY_INSTALL_DIR/strfry.conf" ]; then
        echo "$STRFRY_INSTALL_DIR/strfry.conf"
        cat "$STRFRY_SRC_DIR/strfry.conf" | sed "s~127.0.0.1~0.0.0.0~g" > "$STRFRY_INSTALL_DIR/strfry.conf"
    fi
    ## COPY (RE)START SCRIPT
    cp start_strfry-relay.sh "$STRFRY_INSTALL_DIR/start.sh"
    mkdir -p "$STRFRY_INSTALL_DIR/strfry-db/" # strfry-db/
}

########################################
## INSTALL NOSTR RELAY

ipfs_strfry # show ipfs get link

if [[ ! -s "$STRFRY_INSTALL_DIR/strfry" ]]; then
    install_dependencies
    clone_or_update_repo
    compile_strfry
    install_strfry
else
    echo "Would You like to update strfry ? ENTER / Ctrl+C : CANCEL"
    read
    clone_or_update_repo
    update_strfry
    install_strfry
fi

echo "Installation/mise à jour de strfry terminée."
echo "Strfry est installé dans $STRFRY_INSTALL_DIR"
echo "TO FINISH INSTALL :"
echo "1) setup : $WORKSPACE_DIR/NIP-101/setup.sh"
echo "2) systemd : $WORKSPACE_DIR/NIP-101/systemd-setup.sh"
