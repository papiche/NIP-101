#!/bin/bash

# Function to update a specific field in the configuration
update_field() {
    local field=$1
    local value=$2
    local file=$3

    if [ -n "$value" ]; then
        sed -i "/^\s*$field\s*=/ c\\    $field = \"$value\"" "$file"
    fi
}

# Function to display help
show_help() {
    echo "Usage: $(basename $0) [--help] [name] [description] [pubkey] [contact] [icon] [nips]"
    echo "Update relay.info fields in the strfry configuration file."
    echo
    echo "Options:"
    echo "  --help    Display this help message"
    echo
    echo "Arguments:"
    echo "  name        Set the name of the relay"
    echo "  description Set the description of the relay"
    echo "  pubkey      Set the pubkey of the relay"
    echo "  contact     Set the contact information"
    echo "  icon        Set the icon URL"
    echo "  nips        Set the supported NIPs"
    echo
    echo "Empty arguments will not modify the corresponding field."
    exit 0
}

# Check if the configuration file exists
config_file="$HOME/.zen/strfry/strfry.conf"
if [ ! -f "$config_file" ]; then
    echo "Error: $config_file not found."
    exit 1
fi

# Check for --help option or no arguments
if [ "$1" == "--help" ] || [ $# -eq 0 ]; then
    show_help
fi

# Update fields based on provided arguments
[ -n "$1" ] && update_field "name" "$1" "$config_file"
[ -n "$2" ] && update_field "description" "$2" "$config_file"
[ -n "$3" ] && update_field "pubkey" "$3" "$config_file"
[ -n "$4" ] && update_field "contact" "$4" "$config_file"
[ -n "$5" ] && update_field "icon" "$5" "$config_file"
[ -n "$6" ] && update_field "nips" "$6" "$config_file"

echo "relay.info configuration updated successfully."

