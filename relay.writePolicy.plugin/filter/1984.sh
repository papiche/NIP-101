#!/bin/bash
# filter/1984.sh (OPTIMIZED)
# This script handles Nostr events of kind:1984 (reporting events)

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Define log file and ensure directory exists
LOG_FILE="$HOME/.zen/tmp/nostr_reports.1984.log"
ensure_log_dir "$LOG_FILE"

# Logging function for reports
log_report() {
    log_with_timestamp "$LOG_FILE" "$1"
}

# Extract event data in one optimized call
event_json="$1"
extract_event_data "$event_json"

# Extract specific tags for kind 1984 events
extract_tags "$event_json" "p" "e" "report-type" "reason"
reported_pubkey="$p"
reported_event_id="$e"
report_type="$report_type"
reason="$reason"

# Check authorization using common function
if ! check_authorization "$pubkey" "log_report"; then
    exit 1
fi

# Validate required tags
if [[ -z "$reported_pubkey" ]]; then
    log_report "REJECTED: Report missing required 'p' tag (reported user pubkey)"
    exit 1
fi

if [[ -z "$report_type" ]]; then
    log_report "REJECTED: Report missing required 'report-type' tag"
    exit 1
fi

# Check if reported user is part of UPlanet using common function
if check_authorization "$reported_pubkey" "log_report" 2>/dev/null; then
    reported_in_uplanet=true
    reported_email="$EMAIL"
    reported_source="$SOURCE"
    log_report "REPORT: ${pubkey:0:8}... reported ${reported_pubkey:0:8}... (UPlanet member: $reported_email from $reported_source)"
else
    reported_in_uplanet=false
    log_report "REPORT: ${pubkey:0:8}... reported external user ${reported_pubkey:0:8}..."
fi

# Log report details
log_report "REPORT: Type: $report_type"
[[ -n "$reported_event_id" ]] && log_report "REPORT: Event being reported: ${reported_event_id:0:8}..."
[[ -n "$reason" ]] && log_report "REPORT: Reason: $reason"
[[ -n "$content" ]] && log_report "REPORT: Additional details: $content"

# Check for specific report types that might require immediate action
case "$report_type" in
    "spam"|"impersonation"|"harassment"|"illegal")
        log_report "URGENT: High-priority report type detected: $report_type"
        # Could trigger additional moderation actions here
        ;;
    "fake"|"scam"|"phishing")
        log_report "WARNING: Security-related report type: $report_type"
        ;;
    *)
        log_report "INFO: Standard report type: $report_type"
        ;;
esac

log_report "ACCEPTED: Report from ${pubkey:0:8}... (Email: $EMAIL, Source: $SOURCE)"
echo ">>> (1984) REPORT: ${pubkey:0:8}... → ${reported_pubkey:0:8}... ($report_type)"

exit 0 