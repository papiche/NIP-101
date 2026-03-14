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

## Detect hardware profile for tuning
ARCH=$(uname -m)
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
CPU_CORES=$(nproc 2>/dev/null || echo 2)

if [[ "$ARCH" == "aarch64" && $TOTAL_RAM_MB -lt 1024 ]]; then
    ## RPi Zero W2 / low-RAM aarch64 profile (512 Mo)
    echo "Hardware profile: aarch64 low-RAM (${TOTAL_RAM_MB} MB, ${CPU_CORES} cores)"
    STRFRY_MAXREADERS=64
    STRFRY_MAPSIZE=1073741824           # 1 GB
    STRFRY_NOREADAHEAD=true
    STRFRY_MAXEVENTSIZE=65536           # 64 KB
    STRFRY_EPHEMERAL_LIFETIME=300
    STRFRY_MAXNUMTAGS=500
    STRFRY_MAXTAGVALSIZE=512
    STRFRY_NOFILES=4096
    STRFRY_MAXWSPAYLOAD=65536           # 64 KB
    STRFRY_MAXREQFILTERSIZE=20
    STRFRY_AUTOPINGSECONDS=55
    STRFRY_TCPKEEPALIVE=true
    STRFRY_QUERYTIMESLICE=5000          # 5 ms
    STRFRY_MAXFILTERLIMIT=500
    STRFRY_MAXSUBS=5
    STRFRY_COMPRESSION=true
    STRFRY_SLIDINGWINDOW=false          # Saves ~256 KB per connection
    STRFRY_INVALIDEVENTS=true
    STRFRY_INGESTER=1
    STRFRY_REQWORKER=1
    STRFRY_REQMONITOR=1
    STRFRY_NEGENTROPY_THREADS=1
    STRFRY_MAXSYNCEVENTS=100000
elif [[ "$ARCH" == "aarch64" ]]; then
    ## Standard aarch64 (RPi 4/5, 2-8 GB RAM)
    echo "Hardware profile: aarch64 standard (${TOTAL_RAM_MB} MB, ${CPU_CORES} cores)"
    STRFRY_MAXREADERS=256
    STRFRY_MAPSIZE=4294967296           # 4 GB
    STRFRY_NOREADAHEAD=true
    STRFRY_MAXEVENTSIZE=131072
    STRFRY_EPHEMERAL_LIFETIME=600
    STRFRY_MAXNUMTAGS=2000
    STRFRY_MAXTAGVALSIZE=1024
    STRFRY_NOFILES=32000
    STRFRY_MAXWSPAYLOAD=131072
    STRFRY_MAXREQFILTERSIZE=100
    STRFRY_AUTOPINGSECONDS=55
    STRFRY_TCPKEEPALIVE=true
    STRFRY_QUERYTIMESLICE=10000
    STRFRY_MAXFILTERLIMIT=1000
    STRFRY_MAXSUBS=10
    STRFRY_COMPRESSION=true
    STRFRY_SLIDINGWINDOW=false
    STRFRY_INVALIDEVENTS=true
    STRFRY_INGESTER=2
    STRFRY_REQWORKER=2
    STRFRY_REQMONITOR=2
    STRFRY_NEGENTROPY_THREADS=1
    STRFRY_MAXSYNCEVENTS=500000
else
    ## x86_64 server profile
    echo "Hardware profile: x86_64 server (${TOTAL_RAM_MB} MB, ${CPU_CORES} cores)"
    STRFRY_MAXREADERS=512
    STRFRY_MAPSIZE=10737418240          # 10 GB
    STRFRY_NOREADAHEAD=true
    STRFRY_MAXEVENTSIZE=131072
    STRFRY_EPHEMERAL_LIFETIME=600
    STRFRY_MAXNUMTAGS=2000
    STRFRY_MAXTAGVALSIZE=1024
    STRFRY_NOFILES=100000
    STRFRY_MAXWSPAYLOAD=262144
    STRFRY_MAXREQFILTERSIZE=200
    STRFRY_AUTOPINGSECONDS=55
    STRFRY_TCPKEEPALIVE=true
    STRFRY_QUERYTIMESLICE=20000
    STRFRY_MAXFILTERLIMIT=2000
    STRFRY_MAXSUBS=20
    STRFRY_COMPRESSION=true
    STRFRY_SLIDINGWINDOW=true
    STRFRY_INVALIDEVENTS=true
    STRFRY_INGESTER=4
    STRFRY_REQWORKER=4
    STRFRY_REQMONITOR=3
    STRFRY_NEGENTROPY_THREADS=3
    STRFRY_MAXSYNCEVENTS=1000000
fi

cat <<EOF > ~/.zen/strfry/strfry.conf
##
## strfry config — auto-tuned for $ARCH (${TOTAL_RAM_MB} MB RAM, ${CPU_CORES} cores)
##

# Directory that contains the strfry LMDB database (restart required)
db = "./strfry-db/"

dbParams {
    # Maximum number of threads/processes that can simultaneously have LMDB transactions open (restart required)
    maxreaders = $STRFRY_MAXREADERS

    # Size of mmap() to use when loading LMDB (does *not* correspond to disk-space used) (restart required)
    mapsize = $STRFRY_MAPSIZE

    # Disables read-ahead when accessing the LMDB mapping. Reduces IO activity when DB size is larger than RAM. (restart required)
    noReadAhead = $STRFRY_NOREADAHEAD
}

events {
    # Maximum size of normalised JSON, in bytes
    maxEventSize = $STRFRY_MAXEVENTSIZE

    # Events newer than this will be rejected
    rejectEventsNewerThanSeconds = 900

    # Events older than this will be rejected
    rejectEventsOlderThanSeconds = 94608000

    # Ephemeral events older than this will be rejected
    rejectEphemeralEventsOlderThanSeconds = 60

    # Ephemeral events will be deleted from the DB when older than this
    ephemeralEventsLifetimeSeconds = $STRFRY_EPHEMERAL_LIFETIME

    # Maximum number of tags allowed (kind 3 contact lists can have 1000+ tags)
    maxNumTags = $STRFRY_MAXNUMTAGS

    # Maximum size for tag values, in bytes (NIP-94 file metadata may have long URLs)
    maxTagValSize = $STRFRY_MAXTAGVALSIZE
}

relay {
    # Interface to listen on. Use 0.0.0.0 to listen on all interfaces (restart required)
    bind = "0.0.0.0"

    # Port to open for the nostr websocket protocol (restart required)
    port = 7777

    # Set OS-limit on maximum number of open files/sockets (if 0, don't attempt to set) (restart required)
    nofiles = $STRFRY_NOFILES

    # HTTP header that contains the client's real IP, before reverse proxying (ie x-real-ip) (MUST be all lower-case)
    realIpHeader = "x-real-ip"

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
    maxWebsocketPayloadSize = $STRFRY_MAXWSPAYLOAD

    # Maximum number of filters allowed in a REQ
    maxReqFilterSize = $STRFRY_MAXREQFILTERSIZE

    # Websocket-level PING message frequency (should be less than any reverse proxy idle timeouts) (restart required)
    autoPingSeconds = $STRFRY_AUTOPINGSECONDS

    # If TCP keep-alive should be enabled (detect dropped connections to upstream reverse proxy)
    enableTcpKeepalive = $STRFRY_TCPKEEPALIVE

    # How much uninterrupted CPU time a REQ query should get during its DB scan
    queryTimesliceBudgetMicroseconds = $STRFRY_QUERYTIMESLICE

    # Maximum records that can be returned per filter
    maxFilterLimit = $STRFRY_MAXFILTERLIMIT

    # Maximum number of subscriptions (concurrent REQs) a connection can have open at any time
    maxSubsPerConnection = $STRFRY_MAXSUBS

    writePolicy {
        # If non-empty, path to an executable script that implements the writePolicy plugin logic
        plugin = "$HOME/.zen/workspace/NIP-101/relay.writePolicy.plugin/all_but_blacklist.sh"
    }

    compression {
        # Use permessage-deflate compression if supported by client. Reduces bandwidth, but slight increase in CPU (restart required)
        enabled = $STRFRY_COMPRESSION

        # Maintain a sliding window buffer for each connection. Improves compression, but uses more memory (restart required)
        slidingWindow = $STRFRY_SLIDINGWINDOW
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

        # Log reason for invalid event rejection? Helps diagnose ["OK",false,""] responses
        invalidEvents = $STRFRY_INVALIDEVENTS
    }

    numThreads {
        # Ingester threads: route incoming requests, validate events/sigs (restart required)
        ingester = $STRFRY_INGESTER

        # reqWorker threads: Handle initial DB scan for events (restart required)
        reqWorker = $STRFRY_REQWORKER

        # reqMonitor threads: Handle filtering of new events (restart required)
        reqMonitor = $STRFRY_REQMONITOR

        # negentropy threads: Handle negentropy protocol messages (restart required)
        negentropy = $STRFRY_NEGENTROPY_THREADS
    }

    negentropy {
        # Support negentropy protocol messages
        enabled = true

        # Maximum records that sync will process before returning an error
        maxSyncEvents = $STRFRY_MAXSYNCEVENTS
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
