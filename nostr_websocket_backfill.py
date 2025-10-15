#!/usr/bin/env python3
"""
Nostr WebSocket Backfill Script
Permanent script used by backfill_constellation.sh for WebSocket connections
"""

import asyncio
import websockets
import json
import sys
import time


async def backfill_websocket(websocket_url, req_message, response_file, timeout=30):
    """
    Connect to a Nostr relay via WebSocket and collect events.
    
    Args:
        websocket_url: WebSocket URL (ws:// or wss://)
        req_message: JSON REQ message to send
        response_file: Path to save collected events
        timeout: Maximum time to collect events (default 30s)
    
    Returns:
        Number of events collected
    """
    try:
        async with websockets.connect(
            websocket_url, 
            ping_interval=None, 
            ping_timeout=None
        ) as websocket:
            print(f"Connected to {websocket_url}")
            
            # Send the REQ message
            await websocket.send(req_message)
            print(f"Sent request")
            
            # Collect events
            events = []
            start_time = time.time()
            recv_timeout = 10 if timeout == 30 else 5
            
            while time.time() - start_time < timeout:
                try:
                    message = await asyncio.wait_for(
                        websocket.recv(), 
                        timeout=recv_timeout
                    )
                    data = json.loads(message)
                    
                    if isinstance(data, list) and len(data) > 0:
                        if data[0] == "EVENT":
                            events.append(data[2])  # The event object
                        elif data[0] == "EOSE":
                            print("Received EOSE, ending collection")
                            break
                        elif data[0] == "NOTICE":
                            print(f"Notice: {data[1]}")
                        elif data[0] == "OK":
                            print(f"OK: {data[1]} - {data[2]}")
                except asyncio.TimeoutError:
                    continue
                except Exception as e:
                    print(f"Error processing message: {e}")
                    break
            
            # Save events to file
            with open(response_file, 'w') as f:
                json.dump(events, f, indent=2)
            
            print(f"Collected {len(events)} events")
            return len(events)
            
    except Exception as e:
        print(f"WebSocket error: {e}")
        return 0


def main():
    """Main entry point"""
    if len(sys.argv) not in [4, 5]:
        print("Usage: python3 nostr_websocket_backfill.py <websocket_url> <req_message> <response_file> [timeout]")
        sys.exit(1)
    
    websocket_url = sys.argv[1]
    req_message = sys.argv[2]
    response_file = sys.argv[3]
    timeout = int(sys.argv[4]) if len(sys.argv) == 5 else 30
    
    result = asyncio.run(
        backfill_websocket(websocket_url, req_message, response_file, timeout)
    )
    sys.exit(0 if result > 0 else 1)


if __name__ == "__main__":
    main()

