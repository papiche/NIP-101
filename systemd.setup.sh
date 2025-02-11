#!/bin/bash
# CREATE SYSTEMD FOR STRFRY RELAY SERVICE

# [[ -s /etc/systemd/system/strfry.service ]] \
#     && echo "SKIP: strfry.service already exists" \
#     && exit 0

BINPATH="$HOME/.zen/strfry"
[[ ! -d "$BINPATH" ]] && echo "$BINPATH not found, aborting" && exit 1
[[ ! -x "$BINPATH/start.sh" ]] && echo "$BINPATH/start.sh not found, aborting" && exit 1

echo "CREATE SYSTEMD strfry SERVICE >>>>>>>>>>>>>>>>>>"
cat > /tmp/strfry.service <<EOF
[Unit]
Description=NOSTR strfry relay service
After=network.target
Requires=network.target

[Service]
Type=forking
User=_USER_
Restart=always
WorkingDirectory=_BINPATH_
ExecStart=_BINPATH_/start.sh
PIDFile=_BINPATH_/.pid
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

ulimit -n 1000000

# copy to systemd service dir
sudo cp /tmp/strfry.service /etc/systemd/system/
# update user and binpath
sudo sed -i "s~_USER_~$USER~g" /etc/systemd/system/strfry.service
sudo sed -i "s~_BINPATH_~$BINPATH~g" /etc/systemd/system/strfry.service
# reload systemd
sudo systemctl daemon-reload
sudo systemctl enable strfry.service;
sudo systemctl start strfry.service

exit 0
