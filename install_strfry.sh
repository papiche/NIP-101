#!/bin/bash
## IPFS BINARY
## strfry + strfry.conf
strfry_amd64="/ipfs/QmPq6nbDDXP33n8XG7jJsc5j92xJ7tqsZSeVqkhTYt4V8D"
strfry_arm64="/ipfs/Qmb2TNyXhdvaUxec69W7UPQ1yfBAmXpR6TyhXWopzwWi9X"

# Définition des chemins
WORKSPACE_DIR="$HOME/.zen/workspace"
STRFRY_SRC_DIR="$WORKSPACE_DIR/strfry"
STRFRY_INSTALL_DIR="$HOME/.zen/strfry"

# Création des répertoires nécessaires
mkdir -p ./tmp
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
    if [[ -s "$STRFRY_SRC_DIR/strfry" && ! -s "$STRFRY_INSTALL_DIR/strfry" ]]; then
        echo "Installation strfry..."
        cp "$STRFRY_SRC_DIR/strfry" "$STRFRY_INSTALL_DIR/"
    else
        echo "strfry binary unchanged..."
    fi
    # Copie du fichier de configuration s'il n'existe pas déjà
    if [ ! -f "$STRFRY_INSTALL_DIR/strfry.conf" ]; then
        echo "$STRFRY_INSTALL_DIR/strfry.conf"
        cp "$STRFRY_SRC_DIR/strfry.conf" "$STRFRY_INSTALL_DIR/"
    fi
}

# Fonction pour installer nostr-commander-rs
install_nostr_commander() {
    echo "Installation de nostr-commander-rs..."
    ## nostr-commander-rs
    nostr_amd64="/ipfs/QmeP6QD7Men8KtgX9mCNXFuGM5edTLQ7gsUWEvmpBNGZUo/nostr-commander-rs"
    nostr_arm64="/ipfs/QmcwSZmM3TpEViT39gDAtkDsSuWtZvQNyW659dMDgptKaW/nostr-commander-rs"

    # Déterminer l'architecture
    ARCH=$(uname -m)

    # Définir l'URL IPFS en fonction de l'architecture
    if [ "$ARCH" = "x86_64" ]; then
        NOSTR_COMMANDER_CID="$nostr_amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        NOSTR_COMMANDER_CID="$nostr_arm64"
    else
        echo "Architecture non supportée pour nostr-commander-rs"
        return 1
    fi

    # Télécharger et installer nostr-commander-rs
    ipfs get -o "$HOME/.local/bin/nostr-commander-rs" "$NOSTR_COMMANDER_CID"
    chmod +x "$HOME/.local/bin/nostr-commander-rs"

    CREDENTIALS_DIR="$HOME/.local/share/nostr-commander-rs"
    mkdir -p $CREDENTIALS_DIR
    CREDENTIALS_FILE="$CREDENTIALS_DIR/credentials.json"

    echo -e "${GREEN}Création du fichier credentials.json...${NC}"
    mkdir -p "$CREDENTIALS_DIR"
    cat > "$CREDENTIALS_FILE" <<EOL
{
  "secret_key_bech32": "nsec1hsmhy4d6ve325gxpgk0lzlmu4vymf49r4gq07sw5wjsezz74nrls8cryds",
  "public_key_bech32": "npub1eq0gkvwm43jc506neat4y8t4cyp4z2w846qtxexuc5syh9h5v47sptlfff",
  "relays": [
    {
      "url": "wss://relay.g1sms.fr/",
      "proxy": null
    },
    {
      "url": "wss://relay.copylaradio.com/",
      "proxy": null
    },
    {
      "url": "ws://127.0.0.1:7777/",
      "proxy": null
    }
  ],
  "metadata": {
    "name": "coucou",
    "display_name": "coucou",
    "about": "coucou",
    "picture": "http://127.0.0.1:8080/ipfs/QmbUAMgnTm4dFnH66kgmUXpBBqUMdTmfedvzuYTmgXd8s9",
    "nip05": "support@qo-op.com"
  },
  "contacts": [],
  "subscribed_pubkeys": [],
  "subscribed_authors": [],
  "subscribed_channels": []
}
EOL

    echo "nostr-commander-rs installé"
}

########################################
## INSTALL NOSTR CLIENT
[[ ! $(which nostr-commander-rs) && $(which ipfs) ]] && install_nostr_commander


########################################
## INSTALL NOSTR RELAY
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
