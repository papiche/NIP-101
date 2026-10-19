#!/bin/bash
################################################################################
# Author: Fred (support@qo-op.com)
# License: AGPL-3.0
################################################################################
#~ tests/n2_fork_cross_test.sh — double dépense CROISÉE sur le ledger Ğ1-N² (kind 30852)
#
# Scénario : X (membre malhonnête) reçoit 200 d'une autorité de mint, puis signe
# DEUX transactions de même `prev` ("genesis") : Ta → Alice (cercle de la station A)
# et Tb → Bob (cercle de la station B). Chacune est valide prise isolément.
#
# On rejoue, station par station, la revalidation réelle du backfill
# (reject_invalid_ledger_events, extraite telle quelle de backfill_constellation.sh)
# sur des stores strfry simulés (faux `strfry scan` sur fichier NDJSON, isolés par station).
#
#   T1  A synchronise {Tb}                     → rejeté (fork)
#   T2  B synchronise {Ta}                     → rejeté (fork)
#   T3  pont C, même lot {Ta,Tb}               → un seul accepté : le plus ancien created_at
#   T3b pont C, même lot, horodatages inversés → l'autre gagne (le gagnant dépend de l'attaquant)
#   T4  pont C, lots successifs {Ta} puis {Tb}, import entre les deux
#                                              → Tb DOIT être rejeté (cache de solde rafraîchi)
#   T5  rejeu d'un event déjà importé          → rejeté (inoffensif)
#   T6  fork prouvé reçu par A                 → incident journalisé (preuve : 2 ids) + mails
#                                                aux MULTIPASS locaux concernés ET au capitaine,
#                                                sans doublon au cycle suivant
#   T7  prev simplement inconnu (lot partiel)  → rejeté mais AUCUNE alerte (ambigu)
#   T8  un mint PAR STATION (clés distinctes)  → chaque station accepte le mint de l'autre
#   T8b clé de mint PARTAGÉE (ancien modèle)   → fork de la chaîne du mint (pourquoi on l'a abandonné)
#   T9  fork prouvé → compte GELÉ              → toute tx sortante ultérieure rejetée, sans nouvelle alerte
#   T10 résolution après rencontre humaine     → n2_fork_resolve.sh : branche annulée, dégel, la branche valide passe
#   T11 cache « fantôme » (event rejeté par strfry après avance du cache) → auto-cicatrisé
#
# Usage : tests/n2_fork_cross_test.sh        (code retour ≠ 0 si un test échoue)
################################################################################
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKFILL="$HERE/../backfill_constellation.sh"
LIB="$HERE/../relay.writePolicy.plugin/filter/n2_ledger_lib.sh"
TMP=$(mktemp -d); export HOME="$TMP/home"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

hex() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
M=$(hex mint-authority); X=$(hex mallory); ALICE=$(hex alice); BOB=$(hex bob)
printf '%s\n' "$M" > "$TMP/mint_authorities.txt"
export N2_MINT_AUTHORITIES_FILE="$TMP/mint_authorities.txt"

# ── Notifications simulées : annuaire MULTIPASS local, capitaine, mailjet factice ──
export BACKFILL_SCRIPT_DIR="$HERE/.."
export N2_INCIDENTS_FILE="$TMP/n2_incidents.jsonl" N2_KEY_DIR="$TMP/nostr" CAPTAINEMAIL="captain@example.org"
export N2_MAILJET="$TMP/mailjet_stub.sh" MAIL_LOG="$TMP/mails.log"
printf '#!/bin/bash\n# args : --template T --expire E <to> <html> <subject>\necho "$5" >> "$MAIL_LOG"\n' > "$N2_MAILJET"

# ── Faux strfry : `strfry scan <filtre|[filtres]>` sur $PWD/events.ndjson ────────
FAKE_STRFRY='#!/usr/bin/env python3
import sys, json
f = json.loads(sys.argv[2]); fs = f if isinstance(f, list) else [f]
def match(e, q):
    if "ids" in q and e["id"] not in q["ids"]: return False
    if "kinds" in q and e["kind"] not in q["kinds"]: return False
    if "authors" in q and e["pubkey"] not in q["authors"]: return False
    for k in ("#d", "#p"):
        if k in q and not any(t[0] == k[1] and t[1] in q[k] for t in e["tags"]): return False
    return True
try: lines = open("events.ndjson").read().splitlines()
except FileNotFoundError: lines = []
for l in lines:
    e = json.loads(l)
    if any(match(e, q) for q in fs): print(json.dumps(e, separators=(",", ":")))
'

station_init() {   # station_init NOM [event...] — store + cache isolés
    local d="$TMP/$1"; mkdir -p "$d"
    printf '%s' "$FAKE_STRFRY" > "$d/strfry"; chmod +x "$d/strfry"
    : > "$d/events.ndjson"; rm -rf "$d/n2_ledger" "$d/frozen.txt" "$d/void.txt"
    shift; local e; for e in "$@"; do echo "$e" >> "$d/events.ndjson"; done
}
use() { export N2_STRFRY_DIR="$TMP/$1" N2_LEDGER_DIR="$TMP/$1/n2_ledger" N2_FROZEN_FILE="$TMP/$1/frozen.txt" N2_VOID_FILE="$TMP/$1/void.txt"; }

ev() {   # ev ID_SEED AUTEUR DEST MONTANT PREV D CREATED [mint]
    local tags='[["d","'"$6"'"],["p","'"$3"'"],["amount","'"$4"'"],["prev","'"$5"'"],["t","g1-n2"]'
    [[ "${8:-}" == "mint" ]] && tags+=',["t","mint"]'; tags+=']'
    jq -cn --arg id "$(hex "$1")" --arg pk "$2" --argjson ts "$7" --argjson tags "$tags" \
        '{id:$id,pubkey:$pk,kind:30852,created_at:$ts,tags:$tags,content:"",sig:""}'
}
id() { jq -r .id <<< "$1"; }

E0=$(ev e0 "$M" "$X" 200 genesis n2-e0 900 mint)
Ta=$(ev ta "$X" "$ALICE" 100 genesis n2-a 1000)
Tb=$(ev tb "$X" "$BOB"   100 genesis n2-b 1001)

# ── Revalidation réelle du backfill ───────────────────────────────────────────
log() { :; }      # log() réel écrit aussi sur stdout (capturé) : neutralisé ici
source "$LIB"
eval "$(awk '/^reject_invalid_ledger_events\(\) \{/,/^}/' "$BACKFILL")"
eval "$(awk '/^n2_pubkey_email\(\) \{/,/^}/' "$BACKFILL")"
eval "$(awk '/^n2_report_fork\(\) \{/,/^}/' "$BACKFILL")"
eval "$(awk '/^refresh_n2_ledger_cache\(\) \{/,/^}/' "$BACKFILL")"
declare -F n2_report_fork >/dev/null && declare -F refresh_n2_ledger_cache >/dev/null && declare -F reject_invalid_ledger_events >/dev/null || { echo "fonction introuvable dans $BACKFILL"; exit 2; }

sync() {   # sync STATION event... → écrit les IDs rejetés dans $REJECTED (tableau)
    use "$1"; shift
    local batch="$TMP/batch.json"; printf '%s\n' "$@" | jq -sc . > "$batch"
    mapfile -t REJECTED < <(reject_invalid_ledger_events "$batch" | grep -E '^[0-9a-f]{64}$')
}
import_accepted() {   # import_accepted STATION event... — comme `strfry import` du backfill
    local st="$1"; shift; local e imported="$TMP/imported.ndjson"; : > "$imported"
    for e in "$@"; do
        [[ " ${REJECTED[*]:-} " == *" $(id "$e") "* ]] || { echo "$e" >> "$TMP/$st/events.ndjson"; echo "$e" >> "$imported"; }
    done
    use "$st"; refresh_n2_ledger_cache "$imported"   # étape du backfill après `strfry import`
}
is_rejected() { [[ " ${REJECTED[*]:-} " == *" $(id "$1") "* ]]; }

check() {  # check "libellé" commande...
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "  ok   $label"; PASS=$((PASS+1)); else echo "  FAIL $label"; FAIL=$((FAIL+1)); fi
}
not_rejected() { ! is_rejected "$1"; }

echo "== T1/T2 : chaque cercle refuse la branche de l'autre"
station_init A "$E0" "$Ta";  sync A "$Tb"; check "A rejette Tb (fork de Ta)" is_rejected "$Tb"
station_init B "$E0" "$Tb";  sync B "$Ta"; check "B rejette Ta (fork de Tb)" is_rejected "$Ta"

echo "== T3 : pont C, même lot — le plus ancien created_at gagne"
station_init C "$E0";        sync C "$Ta" "$Tb"
check "C accepte Ta (created_at 1000)" not_rejected "$Ta"
check "C rejette Tb (created_at 1001)" is_rejected "$Tb"

echo "== T3b : mêmes events, horodatages inversés — le gagnant change"
Ta2=$(ev ta "$X" "$ALICE" 100 genesis n2-a 1002); Tb2=$(ev tb "$X" "$BOB" 100 genesis n2-b 1001)
station_init C "$E0";        sync C "$Ta2" "$Tb2"
check "C accepte Tb (désormais le plus ancien)" not_rejected "$Tb2"
check "C rejette Ta (désormais le plus récent)" is_rejected "$Ta2"
echo "  note : l'auteur du fork choisit quelle branche chaque pont accepte en jouant sur created_at"

echo "== T4 : pont C, lots successifs avec import entre les deux"
station_init C "$E0";        sync C "$Ta"
check "lot 1 : C accepte Ta" not_rejected "$Ta"
import_accepted C "$Ta"
sync C "$Tb"
check "lot 2 : C rejette Tb (Ta déjà importé)" is_rejected "$Tb"

echo "== T5 : rejeu d'un event déjà importé"
sync C "$Ta"
check "C rejette Ta rejoué (d-tag déjà connu)" is_rejected "$Ta"

echo "== T6 : fork prouvé → incident + avertissement des concernés et du capitaine"
mkdir -p "$TMP/nostr/alice@example.org"; printf '%s\n' "$ALICE" > "$TMP/nostr/alice@example.org/HEX"
: > "$N2_INCIDENTS_FILE"; : > "$MAIL_LOG"
station_init A "$E0" "$Ta";  sync A "$Tb"
check "incident journalisé (1 ligne)"          test "$(wc -l < "$N2_INCIDENTS_FILE")" -eq 1
check "preuve : les 2 ids signés par X"        jq -e --arg a "$(id "$Ta")" --arg b "$(id "$Tb")" '.type=="fork" and (.events|sort)==([$a,$b]|sort)' "$N2_INCIDENTS_FILE"
check "capitaine averti"                       grep -qx "captain@example.org" "$MAIL_LOG"
check "bénéficiaire local (Alice) averti"      grep -qx "alice@example.org" "$MAIL_LOG"
sync A "$Tb"
check "pas de doublon au cycle suivant"        test "$(wc -l < "$N2_INCIDENTS_FILE")" -eq 1

echo "== T7 : prev inconnu (lot partiel) → rejeté, sans alerte"
: > "$N2_INCIDENTS_FILE"; : > "$MAIL_LOG"
Tx=$(ev tx "$X" "$BOB" 10 "$(hex quelconque)" n2-x 1500)
station_init C "$E0";        sync C "$Tx"
check "Tx rejeté (chaîne incomplète)"          is_rejected "$Tx"
check "aucun incident"                         test ! -s "$N2_INCIDENTS_FILE"
check "aucun mail"                             test ! -s "$MAIL_LOG"

echo "== T8 : un mint par station"
MA=$(hex mint-A); MB=$(hex mint-B); printf '%s\n%s\n' "$MA" "$MB" > "$N2_MINT_AUTHORITIES_FILE"
Ma=$(ev ma "$MA" "$ALICE" 11 genesis n2-ma 2000 mint); Mb=$(ev mb "$MB" "$BOB" 11 genesis n2-mb 2001 mint)
station_init A "$Ma"; sync A "$Mb"; check "A accepte le mint de B (chaînes distinctes)" not_rejected "$Mb"
station_init B "$Mb"; sync B "$Ma"; check "B accepte le mint de A" not_rejected "$Ma"

echo "== T8b : clé de mint partagée = fork garanti (ancien modèle)"
printf '%s\n' "$M" > "$N2_MINT_AUTHORITIES_FILE"
Ma2=$(ev ma2 "$M" "$ALICE" 11 genesis n2-ma2 2000 mint); Mb2=$(ev mb2 "$M" "$BOB" 11 genesis n2-mb2 2001 mint)
station_init A "$Ma2"; sync A "$Mb2"; check "A rejette le mint de B (même chaîne prev)" is_rejected "$Mb2"

echo "== T9 : après fork prouvé, le compte est gelé"
: > "$N2_INCIDENTS_FILE"; : > "$MAIL_LOG"
station_init A "$E0" "$Ta";  sync A "$Tb"
check "X est gelé sur A"                       n2_is_frozen "$X"
Tz=$(ev tz "$X" "$BOB" 5 "$(id "$Ta")" n2-z 1100)      # tx « légitime » (prev = Ta) mais compte gelé
sync A "$Tz"
check "tx sortante d'un compte gelé rejetée"   is_rejected "$Tz"
check "pas de nouvel incident"                 test "$(wc -l < "$N2_INCIDENTS_FILE")" -eq 1

echo "== T10 : résolution après rencontre — la branche d'Alice (Ta) est annulée, celle de Bob (Tb) est valide"
export N2_LEDGER_LIB="$LIB"
use A
bash "$HERE/../../Astroport.ONE/tools/n2_fork_resolve.sh" resolve "$X" "$(id "$Tb")" >/dev/null 2>&1
check "X dégelé"                               bash -c '! grep -q "^'"$X"':" "$N2_FROZEN_FILE" 2>/dev/null'
check "Ta annulée sur A"                       grep -qx "$(id "$Ta")" "$N2_VOID_FILE"
check "solde d'Alice recalculé sans Ta"        test "$(n2_ledger_get_balance "$ALICE" true | cut -d'|' -f1)" = "0"
sync A "$Tb"
check "la branche valide (Tb) est maintenant acceptée" not_rejected "$Tb"

echo "== T11 : cache fantôme auto-cicatrisé"
station_init C "$E0"
use C; n2_ledger_cache_write "$X" 12 "$(hex fantome)" "$(hex fantome)"
jq '.cached_at -= 60' "$N2_LEDGER_DIR/$X.json" > "$N2_LEDGER_DIR/x.tmp" && mv "$N2_LEDGER_DIR/x.tmp" "$N2_LEDGER_DIR/$X.json"
check "le fantôme est écarté (solde recalculé depuis le store)" test "$(n2_ledger_get_balance "$X" | cut -d'|' -f1)" = "200"

echo
echo "Résultat : $PASS ok, $FAIL échec(s)"
[[ $FAIL -eq 0 ]]
