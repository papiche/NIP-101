#!/bin/bash

## strfry + strfry.conf
# Définition des chemins
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/.zen/workspace}"
NIP101_DIR="${NIP101_DIR:-$WORKSPACE_DIR/NIP-101}"
STRFRY_SRC_DIR="${STRFRY_SRC_DIR:-$WORKSPACE_DIR/strfry}"
STRFRY_INSTALL_DIR="${STRFRY_INSTALL_DIR:-$HOME/.zen/strfry}"

# Fonction pour afficher l'aide
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h      Afficher cette aide."
    echo "  --update, -u    Mettre à jour strfry et ses dépendances."
    echo "  --install, -i   Installer strfry et ses dépendances."
    echo ""
    echo "Description:"
    echo "  Ce script installe ou met à jour strfry, un relais Nostr, ainsi que ses dépendances."
    echo "  Il clone également le dépôt NIP-101 pour configurer un relais Nostr personnalisé."
    echo ""
}

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
    echo "Compilation de strfry..."
    git submodule update --init
    make setup-golpe
    make -j3
}

# Fonction pour mettre à jour strfry
update_strfry() {
    echo "Mise à jour de strfry..."
    make update-submodules
    make -j3
}

# Fonction pour installer ou mettre à jour strfry
install_strfry() {
    if [[ -s "$STRFRY_SRC_DIR/strfry" ]]; then
        if ! cmp -s "$STRFRY_SRC_DIR/strfry" "$STRFRY_INSTALL_DIR/strfry"; then
            echo "Installation de strfry..."
            cp -f "$STRFRY_SRC_DIR/strfry" "$STRFRY_INSTALL_DIR/"
            chmod +x "$STRFRY_INSTALL_DIR/strfry"
        else
            echo "Le binaire strfry n'a pas changé."
        fi
    fi
    # Copie du fichier de configuration s'il n'existe pas déjà
    if [ ! -f "$STRFRY_INSTALL_DIR/strfry.conf" ]; then
        echo "Création du fichier de configuration $STRFRY_INSTALL_DIR/strfry.conf"
        cat "$STRFRY_SRC_DIR/strfry.conf" | sed "s~127.0.0.1~0.0.0.0~g" > "$STRFRY_INSTALL_DIR/strfry.conf"
    fi
    # Copie du script de démarrage
    cp start_strfry-relay.sh "$STRFRY_INSTALL_DIR/start.sh"
    mkdir -p "$STRFRY_INSTALL_DIR/strfry-db/"
}

# Gestion des arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --update|-u)
            install_dependencies
            clone_or_update_repo
            update_strfry
            install_strfry
            exit 0
            ;;
        --install|-i)
            install_dependencies
            clone_or_update_repo
            compile_strfry
            install_strfry
            exit 0
            ;;
        *)
            echo "Option inconnue : $1"
            show_help
            exit 1
            ;;
    esac
fi

########################################
## INSTALL NOSTR RELAY
echo "Installation NIP-101"
if [[ ! -d $NIP101_DIR ]]; then
    echo "Clonage de NIP-101 = UPlanet NOSTR Relay ASTROBOT 'Side Chain'"
    cd $WORKSPACE_DIR
    git clone https://github.com/papiche/NIP-101.git
fi

if [[ ! -s "$STRFRY_INSTALL_DIR/strfry" ]]; then
    install_dependencies
    clone_or_update_repo
    compile_strfry
    install_strfry
else
    echo "Souhaitez-vous mettre à jour strfry ? (y/N)"
    read QUOI
    if [[ $QUOI == "y" ]]; then
        clone_or_update_repo
        update_strfry
        install_strfry
    fi
fi

echo "Strfry : $STRFRY_INSTALL_DIR/start.sh"
cp $WORKSPACE_DIR/NIP-101/start_strfry-relay.sh $STRFRY_INSTALL_DIR/start.sh
echo "Pour finaliser l'installation :"
echo "1) Exécutez : $WORKSPACE_DIR/NIP-101/setup.sh"
echo "2) Configurez systemd : $WORKSPACE_DIR/NIP-101/systemd.setup.sh"
