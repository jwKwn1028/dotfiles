#!/bin/sh
# Start xfsettingsd without its own screen layouts; display-setup.sh owns them.

xfconf-query -c keyboards -p /Default/RestoreNumlock --create --type bool --set true
xfconf-query -c displays -p /AutoEnableProfiles --create --type bool --set false
xfconf-query -c displays -p /Notify --create --type int --set 0
xfconf-query -c displays -p /Default --reset --recursive 2>/dev/null
pgrep -x xfsettingsd >/dev/null || exec xfsettingsd
