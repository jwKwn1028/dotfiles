# Hardware assumptions

This source state was written on a ThinkPad P16s Gen 4 (AMD). On other
hardware running the same OS, the rest applies unchanged: display, lid, and
battery-threshold logic detects the hardware or skips itself. The five places
below name this machine's devices. Elsewhere they fail silently, so check them
after the first `chezmoi apply`.

Get the new machine's names with:

```sh
xinput list                    # X pointer device names
sensors -u                     # hwmon chips, labels, and keys
ls /sys/class/power_supply     # battery and adapter names
```

1. **`dot_local/bin/executable_touchpad`** matches the built-in pad with
   `MATCH`, default `ELAN0688`. With no match, the `touchpad apply` that i3
   runs at startup finds nothing and the pad stays enabled. Change the
   default, or export `TOUCHPAD_MATCH` in the environment i3 starts from.

2. **`dot_config/xfce4/xfconf/private_xfce-perchannel-xml/pointers.xml`** keys
   settings by X device name (`ELAN068800_04F3320B_Touchpad`,
   `TPPS2_Elan_TrackPoint`). A new built-in pad and TrackPoint get libinput
   defaults: no tap-to-click, no natural scrolling, default acceleration. The
   external TrackPoint Keyboard II and Logitech receiver entries still match.
   Set them in `xfce4-mouse-settings`, then `chezmoi re-add` the file.

3. **`dot_zsh/rc.d/60-sysmon.zsh`** reads `k10temp`/`Tctl` (AMD CPU),
   `amdgpu`/`edge`, and `thinkpad` `fan1`/`fan2` from `sensors -u`, and GPU
   load from amdgpu's `gpu_busy_percent`. Missing sensors read 0. Swap in the
   new chip and label names (an Intel CPU is `coretemp`, `Package id 0`).

4. **`dot_config/fastfetch/config.jsonc`**: the `Fan` command reads the hwmon
   named `thinkpad` and prints `N/A` without it. Point it at the new fan chip
   or drop the module.

5. **`dot_config/polybar/config.ini`** sets `battery = BAT0` and
   `adapter = AC`. Other names (`BAT1`, `ADP1`, `ACAD`) leave the module
   missing or show the wrong charging state. Use the names from
   `/sys/class/power_supply`; a desktop with no battery just disables the
   module.
