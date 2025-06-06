#!/bin/bash
## THIS SCRIPT IS LAUNCHING "strfry relay"

if [[ ! -x $HOME/.zen/strfry/strfry ]]; then
    echo "$HOME/.zen/strfry/strfry is missing !! "
    exit 1
fi

## CHECK IF ALREADY RUNNING
OLD_PID=$(cat $HOME/.zen/strfry/.pid 2>/dev/null)

## KILL OLD RELAY FIRST
if [[ ! -z $OLD_PID ]]; then
    echo "Stopping old strfry PID : $OLD_PID"
    kill -USR1 $OLD_PID 2>/dev/null
    sleep 1
fi

## LAUNCHING NEW RELAY
cd $HOME/.zen/strfry/
[[ ! -d strfry-db/ ]] && mkdir -p strfry-db/

./strfry relay &
echo $! > .pid
cd - >/dev/null 2>&1

exit 0
