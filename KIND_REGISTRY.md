# Registre des Kinds NOSTR — NIP-101 UPlanet
## Kind Registry · Document de référence technique

---

**Numéro de document :** NIP-101/KIND-REG-1.0  
**Statut :** Production  
**Auteur :** Fred Camps `<support@qo-op.com>`  
**Organisation :** UPlanet / Astroport.ONE Cooperative  
**Licence :** AGPL-3.0  
**Date de publication :** 2026-05-25  
**Dernière révision :** 2026-05-25  
**Dépôt :** `github.com/papiche/NIP-101`

---

## Résumé

Ce document constitue le registre de référence des **kinds NOSTR** utilisés par l'écosystème UPlanet/Astroport.ONE. Il est organisé à la manière de la nomenclature **IANA des ports TCP/IP** (RFC 6335) : chaque kind y est traité comme un « port de service », avec sa description fonctionnelle, la structure JSON canonique de ses événements, ses tags obligatoires et optionnels, la politique de filtrage appliquée par le plugin `writePolicy` de strfry (NIP-101), et son niveau de synchronisation dans la constellation.

---

## Table des matières

1. [Conventions](#1-conventions)
2. [Structure canonique d'un événement NOSTR](#2-structure-canonique-dun-événement-nostr)
3. [Classes de kinds](#3-classes-de-kinds)
4. [Registre — Classe CORE (0–999)](#4-registre--classe-core-0999)
5. [Registre — Classe APPLICATION (1000–9999)](#5-registre--classe-application-10009999)
6. [Registre — Classe REPLACEABLE (10000–19999)](#6-registre--classe-replaceable-1000019999)
7. [Registre — Classe ÉPHÉMÈRE (20000–29999)](#7-registre--classe-éphémère-2000029999)
8. [Registre — Classe ADRESSABLE (30000–39999)](#8-registre--classe-adressable-3000039999)
9. [Index des filtres writePolicy NIP-101](#9-index-des-filtres-writepolicy-nip-101)
10. [Matrice de synchronisation constellation](#10-matrice-de-synchronisation-constellation)
11. [Glossaire](#11-glossaire)

---

## 1. Conventions

### 1.1 Analogie TCP/IP → NOSTR

| Plage TCP/IP | Sémantique TCP/IP | Plage Kind NOSTR | Sémantique NOSTR |
|---|---|---|---|
| 0–1023 | Ports bien connus (Well-Known) | **0–999** | Kinds fondamentaux du protocole |
| 1024–49151 | Ports enregistrés (Registered) | **1000–29999** | Kinds applicatifs étendus |
| 49152–65535 | Ports dynamiques/privés | **30000–39999** | Kinds adressables paramétrés |
| — | États éphémères | **20000–29999** | Kinds éphémères (non persistés) |

### 1.2 Niveaux de statut

| Statut | Signification |
|---|---|
| `FINAL` | Spécification stabilisée, implémentation de référence disponible |
| `DRAFT` | En cours de spécification, susceptible d'évoluer |
| `UPLANET` | Extension UPlanet, non standardisée dans le protocole NOSTR général |
| `DEPRECATED` | Déconseillé, remplacé par un autre kind |

### 1.3 Niveaux d'autorisation NIP-101

| Niveau | Identifiant | Condition d'accès |
|---|---|---|
| 0 | `nobody` | Pubkey inconnue de toute liste |
| 1 | `amisOfAmis` | Présent dans `~/.zen/strfry/amisOfAmis.txt` |
| 2 | `player` | Présent dans `~/.zen/tmp/swarm/*/TW/*/HEX` (constellation) |
| 3 | `uplanet` | Présent dans `~/.zen/game/nostr/*/HEX` (MULTIPASS local) |

### 1.4 Types d'événements NOSTR

| Type | Description | Comportement relay |
|---|---|---|
| **Regular** | Événement ordinaire | Stocké, jamais remplacé |
| **Replaceable** | Un seul valide par `(kind, pubkey)` | Le plus récent remplace l'ancien |
| **Addressable** | Un seul valide par `(kind, pubkey, d-tag)` | Le plus récent remplace l'ancien |
| **Ephemeral** | Transitoire | Non persisté, relayé uniquement |

### 1.5 Notation des tags

```
["tag_name", "valeur_obligatoire", "valeur_optionnelle?"]
```

Les éléments suffixés `?` sont optionnels. Les types sont indiqués en italique : *string*, *hex64*, *unix-timestamp*, *url*, *float*, *int*.

---

## 2. Structure canonique d'un événement NOSTR

Tout événement NOSTR partage la structure de base suivante (NIP-01) :

```json
{
  "id":         "<hex64 — SHA256(sérialisé)>",
  "pubkey":     "<hex64 — clé publique Schnorr secp256k1>",
  "created_at": "<unix-timestamp — entier>",
  "kind":       "<int — identifiant du type d'événement>",
  "tags":       [["<tag>", "<valeur>", "..."], ...],
  "content":    "<string — charge utile textuelle ou JSON>",
  "sig":        "<hex128 — signature Schnorr secp256k1>"
}
```

**Règles de hachage :** `id = SHA256(JSON([0, pubkey, created_at, kind, tags, content]))`  
**Vérification :** La signature `sig` couvre `id` via Schnorr sur secp256k1.

---

## 3. Classes de kinds

```
 Kind 0         Kind 999      Kind 9999     Kind 19999    Kind 29999    Kind 39999
  │                │              │              │              │              │
  ▼                ▼              ▼              ▼              ▼              ▼
┌────────────────────┐  ┌───────────────┐  ┌───────────┐  ┌───────────┐  ┌──────────────────────┐
│   CORE (0–999)     │  │  APPLICATION  │  │REPLACEABLE│  │ ÉPHÉMÈRE  │  │    ADRESSABLE        │
│                    │  │ (1000–19999)  │  │(10000–    │  │(20000–    │  │   (30000–39999)      │
│ Protocole de base  │  │               │  │  19999)   │  │  29999)   │  │                      │
│ • Profils          │  │ Applicatifs   │  │           │  │           │  │ Paramétré par d-tag  │
│ • Notes            │  │ étendus       │  │ État user │  │ Transient │  │ • DID                │
│ • Contacts         │  │               │  │           │  │           │  │ • Oracle             │
│ • Réactions        │  │               │  │           │  │           │  │ • ORE                │
│ • Réponses         │  │               │  │           │  │           │  │ • Crowdfunding       │
└────────────────────┘  └───────────────┘  └───────────┘  └───────────┘  └──────────────────────┘
```

**Résumé des classes :**

| Classe | Plage | Type | Nb kinds actifs UPlanet |
|---|---|---|---|
| CORE | 0–999 | Regular / Replaceable | 10 |
| APPLICATION | 1000–9999 | Regular | 8 |
| REPLACEABLE | 10000–19999 | Replaceable | 2 |
| ÉPHÉMÈRE | 20000–29999 | Ephemeral | 2 |
| ADRESSABLE | 30000–39999 | Addressable | 18 |
| **TOTAL** | | | **41** |

---

## 4. Registre — Classe CORE (0–999)

> Analogie : ports bien connus (0–1023). Kinds fondamentaux définis par NIP-01.

---

### Kind 0 — Metadata (Profil utilisateur)

| Champ | Valeur |
|---|---|
| **Kind** | `0` |
| **Nom de service** | User Metadata / Profile |
| **Type** | Replaceable |
| **Statut NIP** | FINAL (NIP-01) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/0.sh` |
| **Sync constellation** | OUI — Core |

**Description :** Publie les métadonnées publiques d'un utilisateur. Un seul événement valide par `pubkey`. Le relay remplace toute version antérieure.

**Structure JSON — `content` :**

```json
{
  "name":          "alice",
  "display_name":  "Alice Durand",
  "about":         "Coopératrice UPlanet, Toulouse",
  "picture":       "https://...",
  "website":       "https://...",
  "nip05":         "alice@astroport.copylaradio.com",
  "lud16":         "alice@getalby.com",
  "g1pub":         "<base58-clé-publique-Ğ1>",
  "g1nostr":       "<hex64-pubkey-NOSTR-associée>",
  "uplanet":       "<UPLANETNAME_G1_hex>"
}
```

**Tags :**

```
["i", "github:alice", "proof_url"]   — Identité externe NIP-39 (optionnel)
["i", "twitter:alice"]               — (optionnel)
```

**Sous-services :**
- **NIP-05 Verification** — Résolution `/.well-known/nostr.json?name=alice@domain`
- **NIP-39 External Identities** — Preuves d'identité croisée
- **MULTIPASS Link** — Champ `g1pub` liant le profil NOSTR au wallet Ğ1

**Politique de filtrage NIP-101 :**

| Condition | Action |
|---|---|
| `name` contient `(RSS Feed)` | `reject` |
| `nip05` domaine `atomstr.data.haus` | `reject` |
| Pubkey absente de toutes les listes | `accept` (avec log) |
| Pubkey `uplanet` ou `amisOfAmis` | `accept` + log détaillé |

**Log :** `~/.zen/tmp/nostr_kind0.log`

---

### Kind 1 — Text Note (Note courte)

| Champ | Valeur |
|---|---|
| **Kind** | `1` |
| **Nom de service** | Text Note / Short Post |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-01) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/1.sh` |
| **Sync constellation** | OUI — Core |

**Description :** Note textuelle courte, équivalent du tweet. Unité de base du réseau social NOSTR.

**Structure JSON — `content` :**

```
"Texte libre en clair. Pas de markup."
```

**Tags standards :**

```
["e", "<hex64-event-id>", "<relay-url?>", "reply|root|mention?", "<pubkey?>"]
["p", "<hex64-pubkey>", "<relay-url?>"]
["q", "<hex64-event-id>", "<relay-url?>", "<pubkey?>"]  — Citation
["subject", "Titre de la conversation"]
["t", "hashtag"]
["r", "<url>"]
```

**Tags UPlanet étendus :**

```
["g",         "<lat,lon>"]       — Géolocalisation
["latitude",  "<float>"]
["longitude", "<float>"]
["application","UPlanet"]
["#secret",   ""]                — Message confidentiel (rejeté)
["#rec",      "<1–12>"]          — Slot mémoire personnel
["#plantnet", ""]                — Requête identification végétale
["#BRO",      ""]                — Déclencheur IA assistant
["#BOT",      ""]                — Déclencheur IA automatisé
```

**Sous-services UPlanet :**

| Service | Déclencheur | Traitement |
|---|---|---|
| **IA Responder** | `#BRO` ou `#BOT` dans les tags | Mise en file `UPlanet_IA_Responder.sh` |
| **PlantNet** | `#plantnet` dans les tags | Routage vers API PlantNet d'identification |
| **Memory Slots** | `#rec` + slot `1`–`12` | Contrôle d'accès par `check_memory_slot_access()` |
| **UMAP Follow** | Tags `g`/`latitude`/`longitude` présents | Auto-follow du canal UMAP de la zone |
| **Visitor Queue** | Pubkey `nobody` | Rate-limiting : 3 messages puis blacklist |

**Politique de filtrage NIP-101 :**

| Condition | Action |
|---|---|
| Tag `#secret` présent | `reject` |
| Pubkey `nobody` + contenu < 50 caractères | `reject` |
| Pubkey `nobody` + > 3 messages | `shadowReject` + blacklist |
| Tag `#plantnet` | `accept` + routage PlantNet |
| Tag `#BRO`/`#BOT` | `accept` + mise en file IA |
| Tag `#rec` + slot interdit | `reject` |
| Tous autres cas autorisés | `accept` |

**Log :** `~/.zen/tmp/nostr_kind1_messages.log`

---

### Kind 3 — Contacts (Liste de contacts)

| Champ | Valeur |
|---|---|
| **Kind** | `3` |
| **Nom de service** | Contact List / Follow List |
| **Type** | Replaceable |
| **Statut NIP** | FINAL (NIP-02) |
| **Filtre NIP-101** | Aucun filtre spécifique — `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Core |

**Description :** Liste complète des comptes suivis par un utilisateur. Remplace intégralement la version précédente à chaque mise à jour.

**Structure JSON — `content` :** `""` (chaîne vide)

**Tags :**

```
["p", "<hex64-pubkey>", "<relay-url?>", "<petname?>"]
```

> Chaque tag `p` représente un compte suivi. `relay-url` et `petname` sont optionnels.

**Utilisation NIP-101 :** Le fichier `amisOfAmis.txt` est alimenté par les listes de contacts (kind 3) des membres locaux, via `nostr_get_N1.sh`.

---

### Kind 4 — Encrypted Direct Message (Message privé legacy)

| Champ | Valeur |
|---|---|
| **Kind** | `4` |
| **Nom de service** | DM Chiffré (Legacy) |
| **Type** | Regular |
| **Statut NIP** | FINAL (NIP-04) — **DEPRECATED** (remplacé par NIP-17) |
| **Filtre NIP-101** | Optionnel — flag `--no-dms` |
| **Sync constellation** | OPTIONNEL — désactivable |

**Description :** Message direct chiffré AES-256-CBC. Déprécié car il divulgue des métadonnées (qui parle à qui). Remplacé par Kind 13 + Kind 1059 (NIP-17).

**Structure JSON — `content` :**

```
"<base64-ciphertext>?iv=<base64-IV>"
```

**Tags :**

```
["p", "<hex64-pubkey-destinataire>"]     — Obligatoire
["e", "<hex64-event-id-precedent?>"]     — Threading optionnel
```

**Avertissement sécurité :** Ne pas utiliser pour de nouveaux développements. Privilégier Kind 1059 (NIP-17).

---

### Kind 5 — Deletion Request (Demande de suppression)

| Champ | Valeur |
|---|---|
| **Kind** | `5` |
| **Nom de service** | Event Deletion |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-09) |
| **Filtre NIP-101** | Aucun filtre spécifique |
| **Sync constellation** | OUI — Core |

**Tags :**

```
["e", "<hex64-event-id>"]              — Événement à supprimer
["a", "<kind>:<pubkey>:<d-tag>"]       — Événement adressable à supprimer
["k", "<kind-string>"]                 — Kind de l'événement cible (informatif)
```

**Contenu :** Raison de la suppression (optionnel, texte libre)

**Règle relay :** Le relay ne supprime que si `pubkey` de la demande correspond à `pubkey` de l'événement ciblé.

---

### Kind 6 — Repost (Repartage)

| Champ | Valeur |
|---|---|
| **Kind** | `6` |
| **Nom de service** | Repost / Boost |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-18) |
| **Filtre NIP-101** | Aucun filtre spécifique |
| **Sync constellation** | OUI — Core |

**Structure JSON — `content` :** JSON stringifié de l'événement repartagé (ou `""` si NIP-70 protégé)

**Tags :**

```
["e", "<hex64-event-id>", "<relay-url>"]     — Obligatoire
["p", "<hex64-pubkey-auteur-original>"]       — Recommandé
["k", "<kind-string>"]                        — Kind de l'événement source
```

**Variante :** Kind `16` pour les reposts d'événements non-Kind-1.

---

### Kind 7 — Reaction (Réaction / Paiement ZEN)

| Champ | Valeur |
|---|---|
| **Kind** | `7` |
| **Nom de service** | Reaction / ZEN Payment / Crowdfunding Vote |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-25) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/7.sh` |
| **Sync constellation** | OUI — Core |

**Description :** Réaction à un événement (like/dislike/emoji). Dans l'écosystème UPlanet, un like déclenche automatiquement un micropaiement ZEN vers l'auteur de l'événement réagi. Extension critique du modèle économique UPlanet.

**Structure JSON — `content` :**

```
"+"                  — Like standard (déclenche paiement ZEN)
"-"                  — Dislike
"👍"                 — Emoji libre
"+10"                — Like avec montant ZEN explicite (UPlanet)
"+100"               — Contribution crowdfunding (UPlanet)
```

**Tags standards (NIP-25) :**

```
["e", "<hex64-event-id>"]              — Événement cible (obligatoire)
["p", "<hex64-pubkey-auteur>"]         — Auteur de l'événement cible
["k", "<kind-string>"]                 — Kind de l'événement cible
```

**Tags UPlanet étendus (Crowdfunding / Vote) :**

```
["t", "crowdfunding"]                  — Contribution à une campagne
["t", "vote-assets"]                   — Vote d'allocation d'actifs
["project-id", "CF-XXXXXXXX"]         — Identifiant de campagne
["target", "ZEN_CONVERTIBLE|VOTE"]    — Type de contribution
["i", "g1pub:<G1-pubkey-bien>"]       — Wallet Bien destinataire
```

**Sous-services UPlanet :**

| Service | Condition | Traitement |
|---|---|---|
| **Paiement ZEN standard** | `content` = `+` ou `+N` vers auteur UPlanet | `PAYforSURE.sh` → transfert G1 |
| **Crowdfunding** | tag `t=crowdfunding` présent | Paiement vers wallet Bien du projet |
| **Vote d'actifs** | tag `t=vote-assets` | Enregistrement vote + paiement si seuil atteint |
| **Relay roaming** | Auteur absent du nœud local | Transmission au nœud home via `nostr_node_intercom.py` |

**Conversions économiques :**

```
1 Ẑen (ZEN)  =  0.1 G1  =  ~0.01 EUR (mode développement)
1 Ẑen (ZEN)  =  équivalent 1 EUR (mode production UPlanet)
Paiement via : ~/.zen/Astroport.ONE/tools/PAYforSURE.sh
```

**Politique de filtrage NIP-101 :**

| Condition | Action |
|---|---|
| `pubkey` réacteur == `pubkey` auteur cible | `reject` (auto-like interdit) |
| Auteur non-membre UPlanet | `reject` (pas de paiement) |
| Crowdfunding : bien non enregistré | `reject` |
| Vote : seuil déjà atteint | `reject` |
| Tous les cas valides | `accept` + paiement asynchrone |

**Log :** `~/.zen/tmp/nostr_likes.log`

---

### Kind 8 — Badge Award (Attribution de badge)

| Champ | Valeur |
|---|---|
| **Kind** | `8` |
| **Nom de service** | Badge Award |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-58) |
| **Filtre NIP-101** | `all_but_blacklist.sh` (aucun filtre spécifique) |
| **Sync constellation** | OUI — Oracle |

**Description :** Attribution d'un badge défini (Kind 30009) à un utilisateur. Signé par l'autorité émettrice (`UPLANETNAME.G1`).

**Tags :**

```
["a", "30009:<hex64-badge-author>:<d-tag-badge>"]      — Badge défini
["p", "<hex64-pubkey-receveur>", "<relay-url?>"]        — Bénéficiaire
["credential_id", "<credential-uuid>"]                  — Identifiant de credential
["permit_id", "<PERMIT_XXX>"]                           — Lien vers permis Oracle
```

**Contenu :** Message d'attribution (ex : `"Credential issued: PERMIT_ORE_V1"`)

---

### Kind 9 — Chat Message Simple

| Champ | Valeur |
|---|---|
| **Kind** | `9` |
| **Nom de service** | Chat Message |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-C7) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | Selon configuration |

**Tags :**

```
["q", "<nevent-bech32>", "<relay-url?>", "<pubkey?>"]  — Citation/réponse
["p", "<hex64-pubkey>"]
["t", "<hashtag>"]
```

---

## 5. Registre — Classe APPLICATION (1000–9999)

> Analogie : ports enregistrés (1024–49151). Kinds applicatifs pour usages spécifiques.

---

### Kind 1063 — File Metadata (Métadonnées de fichier)

| Champ | Valeur |
|---|---|
| **Kind** | `1063` |
| **Nom de service** | File Metadata / NIP-94 Upload |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-94) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Media |

**Description :** Métadonnées d'un fichier uploadé sur IPFS ou HTTP. Pivot central du système de provenance UPlanet.

**Tags :**

```
["url",         "<url-fichier>"]                  — URL d'accès (obligatoire)
["x",           "<sha256-hex>"]                   — Hash du fichier (obligatoire — clé de déduplication)
["ox",          "<sha256-hex-original?>"]         — Hash original si re-upload
["m",           "<mime-type>"]                    — ex: "video/mp4"
["size",        "<int-bytes?>"]
["dim",         "<WIDTHxHEIGHT?>"]               — Images/vidéos uniquement
["thumb",       "<url-thumbnail?>"]
["blurhash",    "<hash?>"]                        — Prévisualisation de chargement
["magnet",      "<magnet-link?>"]
["info",        "<ipfs-cid-info-json?>"]          — Fichier info.json IPFS (UPlanet)
["upload_chain","<pubkey1,pubkey2,...?>"]         — Chaîne de distribution (UPlanet)
["e",           "<event-id-original?>", "", "mention"]  — Attribution (UPlanet)
["p",           "<pubkey-original?>"]             — Auteur original (UPlanet)
["latitude",    "<float?>"]
["longitude",   "<float?>"]
["g",           "<geohash?>"]
```

**Déduplication IPFS (UPlanet) :**

```
1. Calculer SHA256 du fichier
2. Chercher kind 1063 avec tag ["x", "<hash>"]
3a. Si trouvé → réutiliser CID, pin local, étendre upload_chain
3b. Si nouveau → upload IPFS, générer thumbnail + info.json
```

---

### Kind 1111 — Comment (Commentaire)

| Champ | Valeur |
|---|---|
| **Kind** | `1111` |
| **Nom de service** | Comment |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-22) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Media |

**Tags :**

```
["e", "<hex64-event-id-racine>", "<relay-url?>", "root"]
["e", "<hex64-event-id-parent?>", "<relay-url?>", "reply"]
["p", "<hex64-pubkey-auteur>"]
["k", "<kind-string-event-racine>"]
```

---

### Kind 1222 — Voice Message (Message vocal)

| Champ | Valeur |
|---|---|
| **Kind** | `1222` |
| **Nom de service** | Voice Message |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-A0) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Media |

**Description :** Message audio court (max 60 s). Deux modes : URL directe (public) ou payload NIP-44 chiffré (privé).

**Structure JSON — Mode public :** `content` = URL directe IPFS/HTTP  
**Structure JSON — Mode chiffré :** `content` = payload NIP-44

```json
{
  "url":       "/ipfs/QmXXX.../voice.m4a",
  "duration":  45,
  "waveform":  "0 7 35 8 100 ...",
  "latitude":  48.8566,
  "longitude": 2.3522
}
```

**Tags :**

```
["p",          "<hex64-pubkey-destinataire?>"]
["encrypted",  "true"]                           — Si chiffré NIP-44
["encryption", "nip44"]
["imeta",      "duration 45"]
["expiration", "<unix-timestamp?>"]
```

---

### Kind 1244 — Voice Message Reply

| Champ | Valeur |
|---|---|
| **Kind** | `1244` |
| **Nom de service** | Voice Message Reply |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-A0 + NIP-22) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Media |

**Tags :** Identiques à Kind 1222 + `["e", "<event-id-parent>", "", "reply"]`

---

### Kind 1337 — Code Snippet

| Champ | Valeur |
|---|---|
| **Kind** | `1337` |
| **Nom de service** | Code Snippet |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-C0) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | Selon configuration |

**Tags :**

```
["l",         "<langage>", "ISO-639-3"]    — ex: "python", "bash"
["extension", ".py"]
["license",   "MIT|AGPL-3.0|..."]
["repo",      "<url-repository?>"]
```

---

### Kind 1984 — Report (Signalement)

| Champ | Valeur |
|---|---|
| **Kind** | `1984` |
| **Nom de service** | Content Report |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-56) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/1984.sh` |
| **Sync constellation** | Non documenté |

**Description :** Signalement d'un contenu ou d'un utilisateur. Seuls les membres autorisés peuvent émettre des signalements.

**Tags :**

```
["p", "<hex64-pubkey-signalé>"]                — Obligatoire
["e", "<hex64-event-id-signalé?>"]             — Optionnel
["report-type", "<type>"]                       — Obligatoire
["reason",      "<texte-libre?>"]
```

**Types de signalement standard :**

| Type | Sévérité NIP-101 | Description |
|---|---|---|
| `illegal` | URGENT | Contenu illégal |
| `harassment` | URGENT | Harcèlement |
| `impersonation` | WARNING | Usurpation d'identité |
| `spam` | INFO | Spam |
| `fake` | INFO | Faux contenu |
| `scam` | WARNING | Arnaque |
| `phishing` | URGENT | Hameçonnage |

**Politique de filtrage NIP-101 :**

| Condition | Action |
|---|---|
| Pubkey signataire non autorisée | `reject` |
| Tags `p` ou `report-type` manquants | `reject` |
| Signalement valide | `accept` + log catégorisé |

**Log :** `~/.zen/tmp/nostr_reports.1984.log`

---

### Kind 1985 — User Video Tags

| Champ | Valeur |
|---|---|
| **Kind** | `1985` |
| **Nom de service** | User-Generated Video Tags |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-32 + NIP-71 extension) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Media |

**Description :** Tags communautaires apposés sur une vidéo (Kind 21/22). Agrégation en nuage de tags et recherche multi-critères (AND/OR).

**Tags :**

```
["L", "ugc"]
["l", "<tag-valeur>", "ugc"]
["e", "<hex64-event-id-video>", "<relay-url?>"]
["k", "21"]
```

---

### Kind 1986 — TMDB Metadata Enrichment

| Champ | Valeur |
|---|---|
| **Kind** | `1986` |
| **Nom de service** | Video Metadata Enrichment (TMDB) |
| **Type** | Regular |
| **Statut NIP** | UPLANET (NIP-71 extension) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Media |

**Description :** Corrections et enrichissements communautaires des métadonnées de vidéos via TMDB.

**Structure JSON — `content` :**

```json
{
  "tmdb": {
    "title":  "Titre corrigé",
    "year":   "2024",
    "genres": ["Action", "Sci-Fi"]
  },
  "reason": "Correction du titre"
}
```

**Tags :**

```
["e", "<hex64-event-id-video>", "<relay-url?>"]
["k", "21"]
["L", "tmdb.metadata"]
["l", "correction|enrichment|update|author_update", "tmdb.metadata"]
["p", "<hex64-pubkey-auteur-video>", "<relay-url?>"]
```

---

### Kind 9735 — Zap Receipt (Reçu Lightning)

| Champ | Valeur |
|---|---|
| **Kind** | `9735` |
| **Nom de service** | Lightning Zap Receipt |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-57) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/9735.sh` |
| **Sync constellation** | Non documenté |

**Description :** Reçu de paiement Lightning Network. Émis par le serveur LNURL du bénéficiaire après paiement.

**Structure JSON — `content` :** `""` (vide)

**Tags :**

```
["p",           "<hex64-pubkey-receveur>"]     — Obligatoire
["e",           "<hex64-event-id-zappé?>"]     — Optionnel
["bolt11",      "<invoice-lightning>"]          — Obligatoire
["description", "<json-zap-request>"]           — Obligatoire
["preimage",    "<hex-preimage?>"]              — Optionnel
["amount",      "<int-millisatoshis?>"]
```

**Politique de filtrage NIP-101 :**

| Condition | Action |
|---|---|
| Tags `p`, `bolt11`, `description` manquants | `reject` |
| Bénéficiaire non-membre UPlanet | `reject` |
| Tous cas valides | `accept` + log |

**Log :** `~/.zen/tmp/nostr_zaps.9735.log`

---

### Kind 21 — Short Video

| Champ | Valeur |
|---|---|
| **Kind** | `21` |
| **Nom de service** | Short Video |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-71) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/21.sh` |
| **Sync constellation** | OUI — Media |

**Description :** Post vidéo standard. Contient les métadonnées de la vidéo, son URL (IPFS ou HTTP), et les informations de géolocalisation.

**Structure JSON — `content` :** Description/notes de la vidéo (texte libre)

**Tags :**

```
["title",        "<titre-video>"]
["summary",      "<description?>"]
["published_at", "<unix-timestamp?>"]
["duration",     "<int-secondes?>"]
["imeta",
  "dim WIDTHxHEIGHT",
  "url /ipfs/<CID>/video.mp4",
  "x <sha256-hash>",
  "m video/mp4",
  "image /ipfs/<CID-thumb>",
  "gifanim /ipfs/<CID-gif>"
]
["thumbnail_ipfs", "<CID-jpeg?>"]
["gifanim_ipfs",   "<CID-gif-1.6s?>"]
["info",           "<CID-info-json?>"]
["upload_chain",   "<pubkey1,pubkey2?>"]
["g",              "<lat,lon?>"]
["latitude",       "<float?>"]
["longitude",      "<float?>"]
["location",       "<description-lieu?>"]
["application",    "UPlanet"]
["t",              "<hashtag>"]
```

**Structure `info.json` (IPFS) :**

```json
{
  "file":  { "name": "video.mp4", "size": 52428800, "type": "video/mp4", "hash": "<sha256>" },
  "ipfs":  { "cid": "<CID>", "url": "/ipfs/<CID>/video.mp4", "date": "2026-01-07 14:30 +0000" },
  "media": {
    "duration":       123.456,
    "dimensions":     "1920x1080",
    "video_codecs":   "h264",
    "audio_codecs":   "aac",
    "thumbnail_ipfs": "<CID>",
    "gifanim_ipfs":   "<CID>"
  }
}
```

**Classification automatique NIP-101 :**

| Dimension | Qualité détectée |
|---|---|
| ≥ 1280×720 | HD |
| ≥ 640×360 | SD |
| < 640×360 | Low |

| Durée | Catégorie |
|---|---|
| ≤ 30 s | Short |
| ≤ 300 s | Medium |
| > 300 s | Long |

**Types détectés :** `webcam`, `youtube_dl`, `obs_recording`, `mobile_capture`, `screen_recording`

**Politique de filtrage NIP-101 :** Toujours `accept`. Log détaillé + mise à jour stats.

**Logs :** `~/.zen/tmp/nostr_video_events.log`, `~/.zen/tmp/nostr_video_stats.json`

---

### Kind 22 — Long Video

| Champ | Valeur |
|---|---|
| **Kind** | `22` |
| **Nom de service** | Long Video |
| **Type** | Regular |
| **Statut NIP** | DRAFT (NIP-71) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/22.sh` |
| **Sync constellation** | OUI — Media |

**Description :** Identique à Kind 21 avec catégorisation durée étendue et analyse de complexité de contenu.

**Catégories durée étendues :**

| Durée | Catégorie |
|---|---|
| ≤ 600 s | Medium |
| ≤ 1800 s | Long |
| > 1800 s | Extended |

**Types étendus :** `extended_webcam`, `long_youtube`, `extended_obs`, `live_stream`, `educational`, `presentation`

**Complexité de contenu :** `simple`, `detailed`, `extensive`, `structured`

**Logs :** `~/.zen/tmp/nostr_long_video_events.log`, `~/.zen/tmp/nostr_long_video_stats.json`

---

## 6. Registre — Classe REPLACEABLE (10000–19999)

> Analogie : état utilisateur persistant. Un seul événement valide par `(kind, pubkey)`.

---

### Kind 10063 — Blossom Server List

| Champ | Valeur |
|---|---|
| **Kind** | `10063` |
| **Nom de service** | Blossom Media Server List |
| **Type** | Replaceable |
| **Statut NIP** | DRAFT (NIP-B7) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | Selon configuration |

**Tags :**

```
["server", "<url-blossom-server>"]    — Un tag par serveur (multiple)
```

**Usage :** Résolution `/<sha256>` pour récupérer le fichier sur les serveurs Blossom de l'utilisateur.

---

### Kind 10050 — DM Relay List

| Champ | Valeur |
|---|---|
| **Kind** | `10050` |
| **Nom de service** | DM Relay Preferences |
| **Type** | Replaceable |
| **Statut NIP** | DRAFT (NIP-17) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | Selon configuration |

**Description :** Liste des relays sur lesquels l'utilisateur souhaite recevoir ses messages privés chiffrés (Kind 1059).

**Tags :**

```
["relay", "<wss-relay-uri>"]    — Un tag par relay (multiple)
```

---

## 7. Registre — Classe ÉPHÉMÈRE (20000–29999)

> Analogie : datagrammes UDP sans stockage. Les relays relaient mais ne persistent pas.

---

### Kind 22242 — Auth Challenge / Twin-Key Auth

| Champ | Valeur |
|---|---|
| **Kind** | `22242` |
| **Nom de service** | Relay Authentication / Twin-Key Auth |
| **Type** | Ephemeral |
| **Statut NIP** | DRAFT (NIP-42 + UPlanet Twin-Key extension) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/22242.sh` |
| **Sync constellation** | Non (éphémère) |

**Description :** Authentification au relay NOSTR. UPlanet étend NIP-42 avec le système **Twin-Key** : chaque utilisateur possède une clé géographique dérivée de ses coordonnées UMAP, permettant une authentification spatiale.

**Structure — Authentification personnelle :**

```json
{
  "kind": 22242,
  "pubkey": "<hex64-user>",
  "tags": [
    ["relay",       "wss://relay.copylaradio.com"],
    ["challenge",   "<string-challenge-relay>"],
    ["did",         "did:nostr:<hex64-user>"],
    ["umap",        "43.60,1.44"],
    ["application", "UPlanet"]
  ]
}
```

**Structure — Authentification UMAP (clé géographique) :**

```json
{
  "kind": 22242,
  "pubkey": "<hex64-UMAP-clé-dérivée>",
  "tags": [
    ["relay",      "wss://relay.copylaradio.com"],
    ["challenge",  "<string-challenge-relay>"],
    ["p",          "<hex64-user>"],
    ["g",          "spey6"],
    ["latitude",   "43.60"],
    ["longitude",  "1.44"],
    ["grid_level", "UMAP"]
  ]
}
```

**Dérivation des clés Twin-Key :**

```bash
# Clé utilisateur
nostr_key  = keygen -t nostr "${EMAIL_SALT}" "${CAPTAIN_PEPPER}"
g1_key     = keygen -t duniter "${EMAIL_SALT}" "${CAPTAIN_PEPPER}"
ipfs_key   = keygen -t ipfs "${EMAIL_SALT}" "${CAPTAIN_PEPPER}"

# Clés géographiques
UMAP_key   = keygen -t nostr "UPlanetV1${LAT_0.01}" "UPlanetV1${LON_0.01}"
SECTOR_key = keygen -t nostr "UPlanetV1${LAT_0.1}"  "UPlanetV1${LON_0.1}"
REGION_key = keygen -t nostr "UPlanetV1${LAT_1.0}"  "UPlanetV1${LON_1.0}"
```

**Schéma SSSS (Shamir Secret Sharing) :**

```
Seed DISCO = "/?${EMAIL}=${SALT}&nostr=${PEPPER}"
  ├─ Part HEAD   → Utilisateur (dans QR MULTIPASS)
  ├─ Part MIDDLE → Capitaine (stockage séquestre)
  └─ Part TAIL   → UPlanet (reconstruction)

Reconstruction : HEAD + TAIL suffisent (2-sur-3)
QR MULTIPASS : "M-{SSSS_HEAD_B58}:{NOSTRNSEC}"
```

---

## 8. Registre — Classe ADRESSABLE (30000–39999)

> Analogie : services persistants adressés par `(kind, pubkey, d-tag)`. Équivalent des DNS records ou des entrées de base de données identifiées.

---

### Kind 30008 — Profile Badges

| Champ | Valeur |
|---|---|
| **Kind** | `30008` |
| **Nom de service** | Profile Badge Showcase |
| **Type** | Addressable |
| **Statut NIP** | DRAFT (NIP-58) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Oracle |

**Tags :**

```
["d", "profile_badges"]
["a", "30009:<hex64-issuer>:<d-tag-badge>", "<relay-url?>"]   — Badge accepté
["e", "<hex64-award-event-id>", "<relay-url?>"]                — Réf. événement kind 8
```

---

### Kind 30009 — Badge Definition

| Champ | Valeur |
|---|---|
| **Kind** | `30009` |
| **Nom de service** | Badge Definition |
| **Type** | Addressable |
| **Statut NIP** | DRAFT (NIP-58) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Oracle |

**Description :** Définition d'un badge avec icône, description et critères d'attribution. Dans UPlanet, les badges correspondent à des compétences certifiées par le système Oracle.

**Tags :**

```
["d",          "<badge-slug>"]                             — ex: "ore_verifier"
["name",       "<nom-badge>"]
["description","<description>"]
["image",      "<url-image-1024x1024>", "1024x1024"]
["thumb",      "<url-miniature-256x256?>", "256x256"]
["permit_id",  "<PERMIT_XXX?>"]                           — Lien Oracle UPlanet
["t",          "uplanet"]
["t",          "oracle"]
```

**Niveaux de maîtrise WoTx2 :**

| Niveau | Attestations | Badge | Description |
|---|---|---|---|
| X1–X4 | 1–4 | Bronze/Cuivre | Apprenti |
| X5–X10 | 5–10 | Argent | Expert |
| X11–X50 | 11–50 | Or | Maître |
| X51–X100 | 51–100 | Platine/Diamant | Grand Maître |
| X101+ | 101+ | Arc-en-ciel | Maître Absolu |

---

### Kind 30023 — Long-form Content (Article)

| Champ | Valeur |
|---|---|
| **Kind** | `30023` |
| **Nom de service** | Long-form Article / Blog Post |
| **Type** | Addressable |
| **Statut NIP** | DRAFT (NIP-23) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/30023.sh` |
| **Sync constellation** | OUI — Core |

**Description :** Article long format avec markdown. Identifié par `d-tag` pour l'adressabilité (mise à jour sans changer l'identifiant).

**Structure JSON — `content` :** Texte en markdown

**Tags :**

```
["d",            "<slug-article>"]               — Identifiant unique (obligatoire)
["title",        "<titre>"]
["summary",      "<resume?>"]
["image",        "<url-image-couverture?>"]
["published_at", "<unix-timestamp?>"]
["t",            "<hashtag>"]
["a",            "<30023:pubkey:d-tag?>"]         — Article précédent (révision)
```

**Politique de filtrage NIP-101 :**

| Condition | Action |
|---|---|
| Pubkey `nobody` | `reject` |
| Pubkey `uplanet` ou `amisOfAmis` | `accept` + log `BLOG` |

---

### Kind 30078 — Application-specific Data

| Champ | Valeur |
|---|---|
| **Kind** | `30078` |
| **Nom de service** | App-Specific Addressable Data |
| **Type** | Addressable |
| **Statut NIP** | DRAFT (NIP-78) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/30078.sh` |
| **Sync constellation** | Selon configuration |

**Tags :**

```
["d", "<app-identifier>"]    — Identifiant applicatif
```

**Contenu :** JSON arbitraire défini par l'application

---

### Kind 30303 — Custom Relay Data

| Champ | Valeur |
|---|---|
| **Kind** | `30303` |
| **Nom de service** | Custom Relay Data |
| **Type** | Addressable |
| **Statut NIP** | UPLANET |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/30303.sh` |
| **Sync constellation** | Selon configuration |

---

### Kind 30312 — ORE Meeting Space (Espace de réunion environnemental)

| Champ | Valeur |
|---|---|
| **Kind** | `30312` |
| **Nom de service** | ORE Meeting Space |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 ORE System) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — ORE |

**Description :** Espace de réunion géographique persistant pour les vérifications ORE (Obligations Réelles Environnementales). Ancré sur des coordonnées géographiques précises.

**Structure JSON — `content` :**

```json
{
  "description": "Espace géographique persistant pour vérification ORE",
  "vdo_url":    "https://vdo.ninja/?room=UMAP_ORE_43.60_1.44",
  "contractId": "ORE-2025-001",
  "provider":   "did:nostr:<hex64-verifier>"
}
```

**Tags :**

```
["d",    "ore-space-{lat}-{lon}"]           — Identifiant géographique
["g",    "{lat},{lon}"]                     — Coordonnées
["room", "UMAP_ORE_{lat}_{lon}"]            — Salle de réunion VDO
["t",    "uplanet"]
["t",    "ore-space"]
```

---

### Kind 30313 — ORE Verification Meeting (Réunion de vérification ORE)

| Champ | Valeur |
|---|---|
| **Kind** | `30313` |
| **Nom de service** | ORE Verification Meeting |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 ORE System) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — ORE |

**Description :** Compte-rendu d'une vérification de conformité environnementale. Signé par l'expert détenteur du permis `PERMIT_ORE_V1`.

**Structure JSON — `content` :**

```json
{
  "result":   "compliant|non-compliant|pending",
  "evidence": "ipfs://Qm...",
  "method":   "satellite_imagery|field_visit|document_review",
  "notes":    "Couverture forestière : 82%"
}
```

**Tags :**

```
["d",      "ore-verification-{lat}-{lon}-{unix-timestamp}"]
["a",      "30312:<hex64-authority>:ore-space-{lat}-{lon}"]    — Espace source
["g",      "{lat},{lon}"]
["start",  "<unix-timestamp>"]
["permit", "PERMIT_ORE_V1"]                                    — Obligatoire
```

---

### Kind 30500 — Permit Definition (Définition de permis)

| Champ | Valeur |
|---|---|
| **Kind** | `30500` |
| **Nom de service** | Oracle Permit Definition |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 Oracle) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/30500.sh` |
| **Sync constellation** | OUI — Oracle |

**Description :** Définition d'un type de compétence certifiable dans le système Oracle UPlanet. Constitue le registre décentralisé des qualifications reconnues par la coopérative.

**Structure JSON — `content` :**

```json
{
  "id":                "PERMIT_ORE_V1",
  "name":              "ORE Environmental Verifier",
  "description":       "Autorité pour vérifier les contrats ORE",
  "skill_tag":         "ore-verifier",
  "min_attestations":  5,
  "valid_duration_days": 1095,
  "reward_zen":        10
}
```

**Tags :**

```
["d",                "<PERMIT_ID>"]                           — Obligatoire
["t",                "permit"]
["t",                "auto_proclaimed|composite"]             — Type de permis
["requires",         "<skill_name>", "<min_level>"]           — Pour composites
["min_attestations", "<int>"]
["valid_duration_days", "<int>"]
["r",                "<url-ressource-formation?>", "document|video|link"]
```

**Catalogue des permis UPlanet définis :**

| Identifiant | Nom | Attestations min | Validité | Récompense |
|---|---|---|---|---|
| `PERMIT_ORE_V1` | ORE Environmental Verifier | 5 | 3 ans | 10 Ẑ |
| `PERMIT_DRIVER` | Driver's License | 12 | 15 ans | 5 Ẑ |
| `PERMIT_WOT_DRAGON` | UPlanet Authority | 3 | Illimitée | 50 Ẑ |
| `PERMIT_MEDICAL_FIRST_AID` | First Aid | 8 | 2 ans | 8 Ẑ |
| `PERMIT_BUILDING_ARTISAN` | Artisan Bâtiment | 10 | 5 ans | 12 Ẑ |
| `PERMIT_EDUCATOR_COMPAGNON` | Compagnon Éducateur | 12 | Illimitée | 15 Ẑ |
| `PERMIT_FOOD_PRODUCER` | Producteur Alimentaire | 6 | 3 ans | 8 Ẑ |
| `PERMIT_MEDIATOR` | Médiateur | 15 | 5 ans | 20 Ẑ |

**Politique de filtrage NIP-101 :** Toujours `accept`. Log dans `~/.zen/tmp/nostr_kind30500.log`.

---

### Kind 30501 — Permit Request (Demande de permis)

| Champ | Valeur |
|---|---|
| **Kind** | `30501` |
| **Nom de service** | Oracle Permit Request |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 Oracle) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Oracle |

**Description :** Candidature d'un apprenti à l'obtention d'un permis. Déclenche le processus de certification WoTx2.

**Structure JSON — `content` :**

```json
{
  "statement": "Je déclare maîtriser la validation écologique ORE",
  "evidence":  "https://ipfs.io/ipfs/Qm..."
}
```

**Tags :**

```
["d",      "<uuid-request>"]          — Identifiant unique de la demande
["permit", "<PERMIT_ID>"]             — Type de permis demandé
["t",      "uplanet"]
```

**Processus WoTx2 — Règle A (auto-proclamation) :**

```
1. Apprenti publie Kind 30501
2. 3 pairs envoient Kind 7 "+" (tag t=wotx-review)
3. Apprenti signe Kind 30503 (auto-certification)
4. Oracle émet Kind 8 (badge)
```

**Processus WoTx2 — Règle B (endorsement pair) :**

```
1. Apprenti publie Kind 30501
2. 1 pair certifié X1+ publie Kind 30502
3. Apprenti monte de niveau immédiatement
4. Oracle émet Kind 8
```

---

### Kind 30502 — Permit Attestation (Attestation par les pairs)

| Champ | Valeur |
|---|---|
| **Kind** | `30502` |
| **Nom de service** | Oracle Peer Attestation / Formal Endorsement |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 Oracle — Règle B) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Oracle |

**Condition d'émission :** L'attestant doit lui-même posséder un permis valide de niveau X1 ou supérieur pour le même type de compétence.

**Structure JSON — `content` :**

```json
{
  "attestation_id": "att_xyz...",
  "statement":      "J'atteste de la compétence de cet apprenti",
  "signature":      "<schnorr-hex>",
  "date":           "2026-01-07T14:30:00Z"
}
```

**Tags :**

```
["d",               "<uuid-attestation>"]
["e",               "<hex64-event-id-request>"]    — Kind 30501 ciblé
["p",               "<hex64-pubkey-candidat>"]
["permit",          "<PERMIT_ID>"]
["attester_license","<credential-id>"]             — Preuve de qualification
```

---

### Kind 30503 — Permit Credential (Certificat auto-signé)

| Champ | Valeur |
|---|---|
| **Kind** | `30503` |
| **Nom de service** | Oracle Self-Signed Credential (W3C VC) |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 Oracle) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Oracle |

**Description :** Verifiable Credential W3C signé par l'apprenti lui-même après validation (Règle A ou B). Preuve portable et vérifiable de compétence.

**Structure JSON — `content` (W3C Verifiable Credential) :**

```json
{
  "@context":           "https://www.w3.org/2018/credentials/v1",
  "id":                 "urn:uuid:<uuid>",
  "type":               ["VerifiableCredential", "WoTx2Certificate"],
  "issuer":             "did:nostr:<hex64-apprenti>",
  "issuanceDate":       "2026-01-07T14:30:00Z",
  "expirationDate":     "2029-01-07T14:30:00Z",
  "credentialSubject": {
    "id":           "did:nostr:<hex64-apprenti>",
    "license":      "PERMIT_ORE_V1",
    "rule":         "A|B",
    "reviewsCount": 3
  }
}
```

**Tags :**

```
["d",      "<credential-id>"]
["l",      "<PERMIT_ID>", "permit_type"]
["p",      "<hex64-apprenti>"]
["e",      "<hex64-event-id-permit-definition>"]
["t",      "permit"]
["t",      "credential"]
["t",      "wotx2"]
```

---

### Kind 30504 — Training Resource (Ressource de formation)

| Champ | Valeur |
|---|---|
| **Kind** | `30504` |
| **Nom de service** | WoTx2 Training Resource |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 WoTx2) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Oracle |

**Description :** Ressource pédagogique communautaire associée à un type de permis. Peut référencer n'importe quel type de média.

**Structure JSON — `content` :**

```json
{
  "skill":         "ore-verifier",
  "resource_url":  "/ipfs/Qm.../formation.mp4",
  "resource_type": "video|audio|document|image|cours|lien"
}
```

**Tags :**

```
["d",     "training_{skill}_{unix-timestamp}"]
["t",     "<skill-tag>"]
["t",     "formation"]
["r",     "<url-ressource>", "<type>"]
["title", "<titre>"]
```

---

### Kind 30800 — DID Document (Document d'identité décentralisée)

| Champ | Valeur |
|---|---|
| **Kind** | `30800` |
| **Nom de service** | W3C Decentralized Identifier Document |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 DID) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Identity |

**Description :** Document d'identité décentralisée au format W3C DID, ancré sur l'écosystème UPlanet. Sert de point d'entrée unique pour l'identité numérique : clé NOSTR, wallet Ğ1, espace IPFS, coordonnées géographiques, credentials Oracle.

**Note :** Kind `30800` est choisi délibérément pour éviter le conflit avec NIP-53 (Live Event, kind `30311`).

**Structure JSON — `content` (W3C DID Document) :**

```json
{
  "@context": ["https://w3id.org/did/v1"],
  "id":       "did:nostr:<hex64-user>",
  "type":     ["UMAPGeographicCell|SECTORGeographicCell|REGIONGeographicCell"],
  "uplanetId": "<G1-pubkey-UPLANETNAME>",
  "geographicMetadata": {
    "coordinates": { "lat": 43.60, "lon": 1.44 },
    "precision":   "0.01"
  },
  "ipfsChain": {
    "current_cid":  "<CID-racine-secteur-courant>",
    "previous_cid": "<CID-racine-secteur-précédent>"
  },
  "verificationMethod": [{
    "id":                 "did:nostr:<hex64>#key-1",
    "type":               "Ed25519VerificationKey2020",
    "controller":         "did:nostr:<hex64>",
    "publicKeyMultibase": "z<base58btc>"
  }],
  "service": [
    { "id": "#ipfs-drive",  "type": "IPFSDrive",  "serviceEndpoint": "ipns://<ipfs>/<email>/APP" },
    { "id": "#g1-wallet",   "type": "Ğ1Wallet",   "serviceEndpoint": "g1:<g1-pubkey>" },
    { "id": "#nostr-relay", "type": "NostrRelay",  "serviceEndpoint": "wss://relay.copylaradio.com" }
  ],
  "verifiableCredential": ["<Kind-30503-credential-id>", "..."],
  "metadata": {
    "email":          "user@astroport.copylaradio.com",
    "contractStatus": "active",
    "created_at":     "2026-01-07T14:30:00Z"
  }
}
```

**Tags :**

```
["d",      "did"]                     — Clé d'adressabilité fixe
["t",      "uplanet"]
["t",      "did-document"]
["g",      "{lat},{lon}"]             — Position géographique
```

**Hiérarchie géographique UPlanet :**

| Niveau | Précision | Dimension approx. | Type DID |
|---|---|---|---|
| UMAP | 0.01° | ~1.2 km | `UMAPGeographicCell` |
| SECTOR | 0.1° | ~11 km | `SECTORGeographicCell` |
| REGION | 1.0° | ~111 km | `REGIONGeographicCell` |

---

### Kind 30850 — Station Economic Health Report

| Champ | Valeur |
|---|---|
| **Kind** | `30850` |
| **Nom de service** | Station Economic Health Report |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 Economic Health) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Economic |

**Description :** Rapport de santé économique d'une station Astroport, conforme aux standards de comptabilité SCIC (Société Coopérative d'Intérêt Collectif). Broadcasté périodiquement par chaque nœud.

**Tags principaux (45+ tags économiques) :**

```
["d",                      "economic-health"]
["constellation",          "<hex64-UPLANETG1PUB>"]
["station",                "<IPFSNODEID>"]
["g1pub",                  "<UPLANETG1PUB>"]

— Soldes wallets (en Ẑen)
["balance:cash",           "<float>"]
["balance:rnd",            "<float>"]
["balance:assets",         "<float>"]
["balance:capital",        "<float>"]

— Revenus
["revenue:multipass",      "<float>"]         — Location MULTIPASS
["revenue:zencard",        "<float>"]         — Location ZenCard (locataires UNIQUEMENT)
["revenue:total",          "<float>"]

— Coûts
["cost:paf",               "<float>"]         — Part Armateur
["cost:captain",           "<float>"]         — Part Capitaine

— Capacités
["capacity:multipass_used","<int>"]
["capacity:multipass_total","<int>"]
["capacity:zencard_renters","<int>"]          — Locataires (paient rent)
["capacity:zencard_owners", "<int>"]          — Sociétaires (capital)
["capacity:zencard_total",  "<int>"]

— Santé
["health:status",          "healthy|assets_solidarity|rnd_solidarity|volunteer"]
["health:resilience_level","<int 0-3>"]       — 0=Abondance, 1-3=Solidarité
["health:weeks_runway",    "<int>"]
```

**Distinction critique — ZenCard :**

| Statut | Fichier | Contribution | Revenus station |
|---|---|---|---|
| Locataire | Aucun `U.SOCIETY` | 4 Ẑ/semaine (rent) | OUI |
| Sociétaire | Fichier `U.SOCIETY` valide | Capital coopératif | NON (dividendes futurs) |

---

### Kind 30851 — ZEN Emission Proof (Preuve de paiement ẐEN)

| Champ | Valeur |
|---|---|
| **Kind** | `30851` |
| **Nom de service** | ZEN Emission Proof / OC Payment Record |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 Economic Health) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Economic |

**Description :** Preuve cryptographique d'une émission ẐEN déclenchée par une contribution OpenCollective. Sert de **source de vérité distribuée pour l'idempotence** : avant tout traitement, la station primaire interroge le relay local pour vérifier que la transaction n'a pas déjà été émise. Remplace le fichier `emission.log` local.

**Clé d'adressabilité `d` :**

```
oc-emission-{raw_email}:{amount}:{oc_created_at}
```

**Tags :**

```
["d",           "oc-emission-{raw_email}:{amount}:{oc_created_at}"]  — Clé d'adressabilité unique par TX OC
["t",           "uplanet"]
["t",           "oc-emission"]
["s",           "OK|FAIL"]          — Single-letter tag : filtrable via #s (NIP-01)
["email",       "<email-effectif>"] — MULTIPASS ciblé (peut différer de raw_email pour tiers labo/R&D)
["amount",      "<float>"]          — Montant EUR brut (issu de l'API OC)
["tier",        "<tier-slug>"]      — Slug OC du niveau de contribution
["constellation","<UPLANETG1PUB>"]  — Swarm d'appartenance
```

**Structure JSON — `content` :**

```json
{
  "email":         "user@example.com",
  "raw_email":     "user+alias@example.com",
  "amount":        25,
  "tier_slug":     "satellite",
  "oc_created_at": "2026-06-15T10:30:00.000Z",
  "status":        "OK",
  "generated_at":  "2026-06-30T20:12:00Z",
  "uplanet":       "<UPLANETG1PUB>"
}
```

**Politique d'idempotence :**

```
Avant traitement : strfry scan {"kinds":[30851], "#d":["oc-emission-TX_ID"]}
  → résultat non vide  → TX déjà traitée → skip
  → résultat vide      → TX nouvelle     → traiter + publier kind 30851
```

**Implémentation :** `OC2UPlanet/oc2uplanet.sh` — `_check_emission_nostr()` / `_publish_emission_proof()`  
**Backup :** `OC2UPlanet/data/emission.log` — écriture parallèle (fallback si relay hors-ligne)

---

### Kind 30904 — Crowdfunding Campaign (Campagne de financement)

| Champ | Valeur |
|---|---|
| **Kind** | `30904` |
| **Nom de service** | Commons Crowdfunding Campaign |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-75 extension) |
| **Filtre NIP-101** | `relay.writePolicy.plugin/filter/30904.sh` |
| **Sync constellation** | OUI — Economic |

**Description :** Campagne de financement participatif d'un bien commun (terrain, bâtiment, outil coopératif). Intègre deux modes de propriétaires : donation au commun (`commons`) ou vente avec sortie en euros (`cash`).

**Tags :**

```
["d",         "crowdfund-{lat}-{lon}-{slug}"]
["title",     "<titre-campagne>"]
["g",         "<lat,lon>"]
["p",         "<hex64-UMAP-pubkey>", "", "umap"]
["project-id","CF-{YYYYMMDD}-{hex8}"]
["captain",   "<hex64-CAPTAIN-pubkey>"]

— Propriétaires
["owner", "<hex64-pubkey-A>", "commons", "<montant>", "ZEN"]
["owner", "<hex64-pubkey-B>", "cash",    "<montant>", "EUR"]

— Objectifs multi-devise
["goal", "ZEN_CONVERTIBLE", "<montant>", "0"]
["goal", "G1",              "<montant>", "0"]
["goal", "ZEN_COMMONS",     "<montant>", "0"]

— Wallets destinations
["wallet", "ASSETS",  "<G1-pubkey-actifs>"]
["wallet", "CAPITAL", "<G1-pubkey-capital>"]
["wallet", "G1",      "<G1-pubkey-UPLANETNAME>"]

["status",     "crowdfunding|funded|closed"]
["closed_at",  "<unix-timestamp?>"]
["governance", "majority|unanimous"]
["a",          "30023:<hex64>:<d-tag-doc?>"]    — Lien documentation
```

**Contribution via Kind 7 :**

```json
{
  "kind":    7,
  "content": "+100",
  "tags": [
    ["e",          "<hex64-event-id-campagne>"],
    ["p",          "<hex64-BIEN-pubkey>"],
    ["t",          "crowdfunding"],
    ["t",          "UPlanet"],
    ["project-id", "CF-20260107-A1B2C3D4"],
    ["target",     "ZEN_CONVERTIBLE"],
    ["i",          "g1pub:<G1-pubkey-bien>"]
  ]
}
```

**Politique de filtrage NIP-101 (30904.sh) :**

| Vérification | Action |
|---|---|
| Structure `project-id` invalide | `reject` |
| Wallet Bien non enregistré | Enregistrement dans `amisOfAmis` + `accept` |
| Structure valide | `accept` + `sync_crowdfunding_biens()` |

---

### Kind 31903 — Cookie Vault (Stockage de cookies chiffré)

| Champ | Valeur |
|---|---|
| **Kind** | `31903` |
| **Nom de service** | Cookie Vault |
| **Type** | Addressable |
| **Statut NIP** | UPLANET (NIP-101 Cookie Vault) |
| **Filtre NIP-101** | `all_but_blacklist.sh` |
| **Sync constellation** | OUI — Workflows |

**Description :** Stockage chiffré de cookies de navigation (format Netscape) sur IPFS. Permet à yt-dlp et aux outils d'extraction de fonctionner sans exposition des secrets en clair.

**Structure JSON — `content` :**

```json
{
  "cid":         "Qm...",
  "domain":      "youtube.com",
  "uploaded_at": "2026-01-07T14:30:00Z",
  "type":        "cookie"
}
```

**Tags :**

```
["d",           "cookie:{domain}"]       — Clé NIP-33
["t",           "cookie"]
["t",           "netscape_cookies"]
["domain",      "<domain>"]
["uploaded_at", "<iso8601>"]
```

**Chiffrement :** NaCl box avec clé publique G1 de l'utilisateur. Le CID pointe vers le blob chiffré sur IPFS.

---

## 9. Index des filtres writePolicy NIP-101

> Répertoire : `relay.writePolicy.plugin/filter/`

### Architecture de décision

```
strfry (stdin JSON)
        │
        ▼
all_but_blacklist.sh
        │
        ├─ is_key_blacklisted() ?  ──YES──► shadowReject
        │
        ├─ classify_user()
        │   ├─ LOCAL  : ~/.zen/game/nostr/*/HEX     → "uplanet"
        │   ├─ SWARM  : ~/.zen/tmp/swarm/*/TW/*/HEX → "player"
        │   ├─ AMIS   : ~/.zen/strfry/amisOfAmis.txt → "amisOfAmis"
        │   └─ ABSENT : (aucune liste)               → "nobody"
        │
        ├─ filter/{kind}.sh (si existant)
        │   └─ exit 0 → accept
        │   └─ exit 1 → reject
        │
        └─ stdout: {"id":"...", "action":"accept|reject|shadowReject"}
```

### Table des filtres actifs

| Fichier | Kind | Niveau min requis | Action par défaut | Log |
|---|---|---|---|---|
| `0.sh` | 0 — Profile | `nobody` (avec conditions) | `accept` | `nostr_kind0.log` |
| `1.sh` | 1 — Text Note | `nobody` (rate-limited) | `accept` conditionnel | `nostr_kind1_messages.log` |
| `7.sh` | 7 — Reaction | `amisOfAmis` | `accept` + paiement ZEN | `nostr_likes.log` |
| `21.sh` | 21 — Video | `nobody` | `accept` toujours | `nostr_video_events.log` |
| `22.sh` | 22 — Long Video | `nobody` | `accept` toujours | `nostr_long_video_events.log` |
| `1984.sh` | 1984 — Report | `uplanet` | `accept` catégorisé | `nostr_reports.1984.log` |
| `9735.sh` | 9735 — Zap | `uplanet` | `accept` validé | `nostr_zaps.9735.log` |
| `22242.sh` | 22242 — Auth | `amisOfAmis` | `accept` | — |
| `30023.sh` | 30023 — Article | `amisOfAmis` | `accept` | `strfry.log` |
| `30078.sh` | 30078 — AppData | `amisOfAmis` | `accept` | — |
| `30303.sh` | 30303 — Custom | `amisOfAmis` | `accept` | — |
| `30500.sh` | 30500 — Permit | `nobody` | `accept` toujours | `nostr_kind30500.log` |
| `30904.sh` | 30904 — Crowdfunding | `uplanet` | `accept` + enregistrement | — |

### Fonctions communes (`filter/common.sh`)

| Fonction | Description |
|---|---|
| `extract_event_data "$json"` | Positionne `$event_id`, `$pubkey`, `$content`, `$created_at` |
| `check_authorization "$pubkey"` | Retourne `$AUTHORIZED`, `$EMAIL`, `$SOURCE` |
| `extract_tags "$json" tag1 tag2` | Extraction multi-tags en un seul appel `jq` |
| `parse_zen_amount "$content"` | Extrait le montant numérique de `"+10"` etc. |
| `is_crowdfunding_bien "$pubkey"` | Vérifie si pubkey est un wallet Bien enregistré |
| `record_crowdfunding_contribution` | Journalise une contribution crowdfunding |
| `record_assets_vote` | Journalise un vote d'allocation d'actifs |
| `check_vote_threshold "$project_id"` | Vérifie si le seuil de vote est atteint |
| `check_memory_slot_access "$user" "$slot"` | Contrôle d'accès aux slots mémoire |
| `add_to_amis_of_amis "$pubkey"` | Ajoute à `~/.zen/strfry/amisOfAmis.txt` |
| `log_with_timestamp "$file" "$msg"` | Journalisation horodatée |

---

## 10. Matrice de synchronisation constellation

> Script : `backfill_constellation.sh`  
> Déclenchement : automatique via `_12345.sh` chaque jour après 12h00  
> Protocole : negentropy + WebSocket REQ fallback

### Kinds synchronisés par catégorie

| Catégorie | Kinds | Nb |
|---|---|---|
| **Core** | 0, 1, 3, 4*, 5, 6, 7 | 7 |
| **Media** | 21, 22, 1063, 1111 | 4 |
| **Voix** | 1222, 1244 | 2 |
| **Tags/Enrichissement** | 1985, 1986 | 2 |
| **Badges** | 8, 30008, 30009 | 3 |
| **Contenu long** | 30023, 30024 | 2 |
| **Identité** | 30800 | 1 |
| **Oracle WoTx2** | 30500, 30501, 30502, 30503, 30504 | 5 |
| **ORE Environnement** | 30312, 30313 | 2 |
| **Santé économique** | 30850, 30851 | 2 |
| **Workflows** | 31900, 31901, 31902, 31903 | 4 |
| **Crowdfunding** | 30904 | 1 |
| **TOTAL** | | **34+** |

`*` Kind 4 (DM) : optionnel, désactivable avec `--no-dms`

### Découverte des pairs

```
~/.zen/tmp/swarm/*/12345.json   ← Metadata IPNS de chaque station
~/.zen/game/nostr/*/HEX         ← Pubkeys MULTIPASS locaux
~/.zen/strfry/amisOfAmis.txt    ← Réseau de confiance étendu (N²)
```

### Algorithme N² (Amis des amis)

```
Station A publie amisOfAmis_A.txt  (N1 de ses utilisateurs)
Station B publie amisOfAmis_B.txt  (N1 de ses utilisateurs)
…

Chaque station :
  1. Télécharge amisOfAmis_*.txt de tous les pairs swarm
  2. Fusionne + déduplique → amisOfAmis.txt local
  3. Applique politique blacklist/whitelist :
     ┌─ pubkey dans blacklist ?
     │  ├─ OUI + dans amisOfAmis → ALLOW (retrait blacklist)
     │  └─ OUI + absent         → BLOCK
     └─ NON                     → ALLOW
```

### Tunnels IPFS P2P (services exposés)

| Protocole IPFS | Service | Port local |
|---|---|---|
| `/x/strfry-{NODEID}` | NOSTR Relay | 7777 |
| `/x/ssh-{NODEID}` | SSH | 22 |
| `/x/ollama-{NODEID}` | Ollama AI | 11434 |
| `/x/comfyui-{NODEID}` | ComfyUI | 8188 |
| `/x/orpheus-{NODEID}` | Orpheus TTS | 5005 |
| `/x/perplexica-{NODEID}` | Perplexica | 3001 |

---

## 11. Glossaire

| Terme | Définition |
|---|---|
| **amisOfAmis** | Fichier `~/.zen/strfry/amisOfAmis.txt` — liste des pubkeys du réseau de confiance étendu (amis des amis, N²) |
| **Bien** | Entité juridique ou wallet Ğ1 associé à un bien commun dans une campagne crowdfunding |
| **Capitaine (SUDO)** | Administrateur système d'une station Astroport |
| **Constellation** | Réseau fédéré de stations Astroport partageant une synchronisation NOSTR |
| **d-tag** | Tag `["d", "<valeur>"]` qui paramètre l'adressabilité d'un événement Replaceable |
| **DID** | Decentralized Identifier (W3C) — identifiant numérique décentralisé |
| **Ğ1 / G1** | June, monnaie libre sur Duniter v2s (blockchain Polkadot-based) |
| **IPNS** | InterPlanetary Name System — noms mutables sur IPFS |
| **MULTIPASS** | Carte d'identité numérique UPlanet (NOSTR + Ğ1 + IPFS liés par SSSS) |
| **Negentropy** | Protocole de synchronisation ensembliste efficace utilisé par strfry |
| **NODE (Armateur)** | Propriétaire du matériel d'une station |
| **NIP** | NOSTR Implementation Possibility — spécification du protocole NOSTR |
| **Oracle** | Système décentralisé de certification de compétences UPlanet |
| **ORE** | Obligation Réelle Environnementale — contrat juridique de protection écologique |
| **PAF** | Part d'Attribution Fondatrice — contribution économique minimale à la coopérative |
| **SECTOR** | Cellule géographique 0.1° × 0.1° (~11 km) dans la hiérarchie UPlanet |
| **SSSS** | Shamir's Secret Sharing Scheme — partage de secret en N parts, seuil k |
| **strfry** | Relay NOSTR haute performance en C++, basé sur LMDB |
| **UMAP** | Cellule géographique 0.01° × 0.01° (~1.2 km) dans la hiérarchie UPlanet |
| **VC** | Verifiable Credential (W3C) — attestation numérique vérifiable cryptographiquement |
| **WoTx2** | Web of Trust étendu — système de certification P2P à deux règles (A : réactions collectives, B : endorsement expert) |
| **Ẑen / ZEN** | Unité de compte interne coopérative (1 Ẑ ≈ 1 EUR en production, 0.1 Ğ1 en développement) |
| **ZenCard** | Carte de membre sociétaire UPlanet (128 Go Nextcloud + droits de vote) |

---

## Références

- **NIP-01** : [github.com/nostr-protocol/nostr/blob/master/01.md](https://github.com/nostr-protocol/nostr/blob/master/01.md) — Protocole de base
- **NIP-101** : `README.md` — Spécification NIP-101 UPlanet
- **CONSTELLATION_SYNC.md** : Synchronisation N² de la constellation
- **Astroport.ONE** : [github.com/papiche/Astroport.ONE](https://github.com/papiche/Astroport.ONE) — Orchestrateur
- **W3C DID Core** : [w3.org/TR/did-core/](https://www.w3.org/TR/did-core/)
- **W3C VC Data Model** : [w3.org/TR/vc-data-model/](https://www.w3.org/TR/vc-data-model/)
- **RFC 6335** : IANA Service Name and Transport Protocol Port Number Registry
- **strfry** : [github.com/hoytech/strfry](https://github.com/hoytech/strfry)

---

*Ce document est maintenu dans le dépôt `NIP-101`. Pour signaler une erreur ou proposer un amendement, ouvrir une issue sur `github.com/papiche/NIP-101`.*

---

**Fin du document · NIP-101/KIND-REG-1.0 · AGPL-3.0**
