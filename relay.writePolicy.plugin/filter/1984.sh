#!/bin/bash
# filter/1984.sh
# Handles Nostr events of kind:1984 (NIP-56 reports)
# Extension: report-type=friction → protocole de médiation WoTx² (Kind 30506)

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

source "$MY_PATH/common.sh"

LOG_FILE="$HOME/.zen/tmp/nostr_reports.1984.log"
JUSTICE_LOG="$HOME/.zen/tmp/justice_cases.log"
ensure_log_dir "$LOG_FILE"
ensure_log_dir "$JUSTICE_LOG"

log_report() { log_with_timestamp "$LOG_FILE" "$1"; }

event_json="$1"
extract_event_data "$event_json"

# Extraire p, e, reason via extract_tags (noms sans tiret → variables bash valides)
extract_tags "$event_json" "p" "e" "reason"
reported_pubkey="$p"
reported_event_id="$e"

# report-type contient un tiret → extraction directe via jq (extract_tags ne peut pas créer
# une variable bash avec tiret dans le nom)
report_type=$(echo "$event_json" | jq -r '
    .event.tags[] | select(.[0] == "report-type") | .[1]' 2>/dev/null | head -1)

# Vérifier l'autorisation du rapporteur
if ! check_authorization "$pubkey" "log_report"; then
    exit 1
fi
reporter_email="$EMAIL"
reporter_source="$SOURCE"

if [[ -z "$reported_pubkey" ]]; then
    log_report "REJECTED: 'p' tag manquant (pubkey de la personne signalée)"
    exit 1
fi

if [[ -z "$report_type" ]]; then
    log_report "REJECTED: 'report-type' tag manquant"
    exit 1
fi

# Vérifier si la partie signalée est membre UPlanet
if check_authorization "$reported_pubkey" "log_report" 2>/dev/null; then
    reported_in_uplanet=true
    reported_email="$EMAIL"
    reported_source="$SOURCE"
    log_report "REPORT: ${pubkey:0:8}... signale ${reported_pubkey:0:8}... (membre UPlanet: $reported_email depuis $reported_source)"
else
    reported_in_uplanet=false
    reported_email=""
    log_report "REPORT: ${pubkey:0:8}... signale utilisateur externe ${reported_pubkey:0:8}..."
fi
EMAIL="$reporter_email"
SOURCE="$reporter_source"

log_report "REPORT: Type: $report_type"
[[ -n "$reported_event_id" ]] && log_report "REPORT: Événement signalé: ${reported_event_id:0:8}..."
[[ -n "$reason" ]]            && log_report "REPORT: Raison: $reason"
[[ -n "$content" ]]           && log_report "REPORT: Détails: $content"

case "$report_type" in
    "spam"|"impersonation"|"harassment"|"illegal")
        log_report "URGENT: Rapport haute priorité: $report_type"
        ;;

    "fake"|"scam"|"phishing")
        log_report "WARNING: Rapport sécurité: $report_type"
        ;;

    "friction")
        # ── Protocole de médiation WoTx² N1/N2 ──────────────────────────────
        log_report "FRICTION: Déclaration reçue de ${pubkey:0:8}... contre ${reported_pubkey:0:8}..."

        if [[ "$reported_in_uplanet" != "true" ]]; then
            log_report "FRICTION: Pas de dossier N1 — ${reported_pubkey:0:8}... n'est pas membre UPlanet MULTIPASS"
        else
            # Tags spécifiques friction (noms sans tiret → jq direct)
            friction_amount=$(echo "$event_json" | jq -r '
                .event.tags[] | select(.[0] == "friction-amount") | .[1]' 2>/dev/null | head -1)
            friction_object=$(echo "$event_json" | jq -r '
                .event.tags[] | select(.[0] == "object") | .[1]' 2>/dev/null | head -1)
            friction_amount="${friction_amount:-0}"

            # Seuil de niveau selon montant (barème mutualiste)
            if awk "BEGIN{exit !($friction_amount > 50)}" 2>/dev/null; then
                case_level="constellation"
            elif awk "BEGIN{exit !($friction_amount > 10)}" 2>/dev/null; then
                case_level="N2"
            else
                case_level="N1"
            fi

            # Identifiant unique du dossier
            ts=$(date +%s)
            case_id="friction-${pubkey:0:6}-${reported_pubkey:0:6}-${ts}"

            # Écrire le dossier en attente pour publication Kind 30506
            pending_dir="$HOME/.zen/tmp/justice_pending"
            mkdir -p "$pending_dir"

            reason_json=$(printf '%s' "$reason" | jq -Rs .)
            cat > "${pending_dir}/${case_id}.json" <<JSON
{
  "case_id": "${case_id}",
  "plaignant": "${pubkey}",
  "plaignant_email": "${reporter_email}",
  "défendeur": "${reported_pubkey}",
  "défendeur_email": "${reported_email}",
  "origin_event_id": "${event_id}",
  "amount_zen": ${friction_amount},
  "object_dtag": "${friction_object}",
  "reason": ${reason_json},
  "level": "${case_level}",
  "status": "${case_level}_ouvert",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
            log_report "FRICTION: Dossier ${case_id} créé (niveau ${case_level}, montant: ${friction_amount}Ẑ)"
            log_with_timestamp "$JUSTICE_LOG" \
                "FRICTION ${case_id} | plaignant:${pubkey:0:8} | défendeur:${reported_pubkey:0:8} | level:${case_level} | amount:${friction_amount}Ẑ | object:${friction_object}"

            # Lancer N1Mediation.sh en arrière-plan si disponible
            mediation_script="$HOME/.zen/Astroport.ONE/ASTROBOT/N1Mediation.sh"
            if [[ -x "$mediation_script" ]]; then
                nohup bash "$mediation_script" "${pending_dir}/${case_id}.json" \
                    >>"$HOME/.zen/tmp/nostr_kind30506.log" 2>&1 &
                log_report "FRICTION: N1Mediation.sh lancé (PID $!)"
            else
                log_report "FRICTION: N1Mediation.sh absent — dossier en attente dans $pending_dir"
            fi
        fi
        ;;

    *)
        log_report "INFO: Type de rapport standard: $report_type"
        ;;
esac

log_report "ACCEPTED: Rapport de ${pubkey:0:8}... (Email: $EMAIL, Source: $SOURCE)"
echo ">>> (1984) REPORT: ${pubkey:0:8}... → ${reported_pubkey:0:8}... ($report_type)"

exit 0 