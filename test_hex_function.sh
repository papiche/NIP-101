#!/bin/bash

# Test script for get_constellation_hex_pubkeys function

# Source the main script to get the function
source ./backfill_constellation.sh

# Test the function
echo "Testing get_constellation_hex_pubkeys function..."
echo "================================================"

# Call the function
result=$(get_constellation_hex_pubkeys)

echo "Function returned:"
echo "$result"

echo ""
echo "Number of lines returned:"
echo "$result" | wc -l

echo ""
echo "First few pubkeys:"
echo "$result" | head -5
