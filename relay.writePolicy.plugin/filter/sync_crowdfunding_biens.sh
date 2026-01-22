#!/bin/bash
################################################################################
# sync_crowdfunding_biens.sh - Sync Crowdfunding Biens to amisOfAmis
#
# This script ensures all crowdfunding Bien hex keys are registered in
# amisOfAmis.txt to authorize them for receiving +ZEN payments.
#
# Run this script:
# - At relay startup
# - After creating new crowdfunding projects
# - Periodically via cron to catch any new projects
#
# Usage:
#   ./sync_crowdfunding_biens.sh           # Sync all Biens
#   ./sync_crowdfunding_biens.sh --verbose # With detailed output
#   ./sync_crowdfunding_biens.sh --check   # Only check, don't modify
#
################################################################################

MY_PATH="`dirname \"$0\"`"
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"

# Source common functions
source "$MY_PATH/common.sh"

# Parse arguments
VERBOSE=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --check|-c)
            CHECK_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Sync crowdfunding Bien hex keys to amisOfAmis.txt"
            echo ""
            echo "Options:"
            echo "  --verbose, -v   Show detailed output"
            echo "  --check, -c     Only check, don't modify amisOfAmis"
            echo "  --help, -h      Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

################################################################################
# FUNCTIONS
################################################################################

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$1"
    fi
}

################################################################################
# MAIN LOGIC
################################################################################

echo "=== Crowdfunding Biens Sync ==="
echo "Crowdfunding directory: $CROWDFUNDING_DIR"
echo "amisOfAmis file: $AMISOFAMIS_FILE"
echo ""

# Ensure amisOfAmis file exists
if [[ "$CHECK_ONLY" == "false" ]]; then
    mkdir -p "$(dirname "$AMISOFAMIS_FILE")"
    touch "$AMISOFAMIS_FILE"
fi

# Count variables
total_projects=0
biens_with_hex=0
already_registered=0
newly_registered=0
missing_hex=0

# Process each project
if [[ -d "$CROWDFUNDING_DIR" ]]; then
    for project_dir in "$CROWDFUNDING_DIR"/*/; do
        if [[ -d "$project_dir" ]]; then
            total_projects=$((total_projects + 1))
            project_id=$(basename "$project_dir")
            pubkeys_file="$project_dir/bien.pubkeys"
            
            log_verbose "Processing: $project_id"
            
            if [[ -f "$pubkeys_file" ]]; then
                # Source the pubkeys file to get BIEN_HEX
                source "$pubkeys_file"
                
                if [[ -n "$BIEN_HEX" ]]; then
                    biens_with_hex=$((biens_with_hex + 1))
                    
                    # Check if already in amisOfAmis
                    if grep -q "^$BIEN_HEX$" "$AMISOFAMIS_FILE" 2>/dev/null; then
                        already_registered=$((already_registered + 1))
                        log_verbose "  ✓ Already registered: ${BIEN_HEX:0:16}..."
                    else
                        if [[ "$CHECK_ONLY" == "false" ]]; then
                            # Add to amisOfAmis
                            echo "# Crowdfunding Bien: $project_id" >> "$AMISOFAMIS_FILE"
                            echo "$BIEN_HEX" >> "$AMISOFAMIS_FILE"
                            newly_registered=$((newly_registered + 1))
                            echo "  + ADDED: $project_id (${BIEN_HEX:0:16}...)"
                        else
                            newly_registered=$((newly_registered + 1))
                            echo "  ! MISSING: $project_id (${BIEN_HEX:0:16}...)"
                        fi
                    fi
                else
                    missing_hex=$((missing_hex + 1))
                    log_verbose "  ⚠ No BIEN_HEX found"
                fi
                
                # Unset to avoid carryover
                unset BIEN_HEX BIEN_G1PUB BIEN_NPUB
            else
                missing_hex=$((missing_hex + 1))
                log_verbose "  ⚠ No bien.pubkeys file"
            fi
        fi
    done
else
    echo "No crowdfunding directory found."
fi

################################################################################
# SUMMARY
################################################################################

echo ""
echo "=== Summary ==="
echo "Total projects:      $total_projects"
echo "With Bien hex:       $biens_with_hex"
echo "Already registered:  $already_registered"

if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "Missing (to add):    $newly_registered"
else
    echo "Newly registered:    $newly_registered"
fi

echo "Missing hex keys:    $missing_hex"

if [[ "$CHECK_ONLY" == "true" && $newly_registered -gt 0 ]]; then
    echo ""
    echo "Run without --check to register missing Biens."
fi

echo ""
echo "Done."

exit 0
