#!/bin/bash
# Constellation Synchronization Report
# Sends a concise sync summary via NOSTR (UMAP 0.00 key) after each backfill run

[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "SYNC REPORT NEEDS ~/.zen/Astroport.ONE" && exit 1
source ~/.zen/Astroport.ONE/tools/my.sh

REPORT_LOG="$HOME/.zen/strfry/constellation-backfill.log"

# Load KEY="value" lines into shell variables — allowlist strict pour éviter d'écraser PATH/IFS
_ALLOWED_STATS="SYNC_START_TIME|SYNC_END_TIME|TOTAL_EVENTS|IMPORTED_EVENTS|TOTAL_PEERS|\
SUCCESS_PEERS|HEX_PUBKEYS|PROFILES_FOUND|PROFILES_MISSING|SOCIAL_EVENTS|PRIVATE_EVENTS|\
MEDIA_EVENTS|COOP_EVENTS|STATION_EVENTS|CONTENT_EVENTS|FAILURES"

_load_stats() {
    local _line
    while IFS= read -r _line; do
        [[ "$_line" =~ ^([A-Z_]+)=\"(.*)\"$ ]] || continue
        [[ "${BASH_REMATCH[1]}" =~ ^(${_ALLOWED_STATS})$ ]] || continue
        printf -v "${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
    done <<< "$1"
}

# Extract one named metric — retourne 0 si la clé est absente (évite les erreurs arithmétiques)
_val() {
    local v
    v=$(echo "$1" | grep -o "${2}=[0-9]*" | tail -1 | cut -d= -f2)
    echo "${v:-0}"
}

extract_sync_stats() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && echo "Log not found: $log_file" >&2 && return 1

    local start_time end_time sync_stats sync_hex sync_profiles sync_peers sync_import

    start_time=$(grep "Starting Astroport constellation backfill" "$log_file" | head -1 \
                 | sed 's/.*\[\([0-9-]* [0-9:]*\)\].*/\1/')
    end_time=$(grep "Backfill process completed" "$log_file" | head -1 \
               | sed 's/.*\[\([0-9-]* [0-9:]*\)\].*/\1/')
    sync_stats=$(grep "SYNC_STATS:" "$log_file" | tail -1 | sed 's/.*SYNC_STATS: //')
    sync_hex=$(grep "SYNC_HEX:"     "$log_file" | tail -1 | sed 's/.*SYNC_HEX: //')
    sync_profiles=$(grep "SYNC_PROFILES:" "$log_file" | tail -1 | sed 's/.*SYNC_PROFILES: //')
    sync_peers=$(grep "SYNC_PEERS:"  "$log_file" | tail -1 | sed 's/.*SYNC_PEERS: //')
    sync_import=$(grep "SYNC_IMPORT:" "$log_file" | tail -1 | sed 's/.*SYNC_IMPORT: //')

    # ── Group events by functional role ───────────────────────────────────
    # Social identity (kind 0,1,3,6,7) — MULTIPASS + réseau social
    local social=$(( $(_val "$sync_stats" profiles || echo 0)
                   + $(_val "$sync_stats" text     || echo 0)
                   + $(_val "$sync_stats" contacts || echo 0)
                   + $(_val "$sync_stats" reposts  || echo 0)
                   + $(_val "$sync_stats" reactions || echo 0) ))

    # Private comms (kind 4) — DMs NIP-04
    local priv=$(_val "$sync_stats" dms || echo 0)

    # Media (kind 21,22,1063,1222,1244) — vidéos, fichiers IPFS, voix
    local media=$(( $(_val "$sync_stats" videos || echo 0)
                  + $(_val "$sync_stats" files  || echo 0)
                  + $(_val "$sync_stats" voice  || echo 0) ))

    # Cooperative (kind 8,30008,30009,30312,30313,30500-30503,30850,30851,31910)
    # Oracle permits, ORE meetings, badge awards, N² memory, santé économique
    local coop=$(( $(_val "$sync_stats" oracle        || echo 0)
                 + $(_val "$sync_stats" ore_spaces    || echo 0)
                 + $(_val "$sync_stats" ore_meetings  || echo 0)
                 + $(_val "$sync_stats" economic_health || echo 0)
                 + $(_val "$sync_stats" n2_memory     || echo 0)
                 + $(_val "$sync_stats" badge_awards  || echo 0)
                 + $(_val "$sync_stats" badge_definitions || echo 0) ))

    # Station (kind 30800) — coop-config DID publié par la clé STATION
    local station=$(_val "$sync_stats" did || echo 0)

    # Content (kind 30023,30024,31922-31925,10000) — blog, calendrier, analytics
    local content=$(( $(_val "$sync_stats" blog          || echo 0)
                    + $(_val "$sync_stats" nip52_calendar || echo 0)
                    + $(_val "$sync_stats" analytics     || echo 0)
                    + $(_val "$sync_stats" encrypted_analytics || echo 0) ))

    # Failures: lines with error keywords
    local failures
    failures=$(grep -cE "(failed|FAILED|❌ (Batch|WebSocket|P2P))" "$log_file" 2>/dev/null || echo 0)

    cat << EOF
SYNC_START_TIME="$start_time"
SYNC_END_TIME="$end_time"
TOTAL_EVENTS="$(_val "$sync_stats" events)"
IMPORTED_EVENTS="$(_val "$sync_import" events)"
TOTAL_PEERS="$(_val "$sync_peers" total)"
SUCCESS_PEERS="$(_val "$sync_peers" success)"
HEX_PUBKEYS="$(_val "$sync_hex" count)"
PROFILES_FOUND="$(_val "$sync_profiles" found)"
PROFILES_MISSING="$(_val "$sync_profiles" missing)"
SOCIAL_EVENTS="$social"
PRIVATE_EVENTS="${priv:-0}"
MEDIA_EVENTS="$media"
COOP_EVENTS="$coop"
STATION_EVENTS="${station:-0}"
CONTENT_EVENTS="$content"
FAILURES="$failures"
EOF
}

generate_html_report() {
    local stats="$1"
    _load_stats "$stats"

    local status_color="#27ae60"
    local status_label="OK"
    [[ "${FAILURES:-0}" -gt 0 ]] && status_color="#f39c12" && status_label="Partiel"
    [[ "${SUCCESS_PEERS:-0}" -eq 0 ]] && status_color="#e74c3c" && status_label="Échec"

    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>UPlanet Constellation — Sync $(date '+%Y-%m-%d')</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .box { max-width: 640px; margin: 0 auto; background: white; padding: 20px;
               border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,.1); }
        h2 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 6px; }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 12px;
                 color: white; background: $status_color; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; }
        th { background: #ecf0f1; text-align: left; padding: 8px; font-size: 12px;
             text-transform: uppercase; color: #7f8c8d; }
        td { padding: 8px; border-bottom: 1px solid #ecf0f1; }
        td:last-child { text-align: right; font-weight: bold; color: #2c3e50; }
        .err { color: #e74c3c; }
        .footer { text-align: center; margin-top: 16px; font-size: 11px; color: #aaa; }
    </style>
</head>
<body><div class="box">
    <h2>🌍 UPlanet Constellation — Sync Report</h2>
    <p>
        <span class="badge">$status_label</span>
        &nbsp; ${SYNC_START_TIME} → ${SYNC_END_TIME}
        &nbsp;|&nbsp; Node: ${IPFSNODEID:0:16}…
    </p>
    <table>
        <tr><th colspan="2">Réseau</th></tr>
        <tr><td>Peers synchronisés</td><td>${SUCCESS_PEERS:-0} / ${TOTAL_PEERS:-0}</td></tr>
        <tr><td>HEX pubkeys suivis</td><td>${HEX_PUBKEYS:-0}</td></tr>
        <tr><td>Profils trouvés / manquants</td><td>${PROFILES_FOUND:-0} / ${PROFILES_MISSING:-0}</td></tr>
        <tr><td>Events collectés → importés</td><td>${TOTAL_EVENTS:-0} → ${IMPORTED_EVENTS:-0}</td></tr>

        <tr><th colspan="2">Events par catégorie</th></tr>
        <tr><td>Social (kind 0,1,3,6,7 — MULTIPASS)</td><td>${SOCIAL_EVENTS:-0}</td></tr>
        <tr><td>Messages privés (kind 4 — DMs)</td><td>${PRIVATE_EVENTS:-0}</td></tr>
        <tr><td>Médias (kind 21,22,1063,1222)</td><td>${MEDIA_EVENTS:-0}</td></tr>
        <tr><td>Coopératif (Oracle, ORE, N², Badges)</td><td>${COOP_EVENTS:-0}</td></tr>
        <tr><td>Station (kind 30800 coop-config)</td><td>${STATION_EVENTS:-0}</td></tr>
        <tr><td>Contenu (Blog, Calendrier, Analytics)</td><td>${CONTENT_EVENTS:-0}</td></tr>

        <tr><th colspan="2">Erreurs</th></tr>
        <tr><td>Échecs réseau détectés</td>
            <td class="${FAILURES:-0 > 0 && echo err}">${FAILURES:-0}</td></tr>
    </table>
    <div class="footer">
        Généré par UPlanet Constellation Sync — $(date '+%Y-%m-%d %H:%M:%S')
    </div>
</div></body>
</html>
EOF
}

send_sync_report() {
    local captain_email="$1"
    [[ -z "$captain_email" ]] && echo "CAPTAINEMAIL non défini" && return 1

    local stats
    stats=$(extract_sync_stats "$REPORT_LOG") || return 1

    _load_stats "$stats"

    # Skip if nothing happened
    if [[ "${IMPORTED_EVENTS:-0}" -eq 0 && "${FAILURES:-0}" -eq 0 ]]; then
        echo "Nothing to report (0 imports, 0 failures) — skipping"
        return 0
    fi

    # Build NOSTR message
    local status_icon="✅"
    [[ "${FAILURES:-0}" -gt 0 ]] && status_icon="⚠️"
    [[ "${SUCCESS_PEERS:-0}" -eq 0 ]] && status_icon="❌"

    local nostr_content="${status_icon} Constellation Sync — $(date '+%Y-%m-%d %H:%M')

📡 Peers ${SUCCESS_PEERS:-0}/${TOTAL_PEERS:-0}   🔑 ${HEX_PUBKEYS:-0} pubkeys
📥 ${TOTAL_EVENTS:-0} collectés → ${IMPORTED_EVENTS:-0} importés
👤 Profils: ${PROFILES_FOUND:-0} ✓  ${PROFILES_MISSING:-0} manquants

📊 Social   (0,1,3,6,7) : ${SOCIAL_EVENTS:-0}
🔒 DMs      (kind 4)    : ${PRIVATE_EVENTS:-0}
🎬 Médias   (21,22,…)   : ${MEDIA_EVENTS:-0}
🤝 Coop     (Oracle/ORE/N²) : ${COOP_EVENTS:-0}
🏠 Station  (30800-30851)   : ${STATION_EVENTS:-0}
📝 Contenu  (blog/cal/…)    : ${CONTENT_EVENTS:-0}
${FAILURES:+⚠️ Failures: ${FAILURES}}

#UPlanet #Constellation #NOSTR"

    # Upload HTML summary to IPFS for reference
    local temp_html="/tmp/sync_report_$(date +%s).html"
    generate_html_report "$stats" > "$temp_html"
    local report_ipfs
    report_ipfs=$(ipfs add -q "$temp_html" 2>/dev/null)
    rm -f "$temp_html"
    if [[ -n "$report_ipfs" ]]; then
        nostr_content+="
🔗 $(myIpfsGw)/ipfs/$report_ipfs"
    fi

    # Generate UMAP 0.00,0.00 key (same origin as 1.sh system messages)
    local UMAPNSEC
    UMAPNSEC=$("$HOME/.zen/Astroport.ONE/tools/keygen" -t nostr "${UPLANETNAME}0.00" "${UPLANETNAME}0.00" -s)
    [[ -z "$UMAPNSEC" ]] && echo "❌ UMAP key generation failed" && return 1

    local umap_keyfile="/tmp/umap_$(date +%s).nsec"
    echo "NSEC=$UMAPNSEC;" > "$umap_keyfile"
    chmod 600 "$umap_keyfile"

    local nostr_relay="${myRELAY:-ws://127.0.0.1:7777}"
    python3 "$HOME/.zen/Astroport.ONE/tools/nostr_send_note.py" \
        --keyfile "$umap_keyfile" \
        --content "$nostr_content" \
        --relays "$nostr_relay" \
        --ephemeral 3600 \
        --json > /tmp/nostr_sync_result.json 2>&1
    local rc=$?
    rm -f "$umap_keyfile" /tmp/nostr_sync_result.json

    if [[ $rc -eq 0 ]]; then
        echo "✅ Sync report sent via NOSTR ($nostr_relay)"
    else
        echo "❌ Failed to send sync report"
        return 1
    fi
}

main() {
    [[ -z "$CAPTAINEMAIL" ]]   && echo "CAPTAINEMAIL not set" && exit 1
    [[ ! -f "$REPORT_LOG" ]]   && echo "Log not found: $REPORT_LOG" && exit 1
    send_sync_report "$CAPTAINEMAIL"
}

main "$@"
