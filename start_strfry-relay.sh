#!/bin/bash
## THIS SCRIPT IS LAUNCHING "strfry relay"

if [[ ! -x $HOME/.zen/strfry/strfry ]]; then
echo "$HOME/.zen/strfry/strfry is missing !! "
exit 1
fi

## CHECK IF ALREADY RUNNING
OLD_PID=$(cat $HOME/.zen/strfry/.pid)

## LAUNCHING NEW RELAY
cd $HOME/.zen/strfry/
[[ ! -d strfry-db/ ]] && mkdir -p strfry-db/

./strfry relay &
echo $! > .pid
cd -

## KILL OLD REALY
if [[ ! -z $OLD_PID ]]; then
echo "Stopping old strfry PID : $OLD_PID"
    kill $OLD_PID
    kill -USR1 $OLD_PID
fi

exit 0