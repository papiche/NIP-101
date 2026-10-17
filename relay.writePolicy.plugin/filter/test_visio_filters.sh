#!/bin/bash
# test_24315.sh — vérifie filter/24315.sh (présence) et 24316.sh (sonnerie), éphémères. Nécessite un MULTIPASS local (HEX).
# Usage : ./test_24315.sh   → affiche « OK » / « ÉCHEC » par cas, code 1 au moindre écart.
F="$(cd "$(dirname "$0")" && pwd)/24315.sh"
now=$(date +%s)
HEX=$(cat ~/.zen/game/nostr/*/HEX 2>/dev/null | head -1); [[ -n "$HEX" ]] || { echo "aucun MULTIPASS local : test ignoré"; exit 0; }
FAIL=0; P=$(printf 'ab%.0s' {1..32})
mk() { jq -nc --arg pk "$1" --argjson ts "$2" --argjson tags "$3" --arg c "$4" '{event:{kind:24315,pubkey:$pk,created_at:$ts,tags:$tags,content:$c}}'; }
t() { want="$1"; desc="$2"; shift 2; "$F" "$(mk "$@")" 2>/dev/null; got=$?
      if [[ $got -eq $want ]]; then echo "OK     $desc"; else echo "ÉCHEC  $desc (attendu $want, obtenu $got)"; FAIL=1; fi; }
t 0 "ok (MULTIPASS local)"     "$HEX" $now "[[\"p\",\"$P\"],[\"status\",\"online\"]]" ""
t 1 "pubkey inconnue"          "$P"   $now "[[\"p\",\"$P\"],[\"status\",\"online\"]]" ""
t 1 "statut invalide"          "$HEX" $now "[[\"p\",\"$P\"],[\"status\",\"hacked\"]]" ""
t 1 "contenu non vide"         "$HEX" $now "[[\"p\",\"$P\"],[\"status\",\"online\"]]" "salut"
t 1 "horloge -10 min"          "$HEX" $((now-600)) "[[\"p\",\"$P\"],[\"status\",\"online\"]]" ""
t 1 "aucun p"                  "$HEX" $now "[[\"status\",\"online\"]]" ""
t 1 "p mal formé"              "$HEX" $now "[[\"p\",\"xyz\"],[\"status\",\"online\"]]" ""
big=$(jq -nc --arg p "$P" '[range(51)|["p",$p]] + [["status","online"]]')
t 1 "51 destinataires"         "$HEX" $now "$big" ""
t 1 "2 statuts"                "$HEX" $now "[[\"p\",\"$P\"],[\"status\",\"online\"],[\"status\",\"away\"]]" ""


# ── 24316 : sonnerie (un destinataire, contenu chiffré base64) ──────────────────
G="$(cd "$(dirname "$0")" && pwd)/24316.sh"
CT=$(printf 'A%.0s' {1..64})
mk2() { jq -nc --arg pk "$1" --argjson ts "$2" --argjson tags "$3" --arg c "$4" '{event:{kind:24316,pubkey:$pk,created_at:$ts,tags:$tags,content:$c}}'; }
r() { want="$1"; desc="$2"; shift 2; "$G" "$(mk2 "$@")" 2>/dev/null; got=$?
      if [[ $got -eq $want ]]; then echo "OK     $desc"; else echo "ÉCHEC  $desc (attendu $want, obtenu $got)"; FAIL=1; fi; }
r 0 "24316 ok"                   "$HEX" $now "[[\"p\",\"$P\"]]" "$CT"
r 1 "24316 expéditeur inconnu"   "$P"   $now "[[\"p\",\"$P\"]]" "$CT"
r 1 "24316 contenu en clair"     "$HEX" $now "[[\"p\",\"$P\"]]" "rejoins-moi sur https://x"
r 1 "24316 deux destinataires"   "$HEX" $now "[[\"p\",\"$P\"],[\"p\",\"$P\"]]" "$CT"
r 1 "24316 horloge +10 min"      "$HEX" $((now+600)) "[[\"p\",\"$P\"]]" "$CT"
exit $FAIL
