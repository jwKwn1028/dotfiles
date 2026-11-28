#!/bin/sh
# Start xfsettingsd, leaving the screen layout to display-setup.sh: at start it
# applies its stored Default layout, and on hotplug a matching profile.

xfconf-query -c keyboards -p /Default/RestoreNumlock --create --type bool --set true
xfconf-query -c displays -p /AutoEnableProfiles --create --type bool --set false
xfconf-query -c displays -p /Notify --create --type int --set 0
xfconf-query -c displays -p /Default --reset --recursive 2>/dev/null
pgrep -x xfsettingsd >/dev/null || exec xfsettingsd
