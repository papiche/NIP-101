#!/bin/bash
# Astroport strfry setup

## SET ASTROPORT ENVIRONNEMENT
[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "STRFRY NODE AUTOMATIC SETUP NEEDS ~/.zen/Astroport.ONE" \
    && exit 1

source ~/.zen/Astroport.ONE/tools/my.sh

# Import only the discover_constellation_peers function from backfill_constellation.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/backfill_constellation.sh" ]]; then
    # Extract only the discover_constellation_peers function
    DISCOVER_FUNCTION=$(sed -n '/^# Function to discover constellation peers from IPNS swarm$/,/^}$/p' "$SCRIPT_DIR/backfill_constellation.sh")
    
    # Define the function in this script
    eval "$DISCOVER_FUNCTION"
else
    echo "Error: backfill_constellation.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Parse command line arguments
DRYRUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --DRYRUN)
            DRYRUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--DRYRUN]"
            exit 1
            ;;
    esac
done

# Function to collect relay peers from Astroport constellation using backfill functions
collect_relay_peers() {
    echo "Scanning Astroport constellation for relay peers..." >&2
    
    # Use the robust discover_constellation_peers function from backfill_constellation.sh
    local discovered_peers=$(discover_constellation_peers 2>/dev/null)
    
    if [[ -z "$discovered_peers" ]]; then
        echo "Warning: No constellation peers discovered" >&2
        return 1
    fi
    
    # Convert the discovered peers format to simple URLs for setup
    local peers=()
    while IFS= read -r peer; do
        if [[ "$peer" =~ ^routable:(.+)$ ]]; then
            # Routable relay - extract the URL
            local url="${BASH_REMATCH[1]}"
            peers+=("$url")
            echo "  Found routable peer: $url" >&2
        elif [[ "$peer" =~ ^localhost:([^:]+):(.+)$ ]]; then
            # Localhost relay with P2P tunnel - convert to external IP if available
            local ipfsnodeid="${BASH_REMATCH[1]}"
            local x_strfry_script="${BASH_REMATCH[2]}"
            
            # Try to get external IP from the 12345.json file
            local json_file="$HOME/.zen/tmp/swarm/$ipfsnodeid/12345.json"
            if [[ -f "$json_file" ]]; then
                local external_ip=$(jq -r '.myIP // empty' "$json_file" 2>/dev/null)
                if [[ -n "$external_ip" && "$external_ip" != "127.0.0.1" ]]; then
                    local url="ws://${external_ip}:7777"
                    peers+=("$url")
                    echo "  Found localhost peer with external IP: $url" >&2
                else
                    echo "  Found localhost peer (no external IP): $ipfsnodeid" >&2
                fi
            fi
        fi
    done <<< "$discovered_peers"
    
    # Return peers as space-separated string (to stdout)
    printf '%s' "${peers[*]}"
}

# Collect relay peers from constellation
RELAY_PEERS=$(collect_relay_peers)
if [[ -n "$RELAY_PEERS" ]]; then
    echo "Relay peers found: $RELAY_PEERS"
else
    echo "No relay peers found in constellation"
fi

if [[ "$DRYRUN" == "true" ]]; then
    echo "DRY RUN MODE - Configuration files will not be created"
    echo "Relay peers that would be configured: $RELAY_PEERS"
    exit 0
fi

cat <<EOF > ~/.zen/strfry/strfry.conf
##
## Default strfry config
##

# Directory that contains the strfry LMDB database (restart required)
db = "./strfry-db/"

dbParams {
    # Maximum number of threads/processes that can simultaneously have LMDB transactions open (restart required)
    maxreaders = 512

    # Size of mmap() to use when loading LMDB (default is 10GB, does *not* correspond to disk-space used) (restart required)
    mapsize = 10737418240

    # Disables read-ahead when accessing the LMDB mapping. Reduces IO activity when DB size is larger than RAM. (restart required)
    noReadAhead = true
}

events {
    # Maximum size of normalised JSON, in bytes
    maxEventSize = 131072

    # Events newer than this will be rejected
    rejectEventsNewerThanSeconds = 900

    # Events older than this will be rejected
    rejectEventsOlderThanSeconds = 94608000

    # Ephemeral events older than this will be rejected
    rejectEphemeralEventsOlderThanSeconds = 60

    # Ephemeral events will be deleted from the DB when older than this
    ephemeralEventsLifetimeSeconds = 300

    # Maximum number of tags allowed
    maxNumTags = 200

    # Maximum size for tag values, in bytes
    maxTagValSize = 512
}

relay {
    # Interface to listen on. Use 0.0.0.0 to listen on all interfaces (restart required)
    bind = "0.0.0.0"

    # Port to open for the nostr websocket protocol (restart required)
    port = 7777

    # Set OS-limit on maximum number of open files/sockets (if 0, don't attempt to set) (restart required)
    nofiles = 100000

    # HTTP header that contains the client's real IP, before reverse proxying (ie x-real-ip) (MUST be all lower-case)
    realIpHeader = ""

    info {
        # NIP-11: Name of this server. Short/descriptive (< 30 characters)
        name = "♥️BOX $IPFSNODEID"

        # NIP-11: Detailed information about relay, free-form
        description = "This is an Astroport.ONE instance forging HUMAN/MACHINE Trust over Web3 on UPlanet:${UPLANETG1PUB:0:8}"

        # NIP-11: Administrative nostr pubkey, for contact purposes
        pubkey = "$CAPTAINHEX"

        # NIP-11: Alternative administrative contact (email, website, etc)
        contact = "$CAPTAINEMAIL"

        # NIP-11: URL pointing to an image to be used as an icon for the relay
        icon = "https://ipfs.copylaradio.com/ipfs/QmfBK5h8R4LjS2qMtHKze3nnFrtdm85pCbUw3oPSirik5M/logo.uplanet.png"

        # List of supported lists as JSON array, or empty string to use default. Example: "[1,2]"
        nips = ""
    }

    # Maximum accepted incoming websocket frame size (should be larger than max event) (restart required)
    maxWebsocketPayloadSize = 262144

    # Maximum number of filters allowed in a REQ
    maxReqFilterSize = 200

    # Websocket-level PING message frequency (should be less than any reverse proxy idle timeouts) (restart required)
    autoPingSeconds = 55

    # If TCP keep-alive should be enabled (detect dropped connections to upstream reverse proxy)
    enableTcpKeepalive = false

    # How much uninterrupted CPU time a REQ query should get during its DB scan
    queryTimesliceBudgetMicroseconds = 10000

    # Maximum records that can be returned per filter
    maxFilterLimit = 500

    # Maximum number of subscriptions (concurrent REQs) a connection can have open at any time
    maxSubsPerConnection = 10

    writePolicy {
        # If non-empty, path to an executable script that implements the writePolicy plugin logic
        plugin = "$HOME/.zen/workspace/NIP-101/relay.writePolicy.plugin/all_but_blacklist.sh"
    }

    compression {
        # Use permessage-deflate compression if supported by client. Reduces bandwidth, but slight increase in CPU (restart required)
        enabled = true

        # Maintain a sliding window buffer for each connection. Improves compression, but uses more memory (restart required)
        slidingWindow = true
    }

    logging {
        # Dump all incoming messages
        dumpInAll = false

        # Dump all incoming EVENT messages
        dumpInEvents = false

        # Dump all incoming REQ/CLOSE messages
        dumpInReqs = false

        # Log performance metrics for initial REQ database scans
        dbScanPerf = false

        # Log reason for invalid event rejection? Can be disabled to silence excessive logging
        invalidEvents = false
    }

    numThreads {
        # Ingester threads: route incoming requests, validate events/sigs (restart required)
        ingester = 3

        # reqWorker threads: Handle initial DB scan for events (restart required)
        reqWorker = 3

        # reqMonitor threads: Handle filtering of new events (restart required)
        reqMonitor = 3

        # negentropy threads: Handle negentropy protocol messages (restart required)
        negentropy = 2
    }

    negentropy {
        # Support negentropy protocol messages
        enabled = true

        # Maximum records that sync will process before returning an error
        maxSyncEvents = 1000000
    }
}
EOF

# Display constellation peers information for backfill
if [[ -n "$RELAY_PEERS" ]]; then
    echo "Constellation peers discovered for backfill:"
    echo "$RELAY_PEERS" | tr ' ' '\n' | sed 's/^/  - /'
    echo ""
    echo "These peers will be used by backfill_constellation.sh for historical event retrieval"
    echo "The backfill system runs automatically after 12:00 via _12345.sh"
else
    echo "No constellation peers found - backfill will not be possible"
fi

echo "Strfry configuration completed successfully!"
echo "Main config: ~/.zen/strfry/strfry.conf"
if [[ -n "$RELAY_PEERS" ]]; then
    echo "Constellation peers: $RELAY_PEERS"
fi
echo ""
echo "The constellation backfill system is now configured and will run automatically via _12345.sh"
