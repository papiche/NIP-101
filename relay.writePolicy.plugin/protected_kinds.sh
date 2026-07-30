#!/bin/bash
################################################################################
# Author: Fred (support@qo-op.com)
# License: AGPL-3.0
################################################################################
#~ protected_kinds.sh — Source UNIQUE de la liste des kinds NOSTR immuables
#~ (jamais supprimables, même par leur propre auteur légitime).
#
# Sourcé par :
#   - filter/5.sh                — bloque la suppression sur le chemin d'écriture
#                                   client direct (websocket → RelayWriter → plugin)
#   - backfill_constellation.sh  — exclut les events kind 5 CIBLANT un kind protégé
#                                   de l'import constellation, AVANT `strfry import`
#
# CONTEXTE CRITIQUE (vérifié dans le code source strfry, events.cpp:248-353,
# fonction writeEvents()) : la suppression kind 5 est appliquée par cette même
# fonction bas niveau, appelée À LA FOIS par le chemin d'écriture live (après
# acceptation par writePolicy) ET par `strfry import` (qui N'INVOQUE JAMAIS
# writePolicy). Exclure un kind de la synchronisation constellation (ex. 30852,
# jamais dans les allowlists kinds:[...] de backfill_constellation.sh) NE SUFFIT
# PAS à le protéger : le kind 5 LUI-MÊME est déjà synchronisé aujourd'hui (legit,
# pour propager les suppressions des AUTRES kinds entre stations), donc un event
# kind 5 forgé référençant un event protégé existant localement, une fois importé
# via la synchro, déclenche sa suppression réelle — sans jamais passer par
# filter/5.sh. Les DEUX protections (kind non synchronisé + kind-5 ciblant ce
# kind exclu de l'import) sont nécessaires, aucune ne suffit seule.
################################################################################

PROTECTED_KINDS=(30852)
