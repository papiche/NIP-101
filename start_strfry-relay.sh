#!/bin/bash
## THIS SCRIPT IS LAUNCHING "strfry relay"
    echo "$HOME/.zen/strfry/strfry is missing !! "
    exit 1
fi

## CHECK IF ALREADY RUNNING
OLD_PID=$(cat $HOME/.zen/strfry/.pid)

## LAUNCHING NEW RELAY
cd $HOME/.zen/strfry/
mkdir -p strfry-db/
./strfry relay 2>&1>$HOME/.zen/tmp/strfry.log &
echo $! > .pid
cd -

## KILL OLD REALY
if [[ ! -z $OLD_PID ]]; then
    echo "Stopping old strfry PID : $OLD_PID"
    kill -USR1 $OLD_PID
fi

exit 0
