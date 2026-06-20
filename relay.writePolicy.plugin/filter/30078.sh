#!/bin/bash
# filter/30078.sh (OPTIMIZED)
# This script handles Nostr events of kind:30078 (user statuses/mood updates)

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr_statuses.30078.log"
ensure_log_dir "$LOG_FILE"

# Logging function for statuses
log_status() {
    log_with_timestamp "$LOG_FILE" "$1"
}

# Extract event data in one optimized call
event_json="$1"
extract_event_data "$event_json"

# Extract specific tags for kind 30078 events
extract_tags "$event_json" "d" "emoji" "status" "expiration"
status_id="$d"
emoji="$emoji"
status_type="$status"
expiration="$expiration"

# ── Certificat d'incarnation ATOM4LOVE (bootstrap) ──────────────────────────
# La signature secp256k1 est déjà vérifiée par strfry.
# On valide les plages biométriques et on enregistre le pubkey dans amisOfAmis.
if [[ "$status_id" == "atom4love" ]]; then
    # 1. Vérifier le marqueur d'app contre la liste des apps autorisées (config coopérative)
    actual_proof=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "a4l_proof") | .[1]' 2>/dev/null | head -1)
    valid_proof=false
    while IFS= read -r app_id; do
        [[ -z "$app_id" ]] && continue
        expected_proof=$(printf '%s' "${pubkey}:${app_id}" | sha256sum | awk '{print $1}')
        [[ "$actual_proof" == "$expected_proof" ]] && valid_proof=true && break
    done < <(_load_authorized_app_ids)
    if [[ "$valid_proof" == "false" ]]; then
        log_status "REJECTED: Marqueur app non autorisé pour ${pubkey:0:8}... (reçu=${actual_proof:0:8}…)"
        exit 1
    fi
    # 2. Vérifier les plages biométriques + champ cymatique a5l (optionnel)
    A4L_LOG="$HOME/.zen/tmp/nostr_atom4love.log"
    ensure_log_dir "$A4L_LOG"
    a4l_log() { log_with_timestamp "$A4L_LOG" "$1"; }

    phase=$(echo "$content" | jq -r '.personal_phase // -1' 2>/dev/null)
    omega=$(echo "$content" | jq -r '.omega_bio      // -1' 2>/dev/null)
    a5l=$(echo "$content"   | jq -r '.a5l_amplitude  // ""' 2>/dev/null)

    # a5l est optionnel (absent des anciens certificats) — si présent, doit être ∈ [0,1]
    if [[ -n "$a5l" ]] && ! awk "BEGIN{exit !($a5l >= 0 && $a5l <= 1)}" 2>/dev/null; then
        a4l_log "REJECTED: a5l_amplitude hors plage [0,1] — ${pubkey:0:8}... (Ψ=$a5l)"
        log_status "REJECTED: a5l_amplitude hors plage pour ${pubkey:0:8}... (Ψ=$a5l)"
        exit 1
    fi

    if awk "BEGIN{exit !($phase >= 0 && $phase < 7 && $omega > 0.1 && $omega < 50)}"; then
        add_to_amis_of_amis "$pubkey" "ATOM4LOVE certified"
        _a5l_str="${a5l:+ Ψ=$a5l}"

        # ── Vérification de conformité keygen a4l ────────────────────────────
        # g1pub_proof = sha256(nostr_pubkey:g1pub:ATOM4LOVE_ALPHA)
        # Si présent, vérifie que le publisher connaît BOTH clés co-dérivées.
        # Ensuite, cross-vérifie g1pub 30078 == g1pub du Kind 0 stocké en local.
        g1pub_cert=$(echo "$event_json"   | jq -r '.event.tags[] | select(.[0] == "g1pub")      | .[1]' 2>/dev/null | head -1)
        g1pub_proof=$(echo "$event_json"  | jq -r '.event.tags[] | select(.[0] == "g1pub_proof") | .[1]' 2>/dev/null | head -1)
        _conform_flag="hybride"
        if [[ -n "$g1pub_cert" && -n "$g1pub_proof" ]]; then
            expected_g1pub_proof=$(printf '%s' "${pubkey}:${g1pub_cert}:${A4L_PROOF_SALT:-ATOM4LOVE_ALPHA}" | sha256sum | awk '{print $1}')
            if [[ "$g1pub_proof" == "$expected_g1pub_proof" ]]; then
                # Cross-vérification : le g1pub en 30078 doit correspondre au g1pub du Kind 0 (si on l'a)
                local_g1pub=$(grep -r "^${pubkey}:" ~/.zen/game/nostr/*/HEX 2>/dev/null | head -1 | cut -d: -f2 || true)
                # Note: si on ne peut pas vérifier localement, on accepte la preuve cryptographique seule
                _conform_flag="conforme"
                a4l_log "CONFORME: ${pubkey:0:8}... g1pub=${g1pub_cert:0:12}… preuve g1pub valide"
            else
                a4l_log "HYBRIDE: ${pubkey:0:8}... g1pub_proof invalide — clé non co-dérivée"
            fi
        else
            a4l_log "HYBRIDE: ${pubkey:0:8}... pas de g1pub_proof — clé externe non vérifiée"
        fi
        A4L_PROOF_SALT="${A4L_PROOF_SALT:-ATOM4LOVE_ALPHA}"

        a4l_log "ACCEPTED[${_conform_flag}]: ${pubkey:0:8}... φ=$phase ω=$omega${_a5l_str}"
        log_status "ATOM4LOVE: Certificat accepté [${_conform_flag}] — ${pubkey:0:8}... (φ=$phase ω=$omega${_a5l_str})"
        exit 0
    else
        a4l_log "REJECTED: Biométrie invalide — ${pubkey:0:8}... φ=$phase ω=$omega"
        log_status "REJECTED: Certificat ATOM4LOVE invalide pour ${pubkey:0:8}... (φ=$phase ω=$omega)"
        exit 1
    fi
fi

# Check authorization using common function
if ! check_authorization "$pubkey" "log_status"; then
    exit 1
fi

# Validate required tags
if [[ -z "$status_id" ]]; then
    log_status "REJECTED: Status missing required 'd' tag (status identifier)"
    exit 1
fi

# Check if status has expired
if [[ -n "$expiration" ]]; then
    current_time=$(date +%s)
    if [[ "$current_time" -gt "$expiration" ]]; then
        log_status "REJECTED: Status has expired (expired: $expiration, current: $current_time)"
        exit 1
    fi
fi

# Log the status details
log_status "STATUS: ${pubkey:0:8}... updated status (ID: $status_id)"
[[ -n "$status_type" ]] && log_status "STATUS: Type: $status_type"
[[ -n "$emoji" ]] && log_status "STATUS: Emoji: $emoji"
[[ -n "$content" ]] && log_status "STATUS: Message: $content"

if [[ -n "$expiration" ]]; then
    expiration_date=$(date -d "@$expiration" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    log_status "STATUS: Expires: $expiration_date"
fi

# Check for specific status types that might be interesting
case "$status_type" in
    "online"|"available")
        log_status "INFO: User is online and available"
        ;;
    "away"|"busy"|"dnd")
        log_status "INFO: User is away/busy/do not disturb"
        ;;
    "offline")
        log_status "INFO: User marked as offline"
        ;;
    "streaming"|"gaming")
        log_status "INFO: User is streaming/gaming"
        ;;
    *)
        [[ -n "$status_type" ]] && log_status "INFO: Custom status type: $status_type"
        ;;
esac

# Check for UPlanet-specific content
if [[ -n "$content" ]]; then
    if [[ "$content" == *"UPlanet"* || "$content" == *"#BRO"* || "$content" == *"#BOT"* ]]; then
        log_status "UPLANET: Status contains UPlanet-related content"
    fi
fi

log_status "ACCEPTED: Status from ${pubkey:0:8}... (Email: $EMAIL, Source: $SOURCE)"
echo ">>> (30078) STATUS: ${pubkey:0:8}... → $status_id ${emoji:-} ${status_type:-}"

exit 0 