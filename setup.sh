#!/bin/bash
# Astroport strfry setup

## SET ASTROPORT ENVIRONNEMENT
[[ ! -s ~/.zen/Astroport.ONE/tools/my.sh ]] \
    && echo "STRFRY NODE AUTOMATIC SETUP NEEDS ~/.zen/Astroport.ONE" \
    && exit 1

source ~/.zen/Astroport.ONE/tools/my.sh

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

# Function to collect relay peers from Astroport constellation
collect_relay_peers() {
    local peers=()
    local swarm_dir="$HOME/.zen/tmp/swarm"
    
    if [[ ! -d "$swarm_dir" ]]; then
        echo "Warning: Swarm directory not found: $swarm_dir" >&2
        return 1
    fi
    
    echo "Scanning Astroport constellation for relay peers..." >&2
    
    # Find all 12345.json files in swarm directory
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            # Extract myRELAY value from JSON
            local relay_url=$(grep -o '"myRELAY"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | cut -d'"' -f4)
            
            if [[ -n "$relay_url" && "$relay_url" != "ws://127.0.0.1:7777" ]]; then
                # Convert localhost URLs to actual IP addresses for external access
                if [[ "$relay_url" =~ ws://127\.0\.0\.1:7777 ]]; then
                    # Get the IP from the same file
                    local ip=$(grep -o '"myIP"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | cut -d'"' -f4)
                    if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
                        relay_url="ws://${ip}:7777"
                    fi
                fi
                
                # Add to peers list if not already present
                if [[ ! " ${peers[@]} " =~ " ${relay_url} " ]]; then
                    peers+=("$relay_url")
                    echo "  Found peer: $relay_url" >&2
                fi
            fi
        fi
    done < <(find "$swarm_dir" -name "12345.json" -print0)
    
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

# Create router configuration for inter-relay synchronization if peers are found
if [[ -n "$RELAY_PEERS" ]]; then
    echo "Creating strfry router configuration for constellation synchronization..."
    
    # Convert space-separated peers to array format for config
    peers_array=($RELAY_PEERS)
    urls_config=""
    for peer in "${peers_array[@]}"; do
        if [[ -n "$urls_config" ]]; then
            urls_config="${urls_config}\n                \"$peer\""
        else
            urls_config="                \"$peer\""
        fi
    done
    
    cat <<EOF > ~/.zen/strfry/strfry-router.conf
# Astroport constellation inter-relay synchronization configuration
# This file configures strfry router for bidirectional event streaming with constellation peers

connectionTimeout = 30

streams {
    # Bi-directional streaming within Astroport constellation
    constellation {
        dir = "both"
        
        # Filter to focus on UPlanet-related events and avoid spam
        filter = { 
            "kinds": [0, 1, 3, 22242],  # Profiles, text notes, contacts, auth events
            "limit": 1000
        }
        
        urls = [
$urls_config
        ]
    }
}
EOF

    echo "Router configuration created: ~/.zen/strfry/strfry-router.conf"
    echo "To start constellation synchronization, run: strfry router ~/.zen/strfry/strfry-router.conf"
else
    echo "No constellation peers found - router configuration not created"
fi

echo "Strfry configuration completed successfully!"
echo "Main config: ~/.zen/strfry/strfry.conf"
if [[ -n "$RELAY_PEERS" ]]; then
    echo "Router config: ~/.zen/strfry/strfry-router.conf"
    echo "Constellation peers: $RELAY_PEERS"
fi
