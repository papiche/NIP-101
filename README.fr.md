# NIP-101 : Clés Géographiques Hiérarchiques UPlanet et Système de Tags

`brouillon` `optionnel`

Ce NIP décrit une méthode pour générer des paires de clés Nostr de manière déterministe basée sur des coordonnées géographiques et un espace de noms, créant des "GeoKeys" hiérarchiques. Il spécifie également les tags d'événements utilisés par l'application UPlanet pour associer des notes à des emplacements et niveaux de grille spécifiques.

## Résumé

UPlanet étend Nostr en permettant une communication géographiquement localisée. Il y parvient grâce à :

1.  **GeoKeys Hiérarchiques :** Les paires de clés Nostr (`npub`/`nsec`) sont dérivées d'une combinaison d'une chaîne d'espace de noms fixe (ex : "UPlanetV1") et de coordonnées géographiques formatées à des niveaux de précision spécifiques (ex : 0.01°, 0.1°, 1.0°). Cela crée des identités distinctes pour différentes cellules de grille géographique.
2.  **Tags Géographiques :** Les événements publiés en utilisant ces GeoKeys, ou référençant un emplacement, incluent des tags spécifiques (`latitude`, `longitude`) pour indiquer le point d'intérêt précis.
3.  **Tag d'Application :** Un tag `application` identifie les événements spécifiquement destinés à ou générés par le système UPlanet.

Cela permet aux utilisateurs et applications de s'abonner aux messages pertinents pour des zones géographiques spécifiques en connaissant le `npub` GeoKey correspondant ou en filtrant les événements basés sur les tags de localisation dans un certain rayon.

## Motivation

-   **Flux Localisés :** Créer des flux Nostr pertinents uniquement pour des quartiers spécifiques (UMAP), secteurs (SECTOR), ou régions (REGION).
-   **Géo-clôture :** Permettre aux applications de filtrer ou réagir aux événements se produisant dans des limites géographiques définies.
-   **Intégration Cartographique :** Fournir une couche d'événements Nostr qui peut être facilement affichée sur des cartes.
-   **Services Décentralisés Basés sur la Localisation :** Permettre la découverte et l'interaction basées sur la proximité sans dépendre de serveurs centralisés.
-   **Contexte Spécifique à l'Application :** Le tag `application` permet de distinguer les messages UPlanet du trafic Nostr général.

## Modèle d'Identité et de Stockage Unifié d'UPlanet

Ce NIP décrit comment UPlanet intègre les identités Nostr avec le stockage IPFS, en s'appuyant sur la dérivation de clés géographiques.

### Authentification via NIP-42

Les services UPassport (`54321.py`) utilisent Nostr pour l'authentification des utilisateurs pour les opérations privilégiées telles que le téléchargement, la suppression et la synchronisation de fichiers. Cela est réalisé par :

1.  **Événement d'Authentification Côté Client :** Lorsqu'un utilisateur tente une action privilégiée, son interface web UPlanet (ou client) interagit avec une extension Nostr ([NIP-07](https://github.com/nostr-protocol/nips/blob/master/07.md)) ou directement avec son `nsec` pour signer un événement de `kind: 22242` ([NIP-42: Authentification](https://github.com/nostr-protocol/nips/blob/master/42.md)). Cet événement affirme la clé publique de l'utilisateur (`pubkey`) et inclut typiquement un tag `relay` indiquant le relais auquel il a été envoyé, et un tag `challenge`.
2.  **Vérification Côté Serveur :** Le backend UPlanet UPassport (`54321.py`) se connecte à un relais Nostr local (ex : `ws://127.0.0.1:7777`). En recevant une requête authentifiée d'un utilisateur (`npub`), le backend interroge le relais pour les événements `kind: 22242` récents (ex : dernières 24 heures) créés par ce `npub`. Si un événement valide et récent est trouvé, l'identité de l'utilisateur est authentifiée. Ce mécanisme garantit que l'utilisateur est bien le propriétaire du `npub` sans que le serveur ne détienne jamais la clé privée.

### Mécanisme de Clés Jumelles et Propriété du Drive IPFS

L'innovation principale d'UPlanet réside dans son mécanisme "Clés Jumelles", qui lie inextricablement l'identité Nostr d'un utilisateur à son drive IPFS personnel et autres actifs numériques (G1, clés Bitcoin, comme décrit dans la Spécification 1: Dérivation GeoKey).

-   **Association Déterministe du Drive :** Chaque utilisateur UPlanet est associé à un drive IPFS unique situé dans son répertoire personnel (ex : `~/.zen/game/nostr/<user_email>/APP`). Le fichier `manifest.json` dans ce drive enregistre explicitement l'`owner_hex_pubkey`.
-   **Application de la Propriété :**
    -   Lorsqu'un utilisateur tente de modifier son drive IPFS (téléchargement, suppression de fichiers), le backend UPlanet vérifie que son `npub` Nostr authentifié (converti en `hex_pubkey`) correspond à l'`owner_hex_pubkey` déclaré dans le `manifest.json` du drive cible.
    -   Si le `npub` correspond, l'opération se poursuit et le drive IPFS est régénéré, produisant un nouveau CID.
    -   Si le `npub` ne correspond pas (c'est-à-dire un "drive étranger"), les opérations d'écriture sont strictement interdites. Cependant, les utilisateurs peuvent "synchroniser" des fichiers d'un drive étranger vers leur *propre* drive authentifié, copiant effectivement le contenu public.
-   **Contenu IPFS Structuré :** Contrairement au stockage de blobs générique, UPlanet organise les fichiers dans une structure hiérarchique dans le drive IPFS (`Images/`, `Music/`, `Videos/`, `Documents/`), et génère une interface web lisible par l'homme (`_index.html`) pour l'exploration. Cela fournit une expérience "drive" conviviale plutôt qu'un simple accès aux blobs bruts.

### Comparaison avec le Stockage de Blobs Générique (ex : Blossom)

Bien qu'il partage l'utilisation fondamentale de Nostr pour l'authentification, UPlanet se différencie des spécifications de stockage de blobs basées sur Nostr plus génériques comme [Blossom](https://github.com/hzrd149/blossom) (BUDs) dans sa portée et son approche :

-   **Blossom :** Se concentre sur une API HTTP de bas niveau pour stocker et récupérer des "blobs" arbitraires adressés par des hachages SHA256 sur des serveurs de médias. C'est un bloc de construction fondamental pour la distribution de contenu sur Nostr.
-   **UPlanet :** Opère à un niveau d'application plus élevé. C'est un système de "Drive IPFS Personnel" structuré qui *utilise* IPFS pour le stockage et *utilise* Nostr pour l'identité et l'authentification. Son mécanisme "Clés Jumelles" (GeoKeys NIP-101 et autres clés associées) fournit une identité holistique et unifiée à travers les données géographiques, le contenu IPFS, et potentiellement d'autres actifs blockchain. Il fournit une expérience utilisateur complète avec une interface web pré-construite et des fonctionnalités spécifiques comme les mises à jour incrémentales et l'organisation de contenu structuré.

### Relais Nostr Dédié avec Strfry et Filtres Personnalisés

UPlanet utilise un relais Nostr `strfry` dédié, configuré avec des politiques d'écriture personnalisées pour s'intégrer de manière transparente à l'écosystème UPlanet, permettant des actions authentifiées et des réponses pilotées par l'IA.

#### 1. Compilation et Installation de Strfry (`install_strfry.sh`)

Le script `install_strfry.sh` automatise la configuration du relais Nostr `strfry` :

*   **Installation des Dépendances :** Il s'assure que toutes les dépendances système nécessaires (ex : `git`, `g++`, `make`, `libssl-dev`, `liblmdb-dev`) sont installées sur les systèmes basés sur Debian/Ubuntu.
*   **Gestion des Sources :** Le script clone le dépôt `strfry` depuis GitHub dans `~/.zen/workspace/strfry` ou le met à jour s'il est déjà présent.
*   **Compilation :** Il compile `strfry` depuis les sources, garantissant les dernières fonctionnalités et optimisations.
*   **Installation :** Le binaire `strfry` compilé et sa configuration `strfry.conf` par défaut sont copiés dans `~/.zen/strfry/`, avec la configuration adaptée pour un accès réseau plus large (`bind = "0.0.0.0"`). Cette configuration permet à `strfry` d'être un relais local dédié à l'instance UPlanet.

#### 2. Installation et Configuration Systemd (`setup.sh`)

Après la compilation de `strfry`, le script `setup.sh` configure le relais `strfry` et le prépare pour la gestion Systemd :

*   **Génération de Configuration :** Il génère dynamiquement le fichier `strfry.conf` dans `~/.zen/strfry/strfry.conf` basé sur les variables de l'environnement UPlanet (ex : `UPLANETG1PUB`, `IPFSNODEID`, `CAPTAINHEX`, `CAPTAINEMAIL`).
*   **Informations du Relais :** Le `strfry.conf` inclut les métadonnées NIP-11 telles que le `name` du relais (ex : "♥️BOX `IPFSNODEID`"), la `description` (soulignant son rôle dans UPlanet), la `pubkey` (la clé publique du Capitaine UPlanet pour l'administration), et une URL d'`icon`.
*   **Plugin de Politique d'Écriture :** Crucialement, il définit le paramètre `writePolicy.plugin` dans `strfry.conf` pour pointer vers `"$HOME/.zen/workspace/NIP-101/relay.writePolicy.plugin/all_but_blacklist.sh"`. Cela délègue la logique d'acceptation/rejet d'événements à un script personnalisé, permettant les règles de filtrage spécifiques d'UPlanet.

#### 3. Filtres Spécifiques et Intégration IA

Le relais d'UPlanet implémente plusieurs couches de filtrage pour gérer les événements et déclencher des réponses IA :

*   **`relay.writePolicy.plugin/all_but_blacklist.sh` (Politique d'Écriture Principale) :**
    *   C'est le script principal exécuté par `strfry` pour chaque événement entrant.
    *   Sa fonction principale est d'implémenter une politique "liste blanche par défaut, avec exceptions de liste noire" : il accepte tous les événements sauf si la `pubkey` de l'auteur de l'événement est trouvée dans `~/.zen/strfry/blacklist.txt`.
    *   Pour les événements `kind 1` (texte), il appelle dynamiquement `filter/1.sh` pour appliquer une logique plus spécifique liée à UPlanet.
    *   Les événements de clés publiques blacklistées sont immédiatement rejetés.

*   **`relay.writePolicy.plugin/filter/1.sh` (Filtre d'Événements Kind 1) :**
    *   Ce script gère spécifiquement les événements Nostr `kind 1`, qui sont principalement des notes de texte.
    *   **Gestion des Visiteurs :** Pour les `pubkey` non enregistrées comme "joueurs" UPlanet, il implémente un mécanisme "Hello NOSTR visitor". Les nouveaux visiteurs reçoivent un message d'avertissement de la clé du Capitaine UPlanet, expliquant le système et limitant le nombre de messages qu'ils peuvent envoyer avant d'être blacklistés. Cela encourage les utilisateurs à rejoindre la Web of Trust UPlanet.
    *   **Gestion de la Mémoire :** Il utilise `short_memory.py` pour stocker l'historique des conversations pour les joueurs Nostr, permettant à l'IA de maintenir le contexte.
    *   **Déclenchement IA :** Il agit comme un orchestrateur pour le script `UPlanet_IA_Responder.sh`. Si `UPlanet_IA_Responder.sh` est déjà en cours d'exécution, il met en file d'attente les messages entrants (surtout ceux avec les tags `#BRO` ou `#BOT`) pour éviter de submerger l'IA. Si l'IA n'est pas active, il invoque directement `UPlanet_IA_Responder.sh` avec un timeout.

*   **`Astroport.ONE/IA/UPlanet_IA_Responder.sh` (Backend IA) :**
    *   C'est le script de logique IA principal, responsable de générer des réponses basées sur les messages `kind 1` entrants, typiquement déclenchés par `filter/1.sh`.
    *   **Actions Basées sur les Tags :** Il analyse des hashtags spécifiques dans le contenu du message pour déclencher diverses fonctionnalités IA :
        *   `#search` : Intègre avec un moteur de recherche (ex : Perplexica) pour récupérer des informations.
        *   `#image` : Commande une IA de génération d'images (ex : ComfyUI) pour créer des images basées sur le prompt.
        *   `#video` : Utilise des modèles texte-vers-vidéo (ex : ComfyUI) pour générer de courts clips vidéo.
        *   `#music` : Déclenche la génération de musique.
        *   `#youtube` : Télécharge des vidéos YouTube (ou extrait l'audio avec le tag `#mp3`) via `process_youtube.sh`.
        *   `#pierre` / `#amelie` : Convertit le texte en parole en utilisant des modèles de voix spécifiques (ex : Orpheus TTS).
        *   `#mem` : Affiche l'historique de conversation actuel.
        *   `#reset` : Efface la mémoire de conversation de l'utilisateur.
    *   **Intégration Ollama :** Pour les questions générales sans tags spécifiques, il utilise Ollama avec un script `question.py` conscient du contexte pour générer des réponses IA conversationnelles, exploitant la mémoire stockée.
    *   **Publication des Réponses :** Les réponses générées par l'IA sont signées par la clé du Capitaine UPlanet (ou la clé `KNAME` si spécifiée et disponible) et publiées de retour sur le relais Nostr comme événements `kind 1`, taguant spécifiquement l'événement original et la clé publique pour maintenir le contexte de fil (`tags `e` et `p`).

Ce système intégré permet à UPlanet de fournir une expérience dynamique et interactive où les actions et requêtes des utilisateurs sur Nostr peuvent déclencher des opérations IA complexes et la génération de contenu, tout en maintenant l'intégrité et le modèle de propriété des drives IPFS.

### Tags de Contrôle de Mémoire

UPlanet implémente un système de mémoire conscient de la vie privée où les utilisateurs ont un contrôle explicite sur ce qui est stocké dans leur historique de conversation IA :

-   **`#rec` (Enregistrer) :** Ce tag est **requis** pour que tout message soit stocké dans la mémoire IA. Les messages sans ce tag sont traités normalement mais ne sont pas enregistrés pour le contexte futur. Cela fournit aux utilisateurs un contrôle granulaire sur leur vie privée et l'utilisation du stockage.

-   **`#mem` (Mémoire) :** Affiche l'historique de conversation actuel sans enregistrer le message actuel. Cela permet aux utilisateurs de consulter leurs conversations stockées sans ajouter de nouvelles entrées.

-   **`#reset` (Réinitialiser) :** Efface la mémoire de conversation de l'utilisateur, fournissant un nouveau départ pour les interactions IA.

**Exemple d'Utilisation :**
```
# Message sera traité mais PAS stocké en mémoire
"Bonjour, comment allez-vous ?"

# Message sera traité ET stocké en mémoire pour le contexte futur
"Bonjour, comment allez-vous ? #rec"

# Message affichera la mémoire actuelle sans enregistrer ce message
"Montre-moi notre historique de conversation #mem"

# Message effacera toute la mémoire stockée
"Efface notre conversation #reset"
```

Cette approche garantit que les utilisateurs maintiennent un contrôle total sur leur empreinte numérique tout en bénéficiant d'interactions IA contextuelles quand ils le souhaitent.

### Utilisation de la Mémoire dans les Réponses IA

Le script `UPlanet_IA_Responder.sh` utilise la mémoire stockée de plusieurs façons pour fournir des réponses IA contextuelles :

#### 1. Affichage de la Mémoire (tag `#mem`)
Lorsqu'un utilisateur inclut le tag `#mem`, le script :
- Charge l'historique de conversation de l'utilisateur depuis `~/.zen/strfry/uplanet_memory/pubkey/{pubkey}.json`
- Formate les 30 derniers messages avec des timestamps et du contenu nettoyé (suppression des tags #BOT/#BRO)
- Retourne un historique de conversation lisible par l'homme sans enregistrer le message actuel

#### 2. Réinitialisation de la Mémoire (tag `#reset`)
Lorsqu'un utilisateur inclut le tag `#reset`, le script :
- Supprime complètement le fichier de mémoire de l'utilisateur
- Retourne un message de bienvenue expliquant les fonctionnalités IA disponibles
- Fournit un nouveau départ pour les interactions IA

#### 3. Réponses IA Contextuelles (Comportement par défaut)
Pour les questions générales sans tags spécifiques, le script :
- Appelle `question.py` avec le paramètre `pubkey` de l'utilisateur
- `question.py` charge l'historique de conversation depuis le fichier de mémoire de l'utilisateur
- Construit un prompt conscient du contexte incluant les messages précédents
- Envoie le prompt amélioré à Ollama pour la génération de réponse IA
- Enregistre à la fois le prompt et la réponse dans `~/.zen/tmp/IA.log`

#### 4. Structure et Accès à la Mémoire
Le système de mémoire fournit deux types de contexte :

**Mémoire Utilisateur (`pubkey/{pubkey}.json`) :**
```json
{
  "pubkey": "clé_publique_utilisateur",
  "messages": [
    {
      "timestamp": "2024-01-01T12:00:00Z",
      "event_id": "hash_événement",
      "latitude": "48.8534",
      "longitude": "-2.3412",
      "content": "Contenu du message utilisateur"
    }
  ]
}
```

**Mémoire UMAP (`{latitude}_{longitude}.json`) :**
```json
{
  "latitude": "48.8534",
  "longitude": "-2.3412",
  "messages": [
    {
      "timestamp": "2024-01-01T12:00:00Z",
      "event_id": "hash_événement",
      "pubkey": "clé_publique_utilisateur",
      "content": "Contenu du message à cet emplacement"
    }
  ]
}
```

#### 5. Intégration du Contexte dans les Prompts IA
Le script `question.py` améliore les réponses IA en :
- Chargeant l'historique de conversation pertinent (jusqu'à 50 messages)
- Formatant les messages précédents comme contexte
- Incluant les informations de localisation quand disponibles
- Construisant un prompt complet pour Ollama
- Maintenant la continuité de conversation à travers les sessions

Ce système de mémoire permet à l'IA de fournir des réponses personnalisées et conscientes du contexte tout en respectant la vie privée des utilisateurs grâce au consentement explicite via le tag `#rec`.

### Économie Zen et Paiements Basés sur les Réactions

UPlanet implémente un système économique unique où les interactions sociales (réactions/likes) déclenchent des micro-paiements automatiques dans la devise Ğ1, créant une économie circulaire au sein de l'écosystème.

#### 1. Traitement des Réactions (`filter/7.sh`)

Le script `filter/7.sh` gère les événements Nostr de kind:7 (réactions/likes) et implémente l'économie Zen :

**Types de Réactions :**
- **Réactions Positives :** `+`, `👍`, `❤️`, `♥️` (le contenu vide est traité comme positif)
- **Réactions Négatives :** `-`, `👎`, `💔`
- **Réactions Personnalisées :** Tout autre emoji ou contenu

**Flux de Traitement :**
1. **Vérification d'Autorisation :** Vérifie que l'expéditeur de la réaction est un joueur UPlanet autorisé ou dans `amisOfAmis.txt`
2. **Détection de Membre UPlanet :** Utilise `search_for_this_hex_in_uplanet.sh` pour vérifier si l'auteur réagi fait partie d'UPlanet
3. **Paiement Automatique :** Si les deux conditions sont remplies, déclenche un paiement de 0.1 Ğ1 du réacteur vers le créateur de contenu

**Implémentation du Paiement :**
```bash
# Extraire G1PUBNOSTR pour l'auteur réagi
G1PUBNOSTR=$(~/.zen/Astroport.ONE/tools/search_for_this_hex_in_uplanet.sh $reacted_author_pubkey)

# Envoyer 0.1 Ğ1 si les deux utilisateurs sont membres UPlanet
if [[ -n "$G1PUBNOSTR" && -s "${PLAYER_DIR}/.secret.dunikey" ]]; then
    ~/.zen/Astroport.ONE/tools/PAYforSURE.sh "${PLAYER_DIR}/.secret.dunikey" "0.1" "$G1PUBNOSTR" "_like_${reacted_event_id}_from_${pubkey}"
fi
```

#### 2. Écosystème Économique (`ZEN.ECONOMY.sh`)

Le script `ZEN.ECONOMY.sh` gère le système économique plus large :

**Acteurs et Soldes :**
- **UPlanet :** "Banque centrale" coopérative gérant l'écosystème
- **Node :** Serveur physique (PC Gamer ou RPi5) hébergeant le relais
- **Captain :** Gestionnaire et administrateur du Node

**Coûts Hebdomadaires :**
- **Carte NOSTR :** 1 Ẑen/semaine (utilisateurs avec cartes Nostr)
- **Carte ZEN :** 4 Ẑen/semaine (utilisateurs avec cartes ZEN)
- **PAF (Participation Aux Frais) :** 14 Ẑen/semaine (coûts opérationnels)

**Logique de Paiement :**
```bash
# Calcul PAF quotidien
DAILYPAF=$(echo "$PAF / 7" | bc -l)  # 2 Ẑen/jour

# Captain paie PAF si solde suffisant, sinon UPlanet paie
if [[ $CAPTAINZEN > $DAILYPAF ]]; then
    # Captain paie Node (économie positive)
    PAYforSURE.sh "$CAPTAIN_DUNIKEY" "$DAILYG1" "$NODEG1PUB" "PAF"
else
    # UPlanet paie Node (économie négative)
    PAYforSURE.sh "$UPLANET_DUNIKEY" "$DAILYG1" "$NODEG1PUB" "PAF"
fi
```

#### 3. Incitations Économiques

**Incitations à la Création de Contenu :**
- **Micro-paiements :** Chaque réaction positive génère 0.1 Ğ1 pour les créateurs de contenu
- **Contenu de Qualité :** Encourage les contributions précieuses à l'écosystème
- **Construction de Communauté :** Récompense l'engagement et l'interaction

**Soutien à l'Infrastructure :**
- **Durabilité du Node :** PAF assure que les serveurs relais restent opérationnels
- **Compensation du Captain :** Les captains sont incités à maintenir une infrastructure de qualité
- **Stabilité UPlanet :** Le modèle coopératif distribue les coûts à travers l'écosystème

**Flux Économique :**
```
Utilisateur A publie du contenu → Utilisateur B like le contenu → Paiement 0.1 Ğ1 à Utilisateur A
                                                                        ↓
Node fournit service relais → Captain paie PAF → Node reçoit financement opérationnel
                                                                        ↓
Coopérative UPlanet → Gère l'écosystème → Distribue coûts et bénéfices
```

Ce modèle économique crée un écosystème auto-suffisant où les interactions sociales financent directement l'infrastructure et récompensent les créateurs de contenu, favorisant une économie circulaire au sein du réseau UPlanet.

## Spécification

### 1. Dérivation GeoKey

Une paire de clés Nostr (secp256k1) est dérivée de manière déterministe d'une chaîne de graine. La graine est construite en concaténant :

1.  `UPLANETNAME` : Une chaîne secrète identifiant l'application et utilisée comme ```~/.ipfs/swarm.key``` et crée l'essaim IPFS privé dédié à l'Application UPlanet.
2.  `FORMATTED_LATITUDE` : La latitude, formatée comme une chaîne à un nombre spécifique de décimales correspondant au niveau de grille souhaité.
3.  `FORMATTED_LONGITUDE` : La longitude, formatée comme une chaîne au même nombre de décimales que la latitude, correspondant au niveau de grille.

**Format de Graine :** `"{UPLANETNAME}_{FORMATTED_LATITUDE}" "{UPLANETNAME}_{FORMATTED_LONGITUDE}"` utilisé comme sel et poivre [libsodium](https://doc.libsodium.org/libsodium_users)
**Génération de Clés :** Implémenter la logique de génération de clés déterministes spécifiée ([accès au code de l'outil `keygen`](https://github.com/papiche/Astroport.ONE/blob/master/tools/keygen)).

**Niveaux de Grille et Formatage :**

UPlanet définit les niveaux de grille initiaux suivants :

-   **UMAP (Micro-Zone) :** Précision 0.01°.
    -   Formatage Latitude/Longitude : Représentation en chaîne avec exactement **deux** décimales (ex : `sprintf("%.2f", coordinate)` en C, ou équivalent). Les coordonnées devraient probablement être tronquées ou arrondies de manière cohérente *avant* le formatage.
    -   Exemple de Graine : `"UPlanetV148.85-2.34"` (pour Lat 48.853, Lon -2.341)
-   **SECTOR :** Précision 0.1°.
    -   Formatage Latitude/Longitude : Représentation en chaîne avec exactement **une** décimale.
    -   Exemple de Graine : `"UPlanetV148.8-2.3"` (pour Lat 48.853, Lon -2.341)
-   **REGION :** Précision 1.0°.
    -   Formatage Latitude/Longitude : Représentation en chaîne avec exactement **zéro** décimales (partie entière).
    -   Exemple de Graine : `"UPlanetV148-2"` (pour Lat 48.853, Lon -2.341)

**Algorithme de Génération de Clés :**
L'algorithme spécifique utilisé par l'outil `keygen` utilisé dans `IA_UPlanet.sh` est l'outil "Astroport", fournissant une méthode déterministe pour dériver une paire de clés secp256k1 d'une chaîne de graine unique (et autres clés jumelles : IPFS, G1, Bitcoin). La méthode choisie EST cohérente à travers l'écosystème UPlanet.

### 2. Tags d'Événements

Les événements liés aux emplacements UPlanet DEVRAIENT inclure les tags suivants :

-   **Tag Latitude :** `["latitude", "CHAINE_FLOAT"]`
    -   Valeur : La latitude comme une chaîne, optionnellement avec une précision plus élevée (ex : 6+ décimales) que le niveau de grille GeoKey. Exemple : `"48.8534"`
-   **Tag Longitude :** `["longitude", "CHAINE_FLOAT"]`
    -   Valeur : La longitude comme une chaîne, optionnellement avec une précision plus élevée. Exemple : `"-2.3412"`
-   **Tag Application :** `["application", "UPlanet*"]`
    -   Valeur : Identifie l'événement comme appartenant au système UPlanet. Permet la différenciation (ex : `UPlanet_AppName`).

**Note :** Bien que les GeoKeys fournissent une identité pour les cellules de grille, les tags `latitude` et `longitude` spécifient le point d'intérêt précis *dans* ou lié à cette cellule. Les événements publiés *depuis* une GeoKey UMAP pourraient contenir des tags pointant vers une coordonnée très spécifique dans cette cellule 0.01°x0.01°.

### 3. Publication

-   Pour poster **en tant que** une cellule de grille d'emplacement spécifique (ex : un bot automatisé rapportant pour une cellule UMAP), dériver la GeoKey `nsec` appropriée en utilisant la méthode de la Spécification 1 et publier un événement kind 1 signé avec elle. L'événement DEVRAIT inclure les tags `latitude`, `longitude`, et `application`.
-   Les utilisateurs réguliers postant *à propos* d'un emplacement ont un emplacement par défaut enregistré avec leur clé personnelle fournie lors de l'enregistrement Astroport. Cet emplacement est utilisé quand des données géo sont trouvées dans l'événement.

### 4. Abonnement et Filtrage

Les clients peuvent découvrir le contenu UPlanet de plusieurs façons :

-   **S'abonner par GeoKey :** S'abonner directement au `npub` de la GeoKey UMAP, SECTOR, ou REGION souhaitée(s).
-   **Filtrer par Tags :** S'abonner aux événements `kind: 1` filtrés par le tag `application` (`#a`: `["UPlanet"]`) et optionnellement filtrer côté client basé sur les tags `latitude` et `longitude` pour trouver les événements dans un rayon géographique spécifique.
-   **Filtrer par Référence Géographique :** S'abonner aux événements qui taguent (`#p`) des `npub` GeoKey spécifiques.

## Guide d'Implémentation Client

-   **Publication :** Lors de la publication, déterminer les coordonnées pertinentes. Inclure les tags `latitude`, `longitude`, et `application`. Optionnellement dériver et inclure les tags `p` pour les GeoKeys pertinentes. Si on poste *en tant qu* emplacement, utiliser la GeoKey `nsec` dérivée pour la signature.
-   **Réception :** Filtrer les événements entrants basés sur les GeoKeys souscrites ou les tags. Afficher les informations d'emplacement, potentiellement sur une carte. Parser les tags `latitude` et `longitude` pour le positionnement précis.
-   **Formatage des Coordonnées :** Respecter strictement les décimales spécifiées pour chaque niveau de grille lors de la dérivation des clés. Utiliser des fonctions standard pour le formatage (ex : `sprintf("%.2f", coord)`). La cohérence dans la troncature ou l'arrondi est cruciale.

## Cas d'Usage Illustrés

-   **Chat Local :** Alice poste depuis son téléphone en utilisant sa clé personnelle mais tag la GeoKey UMAP `npub` pour son bloc actuel et inclut les tags `latitude`/`longitude`. Bob, souscrit à cette GeoKey UMAP, voit son message.
-   **Alerte Météo Automatisée :** Un service automatisé dérive la GeoKey REGION pour Paris (`"UPlanetV1482"`), signe une alerte météo en utilisant la `nsec` de cette clé, et inclut des tags `latitude`/`longitude` précis pour le centre de la tempête. Les utilisateurs souscrits à la GeoKey REGION Paris reçoivent l'alerte.
-   **Répondeur IA :** Un service IA surveille les messages tagués avec `application: UPlanet`. Quand il voit un message d'un utilisateur (`pubkey_A`) tagué avec `latitude`/`longitude`, il dérive la GeoKey UMAP correspondante (`pubkey_UMAP`), génère une réponse, la signe avec la `nsec` de la GeoKey UMAP, et inclut les tags `e` et `p` référençant l'événement original (`event_id`) et l'utilisateur (`pubkey_A`).

## Considérations de Sécurité et de Vie Privée

-   **Divulgation de Localisation :** Publier avec des tags `latitude`/`longitude` précis révèle la localisation. Les utilisateurs doivent en être conscients. Utiliser des clés de grille plus larges (SECTOR, REGION) pour poster offre moins de précision.
-   **Suivi :** L'utilisation cohérente de GeoKeys ou de tags pourrait permettre le suivi des mouvements des utilisateurs s'ils postent fréquemment depuis différents emplacements en utilisant leur clé personnelle avec des tags géo.
-   **Sécurité de l'Espace de Noms :** Le contrôle sur la chaîne `UPLANETNAME` est important. Si elle est compromise ou changée, cela pourrait perturber le système ou mener à l'usurpation d'emplacements.
-   **Gestion des Clés :** Gérer potentiellement 654 Millions de `nsec` GeoKey, le stockage Astroport peut choisir le nœud le plus proche.

## Compatibilité

Ce NIP est compatible avec les concepts Nostr existants :
-   Utilise des événements kind 1 standard.
-   Utilise les tags `e` et `p` standard pour les réponses et références utilisateur (NIP-10).
-   Peut être utilisé avec d'autres NIPs définissant du contenu ou des tags.

## Références

-   NIP-01 : Description du flux de protocole de base
-   NIP-10 : Conventions pour l'utilisation des tags `e` et `p` dans les événements texte
-   *(Impliqué)* : secp256k1, SHA256 