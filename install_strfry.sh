#!/bin/bash

# Définition des chemins
WORKSPACE_DIR="$HOME/.zen/workspace"
STRFRY_SRC_DIR="$WORKSPACE_DIR/strfry"
STRFRY_INSTALL_DIR="$HOME/.zen/strfry"

# Création des répertoires nécessaires
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$STRFRY_INSTALL_DIR"

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
    make -j4
}

# Fonction pour compiler strfry
update_strfry() {
    echo "Updating strfry..."
    make update-submodules
    make -j4
}

# Fonction pour installer ou mettre à jour strfry
install_strfry() {
    if [[ $(diff "$STRFRY_SRC_DIR/build/strfry" "$STRFRY_INSTALL_DIR/strfry") ]]; then
        echo "Installation strfry..."
        cp "$STRFRY_SRC_DIR/build/strfry" "$STRFRY_INSTALL_DIR/"
    else
        echo "strfry binary unchanged..."
    fi
    # Copie du fichier de configuration s'il n'existe pas déjà
    if [ ! -f "$STRFRY_INSTALL_DIR/strfry.conf" ]; then
        echo "$STRFRY_INSTALL_DIR/strfry.conf"
        cp "$STRFRY_SRC_DIR/build/strfry.conf" "$STRFRY_INSTALL_DIR/"
    fi
}

# Exécution des fonctions
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
echo "Le fichier de configuration se trouve dans $STRFRY_INSTALL_DIR/strfry.conf"
