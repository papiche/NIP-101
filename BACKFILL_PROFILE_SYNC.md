# 🔄 Constellation Backfill avec Synchronisation des Profils

## 📋 Qu'est-ce que fait le script `backfill_constellation.sh` ?

Le script `backfill_constellation.sh` est le cœur du système de synchronisation de la constellation NOSTR. Voici son fonctionnement détaillé :

### 🎯 Objectifs Principaux

1. **Découverte des peers** : Scanne le swarm IPFS pour trouver les relays NOSTR de la constellation
2. **Synchronisation des messages** : Récupère les événements NOSTR des derniers jours (par défaut 1 jour)
3. **Extraction des profils** : Convertit les clés HEX en profils lisibles (kind 0)
4. **Synchronisation complète** : Si un profil n'est pas trouvé, récupère **TOUS** les messages de cette clé (sans limite temporelle)

### 🔍 Flux de Traitement

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. DÉCOUVERTE DES PEERS                                        │
│    - Scan ~/.zen/tmp/swarm/*/12345.json                        │
│    - Extrait myRELAY et ipfsnodeid                             │
│    - Identifie les relays routables et P2P tunnels             │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. SYNCHRONISATION STANDARD (1 jour par défaut)                │
│    - Récupère les HEX pubkeys de la constellation              │
│    - Pour chaque peer, synchronise les événements récents      │
│    - Kinds: 0, 1, 3, [4], 5, 6, 7, 30023, 30024               │
│    - Import dans strfry (--no-verify pour la vitesse)          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. EXTRACTION DES PROFILS (si --extract-profiles)              │
│    - Collecte toutes les HEX pubkeys de la constellation       │
│    - Appelle hex_to_profile.sh pour convertir en profils       │
│    - Récupère kind 0 (profile) et kind 3 (relays)             │
│    - Génère profiles.json avec les données structurées         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. VÉRIFICATION DES PROFILS MANQUANTS                         │
│    - Pour chaque HEX pubkey, vérifie si kind 0 existe          │
│    - Si PROFIL TROUVÉ:                                          │
│      ✅ Affiche: nom, display_name, nip05                      │
│    - Si PROFIL NON TROUVÉ:                                      │
│      ❌ Ajoute à la liste missing_profiles[]                   │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. SYNCHRONISATION COMPLÈTE (si profils manquants)             │
│    - Pour chaque HEX sans profil:                               │
│      🔄 FULL SYNC (since=0, limit=50000)                       │
│      📡 Récupère TOUS les messages (pas de limite temporelle)  │
│      ✅ Continue jusqu'à succès ou épuisement des peers        │
│      ⏱️  Timeout 60s par HEX (vs 30s pour sync standard)       │
└─────────────────────────────────────────────────────────────────┘
```

## 🔑 Logique de Détection des Profils Manquants

### Pourquoi un profil peut être manquant ?

1. **Nouvelle clé** : C'est la première fois que cette HEX pubkey est vue
2. **Sync incomplet** : La synchronisation précédente n'a pas récupéré le kind 0
3. **Profil supprimé** : L'utilisateur a supprimé son profil (rare)
4. **Relay inaccessible** : Le relay source était hors ligne lors des syncs précédents

### Comment détecter un profil manquant ?

```bash
# Requête strfry pour chercher le kind 0
local profile_event=$(cd "$HOME/.zen/strfry" && ./strfry scan "{
    \"kinds\": [0],
    \"authors\": [\"$hex_pubkey\"],
    \"limit\": 1
}" 2>/dev/null | jq -c 'select(.kind == 0)' 2>/dev/null | head -1)

# Si profile_event est vide ou null
if [[ -z "$profile_event" || "$profile_event" == "null" ]]; then
    # ❌ PROFIL MANQUANT → FULL SYNC
    missing_profiles+=("$hex_pubkey")
fi
```

### Action de correction automatique

Lorsqu'un profil est manquant, le script lance automatiquement une **synchronisation complète** :

```bash
# Synchronisation complète pour HEX sans profil
execute_backfill_websocket_single_hex "$relay_url" "0" "$missing_hex"
#                                                    ↑
#                                                    since=0 (tous les messages)
```

**Paramètres de la synchronisation complète :**
- `since: 0` → Récupère tous les messages depuis le début
- `limit: 50000` → Limite haute pour récupérer le maximum d'événements
- `timeout: 60s` → Plus de temps pour collecter les données
- `kinds: [0, 1, 3, 4, 5, 6, 7, 30023, 30024]` → Tous les types d'événements

## 📊 Informations Affichées pour Chaque Profil

### Profil Trouvé ✅

```log
[2025-10-15 00:51:52] [INFO]   ✅ 7f3b6ad3... Profile: Alice
[2025-10-15 00:51:52] [INFO]       Display: Alice in Wonderland
[2025-10-15 00:51:52] [INFO]       NIP-05: alice@example.com
```

**Données extraites du kind 0 :**
- `name` → Nom d'affichage principal
- `display_name` → Nom d'affichage alternatif
- `nip05` → Identifiant vérifié
- `about` → Biographie
- `picture` → URL de l'avatar
- `website` → Site web personnel

### Profil Non Trouvé ❌

```log
[2025-10-15 00:51:52] [WARN]   ❌ 5e186df4... NO PROFILE FOUND - scheduling full sync
[2025-10-15 00:51:52] [INFO]   🔄 FULL SYNC for 5e186df4... (all messages, no time limit)
[2025-10-15 00:51:52] [INFO]     📡 Syncing from: wss://relay.copylaradio.com
[2025-10-15 00:51:55] [INFO]     ✅ Full sync successful for 5e186df4
```

## 🚀 Utilisation

### Commande Standard (avec extraction de profils)

```bash
./backfill_constellation.sh --verbose --days 1
```

### Commande sans Extraction de Profils

```bash
./backfill_constellation.sh --verbose --no-profiles
```

### Commande avec DMs Exclus

```bash
./backfill_constellation.sh --verbose --no-dms
```

### Commande avec Vérification des Signatures

```bash
./backfill_constellation.sh --verbose --verify
```

## 📈 Statistiques Affichées

```log
[2025-10-15 00:51:52] [INFO] 📊 Found 12 HEX pubkeys with profiles
[2025-10-15 00:51:52] [INFO] 📊 Found 3 HEX pubkeys WITHOUT profiles
[2025-10-15 00:51:52] [INFO] 🔄 Triggering FULL SYNC (no time limit) for 3 HEX pubkeys without profiles...
```

### Métriques Collectées

- **Total HEX pubkeys** : Nombre de clés dans la constellation
- **With profiles** : Nombre de profils trouvés (kind 0 présent)
- **WITHOUT profiles** : Nombre de profils manquants
- **Full syncs** : Nombre de synchronisations complètes effectuées
- **Events collected** : Nombre total d'événements récupérés

## 🔧 Options Disponibles

| Option | Description | Défaut |
|--------|-------------|--------|
| `--days N` | Nombre de jours à synchroniser | 1 |
| `--verbose` | Affichage détaillé | false |
| `--no-dms` | Exclure les messages directs (kind 4) | false |
| `--verify` | Vérifier les signatures (plus lent) | false |
| `--no-profiles` | Ne pas extraire les profils | false |
| `--DRYRUN` | Mode simulation | false |

## 📁 Fichiers de Sortie

### Logs
- `~/.zen/strfry/constellation-backfill.log` → Log principal du backfill
- `~/.zen/strfry/hex-to-profile.log` → Log de l'extraction des profils

### Données
- `~/.zen/tmp/coucou/_NIP101.profiles.json` → Profils extraits (JSON)
- `~/.zen/tmp/constellation_hex_*.txt` → Liste temporaire des HEX pubkeys

### Base de Données
- `~/.zen/strfry/strfry-db/data.mdb` → Base LMDB avec tous les événements

## 🎯 Cas d'Usage

### 1. Synchronisation Horaire Standard

```bash
# Appelé par constellation_sync_trigger.sh toutes les heures
./backfill_constellation.sh --days 1 --verbose
```

**Résultat :**
- Synchronise les événements des dernières 24h
- Extrait les profils de toutes les HEX pubkeys
- Lance une full sync pour les profils manquants
- Log détaillé des opérations

### 2. Récupération Initiale Complète

```bash
# Première synchronisation d'une nouvelle instance
./backfill_constellation.sh --days 30 --verbose --verify
```

**Résultat :**
- Synchronise 30 jours d'événements
- Vérifie toutes les signatures
- Extrait et vérifie tous les profils
- Garantit l'intégrité des données

### 3. Maintenance Rapide

```bash
# Sync rapide sans profils
./backfill_constellation.sh --days 1 --no-profiles
```

**Résultat :**
- Synchronise uniquement les nouveaux événements
- Skip l'extraction des profils (plus rapide)
- Utile pour les syncs fréquents

## 🐛 Dépannage

### Problème : Pas de profils trouvés

```log
[2025-10-15 00:51:52] [INFO] 📊 Found 0 HEX pubkeys with profiles
[2025-10-15 00:51:52] [INFO] 📊 Found 96 HEX pubkeys WITHOUT profiles
```

**Solution :**
- Le script va automatiquement lancer une full sync pour chaque HEX
- Vérifier que les relays sont accessibles
- Augmenter le timeout si nécessaire

### Problème : Full sync timeout

```log
[2025-10-15 00:52:55] [WARN]   ❌ Full sync failed for 5e186df4 from wss://relay.example.com
```

**Solution :**
- Le script essaiera le relay suivant automatiquement
- Si tous les relays échouent, le profil restera manquant
- Relancer le script plus tard

### Problème : Too many HEX pubkeys

```log
[2025-10-15 00:51:52] [INFO] Found 500 HEX pubkeys in constellation
```

**Solution :**
- Le script traite par batches de 50
- Augmenter le timeout global si nécessaire
- Considérer un filtrage par région/zone

## 🌟 Avantages de cette Approche

1. **Automatique** : Détecte et corrige les profils manquants automatiquement
2. **Intelligent** : Synchronise uniquement ce qui est nécessaire
3. **Robuste** : Réessaie avec différents relays en cas d'échec
4. **Traçable** : Logs détaillés pour le debugging
5. **Scalable** : Gère efficacement des centaines de HEX pubkeys
