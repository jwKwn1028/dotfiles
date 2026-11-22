# Hardware assumptions

Targets ThinkPad P16s Gen 4 (AMD). Display/lid/battery logic detects hardware;
check these device-specific settings after applying elsewhere:

```sh
xinput list
sensors -u
ls /sys/class/power_supply
```

| Source | Check on other hardware |
| --- | --- |
| `dot_local/bin/executable_touchpad` | `MATCH=ELAN0688` (override `TOUCHPAD_MATCH`); unmatched pads stay enabled. |
| `dot_config/xfce4/xfconf/private_xfce-perchannel-xml/pointers.xml` | Built-in ELAN/TrackPoint device names; unmatched devices use libinput defaults. Configure with `xfce4-mouse-settings`, then `chezmoi re-add` to preserve changes. |
| `dot_zsh/rc.d/60-sysmon.zsh` | AMD `k10temp/Tctl`, `amdgpu/edge`, `gpu_busy_percent`, ThinkPad `fan1/fan2`; absent readings show 0. Intel commonly uses `coretemp` / `Package id 0`. |
| `dot_config/fastfetch/config.jsonc` | Fan hwmon name `thinkpad`; absent readings show N/A. |
| `dot_config/polybar/config.ini` | `battery=BAT0`, `adapter=AC`; use detected names. No battery disables the module. |
