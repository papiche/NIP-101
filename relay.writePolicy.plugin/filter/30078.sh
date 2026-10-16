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
    # 1. Vérifier la présence d'un marqueur d'app (a4l_proof non vide, pas de liste blanche à maintenir)
    actual_proof=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "a4l_proof") | .[1]' 2>/dev/null | head -1)
    if [[ -z "$actual_proof" ]]; then
        log_status "REJECTED: a4l_proof manquant pour ${pubkey:0:8}..."
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

        a4l_log "ACCEPTED: ${pubkey:0:8}... φ=$phase ω=$omega${_a5l_str}"
        log_status "ATOM4LOVE: Certificat accepté — ${pubkey:0:8}... (φ=$phase ω=$omega${_a5l_str})"

        # Persistance dans atom4love_certified.txt (survit au reset 20h12 de amisOfAmis)
        _cert_file="$HOME/.zen/strfry/atom4love_certified.txt"
        touch "$_cert_file"
        grep -v "^${pubkey}:" "$_cert_file" > "${_cert_file}.tmp" && mv "${_cert_file}.tmp" "$_cert_file"
        echo "${pubkey}:${created_at}" >> "$_cert_file"

        exit 0
    else
        a4l_log "REJECTED: Biométrie invalide — ${pubkey:0:8}... φ=$phase ω=$omega"
        log_status "REJECTED: Certificat ATOM4LOVE invalide pour ${pubkey:0:8}... (φ=$phase ω=$omega)"
        exit 1
    fi
fi

# ── d=atom4love-home — localisation home semi-publique ────────────────────────
# Seule contrainte : a4l_proof valide. Rafraîchit l'horodatage dans certified.txt.
if [[ "$status_id" == "atom4love-home" ]]; then
    _home_proof=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "a4l_proof") | .[1]' 2>/dev/null | head -1)
    if [[ -z "$_home_proof" ]]; then
        log_status "REJECTED: atom4love-home sans a4l_proof — ${pubkey:0:8}..."
        exit 1
    fi
    # Rafraîchir l'horodatage dans certified.txt (crée l'entrée si nouvelle, renouvelle le TTL 180j)
    _cert_file="$HOME/.zen/strfry/atom4love_certified.txt"
    touch "$_cert_file"
    grep -v "^${pubkey}:" "$_cert_file" > "${_cert_file}.tmp" && mv "${_cert_file}.tmp" "$_cert_file"
    echo "${pubkey}:${created_at}" >> "$_cert_file"
    log_status "ATOM4LOVE-HOME: TTL rafraîchi — ${pubkey:0:8}..."
    log_status "ACCEPTED: atom4love-home — ${pubkey:0:8}..."
    exit 0
fi

# ── d=atom4love-priv — données privées chiffrées NIP-44 ──────────────────────
# Seule contrainte : a4l_proof valide. Le contenu est opaque (chiffré).
if [[ "$status_id" == "atom4love-priv" ]]; then
    _priv_proof=$(echo "$event_json" | jq -r '.event.tags[] | select(.[0] == "a4l_proof") | .[1]' 2>/dev/null | head -1)
    if [[ -z "$_priv_proof" ]]; then
        log_status "REJECTED: atom4love-priv sans a4l_proof — ${pubkey:0:8}..."
        exit 1
    fi
    log_status "ACCEPTED: atom4love-priv (chiffré) — ${pubkey:0:8}..."
    exit 0
fi

# ── d=facecloud:* — données FaceCloud chiffrées NIP-44 pour soi-même ──────────
# (UPassport/ucloud_backup.py : pointeur vers la sauvegarde chiffrée du cloud,
# d=facecloud:backup). Réservé aux MULTIPASS autorisés ; le contenu est opaque
# et n'est JAMAIS journalisé (contrairement aux statuts ci-dessous).
if [[ "$status_id" == facecloud:* ]]; then
    if ! check_authorization "$pubkey" "log_status"; then
        exit 1
    fi
    log_status "ACCEPTED: ${status_id} (chiffré) — ${pubkey:0:8}..."
    exit 0
fi

# ── d=skillmap:<skill>:<hex membre> — annuaire du coin (UPassport/services/skill_map.py) ──
# Signé par la clé de la CASE (UMAP / SECTOR / REGION, dérivée de la clé de la coopérative) : cette clé n'est pas un MULTIPASS, donc
# l'autorisation porte sur le MEMBRE annoncé (tag p), qui doit être un MULTIPASS connu (local ou swarm). Les clients ne lisent que les
# auteurs dont ils ont dérivé la clé de case, et revérifient le certificat du membre : cet événement n'est qu'un index.
if [[ "$status_id" == skillmap:* ]]; then
    _sm_member=$(echo "$event_json" | jq -r '.event.tags[]? | select(.[0] == "p") | .[1]' 2>/dev/null | head -1)
    _sm_skill=$(echo "$event_json" | jq -r '.event.tags[]? | select(.[0] == "t") | .[1]' 2>/dev/null | head -1)
    if [[ ! "$_sm_member" =~ ^[0-9a-f]{64}$ || -z "$_sm_skill" ]]; then
        log_status "REJECTED: ${status_id} sans membre (p) ou savoir-faire (t) valides — ${pubkey:0:8}..."
        exit 1
    fi
    if ! check_authorization "$_sm_member" "log_status"; then
        log_status "REJECTED: ${status_id} — membre ${_sm_member:0:8}... inconnu de la constellation"
        exit 1
    fi
    log_status "ACCEPTED: ${status_id} (annuaire du coin, case ${pubkey:0:8}...)"
    exit 0
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