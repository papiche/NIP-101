#!/bin/bash
# filter/30850.sh
# Log Station Economic Health Report (kind 30850) — cf. KIND_REGISTRY.md §Kind 30850
#
# Rapport périodique de santé économique de chaque station (SCIC), diffusé par
# ZEN.ECONOMY.sh (trésorerie, revenus, coûts, capacités, niveau de résilience).
# Jusqu'ici sans filtre dédié (routé par all_but_blacklist.sh générique) :
# angle mort sur un signal pourtant central pour NODE. La station qui rapporte
# elle-même son état de résilience est exactement le genre de signal que
# LifeOS/Arbor doit pouvoir observer dans le temps — et un complément utile à
# l'alerte low_g1_balance de BRO (qui ne voit que le solde individuel, pas la
# santé globale de la station qui l'héberge).

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

# Source common functions
source "$MY_PATH/common.sh"

event_json="$1"
extract_event_data "$event_json"

# Tags contenant ":" — extract_tags() ne peut pas les affecter en variables
# bash (eval échouerait sur un nom de variable avec ":"), extraction directe.
station=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0]=="station") | .[1]' 2>/dev/null | head -1)
health_status=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0]=="health:status") | .[1]' 2>/dev/null | head -1)
health_resilience=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0]=="health:resilience_level") | .[1]' 2>/dev/null | head -1)
health_runway=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0]=="health:weeks_runway") | .[1]' 2>/dev/null | head -1)
revenue_total=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0]=="revenue:total") | .[1]' 2>/dev/null | head -1)

LOG_FILE="$HOME/.zen/tmp/nostr_kind30850.log"
ensure_log_dir "$LOG_FILE"

log_with_timestamp "$LOG_FILE" "=== Station Economic Health Report (kind 30850) ==="
log_with_timestamp "$LOG_FILE" "Station: ${station:-?} | Status: ${health_status:-?} | Resilience: ${health_resilience:-?} | Runway: ${health_runway:-?} semaines | Revenue: ${revenue_total:-?}"
log_with_timestamp "$LOG_FILE" "================================"

nip101_log_event "30850" "health_report" 1 \
    "{\"station\":\"${station:-}\",\"status\":\"${health_status:-}\",\"resilience_level\":\"${health_resilience:-}\",\"weeks_runway\":\"${health_runway:-}\"}"

# Toujours accepté — rapport informatif, aucune politique de rejet documentée.
exit 0
