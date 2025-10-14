# 🔄 Lifecycle des fichiers amisOfAmis.txt et blacklist.txt

## 📊 Diagramme du cycle de vie

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           NOSTRCARD.refresh.sh                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐   │
│  │   MULTIPASS     │───▶│  nostr_get_N1   │───▶│   fof_list (amis)     │   │
│  │   (carte NOSTR) │    │   (récupère     │    │                         │   │
│  │                 │    │    les amis)    │    │                         │   │
│  └─────────────────┘    └─────────────────┘    └─────────────────────────┘   │
│                                                          │                   │
│                                                          ▼                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │              amisOfAmis.txt (local)                                     │ │
│  │  printf "%s\n" "${fof_list[@]}" | sort -u >> amisOfAmis.txt            │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           NODE.refresh.sh                                   │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐   │
│  │  amisOfAmis.txt │───▶│   Cache Node    │───▶│   ~/.zen/tmp/IPFSNODEID │   │
│  │   (local)       │    │                 │    │                         │   │
│  └─────────────────┘    └─────────────────┘    └─────────────────────────┘   │
│                                                          │                   │
│  ┌─────────────────┐    ┌─────────────────┐            │                   │
│  │  blacklist.txt  │───▶│   Cache Node    │────────────┘                   │
│  │   (local)       │    │                 │                                │
│  └─────────────────┘    └─────────────────┘                                │
│                                                          │                   │
│                                                          ▼                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                    SWARM SYNC                                          │ │
│  │  cat ~/.zen/tmp/swarm/*/amisOfAmis.txt | sort -u >> amisOfAmis.txt    │ │
│  │  cat ~/.zen/tmp/swarm/*/blacklist.txt | sort -u >> blacklist.txt      │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                          │                   │
│                                                          ▼                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                    DEDUPLICATION                                       │ │
│  │  sort -u amisOfAmis.txt -o amisOfAmis.txt                              │ │
│  │  sort -u blacklist.txt -o blacklist.txt                                │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        RELAY POLICY SYSTEM                                  │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐   │
│  │   Event NOSTR   │───▶│  Check blacklist│───▶│  Pubkey in blacklist?   │   │
│  │   (incoming)    │    │                 │    │                         │   │
│  └─────────────────┘    └─────────────────┘    └─────────────────────────┘   │
│                                                          │                   │
│                                                          ▼                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  IF in blacklist:                                                       │ │
│  │    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐   │ │
│  │    │ Check amisOfAmis │───▶│  In amisOfAmis? │───▶│  ALLOW (remove  │   │ │
│  │    │                 │    │                 │    │   from blacklist)│   │ │
│  │    └─────────────────┘    └─────────────────┘    └─────────────────┘   │ │
│  │                                                          │               │ │
│  │                                                          ▼               │ │
│  │    ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │    │  IF NOT in amisOfAmis: BLOCK event                            │   │ │
│  │    └─────────────────────────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                          │                   │
│                                                          ▼                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  IF NOT in blacklist: ALLOW event                                     │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 🔍 **Détails du processus**

### **1. Phase de collecte (NOSTRCARD.refresh.sh)**
- **Déclenchement** : À chaque refresh d'une carte NOSTR (MULTIPASS)
- **Action** : Récupération des amis (N1) via `nostr_get_N1.sh`
- **Résultat** : Ajout des HEX des amis dans `amisOfAmis.txt`

### **2. Phase de synchronisation (NODE.refresh.sh)**
- **Déclenchement** : À chaque refresh du nœud
- **Actions** :
  - Copie des fichiers locaux vers le cache du nœud
  - Fusion avec les fichiers du swarm (réseau de nœuds)
  - Déduplication avec `sort -u`
  - Publication des fichiers mis à jour

### **3. Phase d'utilisation (Relay Policy)**
- **Principe** : "Whitelist by default, blacklist exceptions"
- **Logique** :
  1. Vérifier si la pubkey est dans `blacklist.txt`
  2. Si oui, vérifier si elle est dans `amisOfAmis.txt`
  3. Si dans `amisOfAmis.txt` → AUTORISER
  4. Si pas dans `amisOfAmis.txt` → BLOQUER
  5. Si pas dans `blacklist.txt` → AUTORISER

## 📈 **Métriques et monitoring**

```bash
# Compteurs dans NODE.refresh.sh
echo "Updated blacklist.txt: $(cat $HOME/.zen/strfry/blacklist.txt | wc -l) entries"
echo "Updated amisOfAmis.txt: $(cat $HOME/.zen/strfry/amisOfAmis.txt | wc -l) entries"
```

## 🎯 **Avantages du système**

1. **Réseau étendu** : Les amis des MULTIPASS peuvent utiliser le relay
2. **Sécurité** : Système de blacklist pour bloquer les utilisateurs indésirables
3. **Flexibilité** : Possibilité de retirer de la blacklist via `amisOfAmis.txt`
4. **Synchronisation** : Partage des listes entre tous les nœuds du swarm
5. **Déduplication** : Évite les doublons dans les fichiers

## 🔧 **Fichiers impliqués**

- **`~/.zen/strfry/amisOfAmis.txt`** : Fichier principal des amis d'amis
- **`~/.zen/strfry/blacklist.txt`** : Fichier principal de la liste noire
- **`~/.zen/tmp/$IPFSNODEID/amisOfAmis.txt`** : Cache local du nœud
- **`~/.zen/tmp/$IPFSNODEID/blacklist.txt`** : Cache local du nœud
- **`~/.zen/tmp/swarm/*/amisOfAmis.txt`** : Fichiers du swarm
- **`~/.zen/tmp/swarm/*/blacklist.txt`** : Fichiers du swarm
