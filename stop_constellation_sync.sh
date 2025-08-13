#!/bin/bash
# Astroport constellation synchronization stop script

PID_FILE="$HOME/.zen/strfry/constellation-sync.pid"

if [[ ! -f "$PID_FILE" ]]; then
    echo "No constellation synchronization PID file found"
    exit 0
fi

PID=$(cat "$PID_FILE")
if [[ -z "$PID" ]]; then
    echo "Invalid PID file content"
    rm -f "$PID_FILE"
    exit 1
fi

if kill -0 "$PID" 2>/dev/null; then
    echo "Stopping constellation synchronization (PID: $PID)..."
    kill "$PID"
    
    # Wait for graceful shutdown
    for i in {1..10}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "✅ Constellation synchronization stopped successfully"
            rm -f "$PID_FILE"
            exit 0
        fi
        sleep 1
    done
    
    # Force kill if still running
    echo "Force killing constellation synchronization..."
    kill -9 "$PID"
    rm -f "$PID_FILE"
    echo "✅ Constellation synchronization force stopped"
else
    echo "Constellation synchronization is not running"
    rm -f "$PID_FILE"
fi
