#!/bin/bash

if [[ ! -x $HOME/.zen/strfry/strfry ]]; then
    echo "$HOME/.zen/strfry/strfry is missing !! "
    exit 1
fi

## CHECK IF ALREADY RUNNING
OLD_PID=$(cat $HOME/.zen/strfry/.pid)

## KILL OLD REALY
if [[ ! -z $OLD_PID ]]; then
    echo "Stopping old strfry PID : $OLD_PID"
    kill $OLD_PID
else
    killall strfry
fi

rm $HOME/.zen/strfry/.pid

exit 0
