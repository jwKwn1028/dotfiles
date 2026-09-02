# Taskwarrior Reminders Manual

Taskwarrior has no reminder daemon: it stores `scheduled` and `due` datetimes
and shows them in reports, but nothing raises a notification at the right
moment. This documents the piece that closes that gap —
`~/.local/bin/task-notify`, its systemd user timer, and the dunst rules that
colour what it raises.

## Overview

A systemd user timer runs `task-notify` once a minute. Each run is a read plus
`notify-send`, measured at about 7 ms against a 180-task database, so polling
that often is free.

Every run exports pending tasks carrying `scheduled` or `due`, selects future
timed fields that are armed under the rules below, and raises one sticky dunst
popup per reminder once its window opens. A popup waits for a click rather than
expiring, so one cannot be missed by being away from the keyboard.

The timer is enabled by hand, not by `chezmoi apply`:

```sh
systemctl --user daemon-reload
systemctl --user enable --now task-notify.timer
```

It starts with the systemd *user* instance, which starts at login rather than at
boot (`Linger=no`). That is the right moment: dunst needs a graphical session to
draw into.

## What is notified

`scheduled` always; `due` only when the task carries an explicit `remind:`.

| task has | `remind:` | reminds on |
|---|---|---|
| scheduled (± due) | explicit | **scheduled**, at those offsets plus the default |
| scheduled (± due) | absent | **scheduled**, at the priority default |
| due only | explicit | **due**, at those offsets plus the default |
| due only | absent | nothing |

A deadline is not an appointment, so `due` raises nothing on its own — typing
`remind:` is the opt-in. When a task carries both fields, `scheduled` wins, so
one task never pops twice for the same offset. A due-based popup says
`due 21:30 · in 2h`, making it obvious which date is being announced.
The countdown rounds partial minutes up, so 14 minutes 31 seconds remaining is
shown as `in 15m` rather than understating the configured lead.

Two things are always skipped.

**A target time already past.** The window is strictly
`now < target <= now + offset`, checked after export for either `scheduled` or
the opted-in `due`. The timer is `Persistent=false`, so a tick missed while the
machine was suspended or off is never caught up. A reminder for a moment that
has gone is worse than no reminder.

**A date without a time of day.** Taskwarrior records no "a time was given"
flag. `scheduled:2026-09-01` and `scheduled:2026-09-01T00:00` are stored
identically, as local midnight:

```
$ jq -rn '"20260831T150000Z"|strptime("%Y%m%dT%H%M%SZ")|mktime|strflocaltime("%H%M%S")'
000000
```

So a local time of exactly `00:00:00` is read as date-only and skipped. The
consequence is real and accepted: a task deliberately scheduled for midnight
gets no reminder. Give it `00:01` if you want one.

## `remind:`

`remind` is a string UDA declared in `~/.taskrc`. Its value is a comma-separated
list of offsets before the selected `scheduled` or `due` time. Each entry is a
number with an optional unit, and **a bare number means hours**:

```sh
task add 'Exam' scheduled:2026-09-01T09:00 remind:1d,2,30m
#   1d -> 24 hours before    2 -> 2 hours before    30m -> 30 minutes before
```

`m`, `h` and `d` are the units; decimals are allowed, so `0.5` is thirty
minutes. Order does not matter.

**The priority default is added, not replaced.** `remind:` buys extra, earlier
warnings; it does not trade the usual one away. So `remind:4` on an unprioritised
task reminds at 4 hours *and* 15 minutes before, and on a `priority:H` task at
4 hours and 30 minutes before. Writing an offset that equals the default, as in
`remind:15m`, collapses to one reminder rather than two.

The corollary is that the default cannot be suppressed: `remind:5m` gives five
minutes *and* fifteen, and there is no spelling for "five minutes only". Lower
`TASK_NOTIFY_LEAD_DEFAULT` if that is not what you want.

### One reminder per tick

With several offsets, only the **smallest offset whose window is open** fires on
any given run. For `remind:1d,2,30m`:

| now is | open offsets | fires |
|---|---|---|
| 25 h before | none | nothing |
| 20 h before | `1d` | the `1d` slot |
| 1 h before | `1d`, `2` | the `2` slot |
| 20 min before | all three | the `30m` slot |

Without this rule, a task created an hour before its scheduled time would have
all three windows open at once and pop three times. It also degrades correctly
after downtime: come back an hour before, having missed the 24-hour mark, and
you get the 2-hour reminder rather than a stale "24 hours to go".

Each slot fires exactly once, because the suppression key is
`uuid field stamp offset`. Rescheduling the task changes the key and re-arms
every slot; any other edit does not.

### Why a string UDA

A `numeric` UDA holds one value, and several offsets are the point. A `duration`
UDA looks like the natural fit but is not: Taskwarrior stores duration values as
the raw string you typed — `"30min"`, `"2h30min"`, `"PT30M"`, the same way
`recur` is stored — which would push a free-form duration parser into the
notifier. A string with one small grammar of its own is simpler and predictable.

The cost is that `remind` is no longer numerically filterable; `task remind.any:`
and substring matches still work, but `task remind.over:20` does not.

### Malformed entries

An entry that does not parse is skipped, and the run logs
`ignoring malformed remind entry` to the journal. Valid entries beside it still
work, so `remind:2,bogus,30m` behaves as `remind:2,30m`. If no entry survives,
the task falls back to its priority default rather than going silent. Zero and
negative offsets are treated the same way.

## Priority

Priority sets both how early a reminder fires and how it looks.

| priority | default lead | environment override | urgency | category | frame |
|---|---|---|---|---|---|
| `H` | 30 min | `TASK_NOTIFY_LEAD_HIGH` | critical | `task.h` | `#f7768e` red |
| `M` | 15 min | `TASK_NOTIFY_LEAD_MEDIUM` | normal | `task.m` | `#e0af68` yellow |
| `L` | 10 min | `TASK_NOTIFY_LEAD_LOW` | low | `task.l` | `#7aa2f7` blue |
| unset | 15 min | `TASK_NOTIFY_LEAD_DEFAULT` | normal | `task.none` | `#86be43` green |

This lead always applies; an explicit `remind:` adds to it rather than replacing
it. The environment overrides take the same offset grammar as `remind:`, so
`TASK_NOTIFY_LEAD_HIGH=2` means two hours.

`task-notify` passes the category through `notify-send --category`, and four
rules in `~/.config/dunst/dunstrc` turn it into a frame colour. Matching is on
`category` rather than `msg_urgency` because dunst has three urgency levels and
there are four buckets here. Urgency is still set, so dunst's own ordering
(`sort = yes`) floats a high-priority reminder to the top of a stack.

The rules are named, so a colour can be toggled live:

```sh
dunstctl rule taskwarrior-priority-high disable
```

## Quick-add shortcuts

`~/.zsh/rc.d/30-aliases.zsh` defines a weekday quick-add DSL whose whole
specification is the command name:

```
t<W><D><d|s>[hml][HH:MM][r<offsets>]
```

- `W` weeks ahead: `0` the Mon-Sun week containing today, through `4`
- `D` ISO weekday, 1 = Monday … 7 = Sunday
- `d` due, `s` scheduled
- `h`/`m`/`l` optional priority
- `HH:MM` optional time of day
- `r` optional reminder offsets, same grammar as `remind:`

```sh
t04s prep slides                  # this Thursday, scheduled, no time
t11s09:30r1,2,3 lecture           # Mon 09:30, remind 3h, 2h, 1h (and 15m) before
t11d21:30r1d,2h,3m paper          # Mon 21:30 due, remind 1 day, 2h, 3m before
t12dh dentist +health             # next week Tuesday, due, priority H, tagged
```

Week `0` counts from Monday, so a weekday earlier than today is in the past. That
would create a task whose reminders can never fire, so it is refused and the
working spelling is named:

```
$ t01s09:30r1,2,3 lecture
t01s09:30r1,2,3: Mon 2026-08-24 is in the past (did you mean t11s09:30r1,2,3?)
```

A shortcut carrying `HH:MM` is judged on the moment, so `t06s09:30` typed on
Saturday afternoon is refused too; a bare shortcut is judged on the day, so
`t06s` still works on the day itself.

The date is computed by the shell, not handed to Taskwarrior as a weekday
synonym: `due:monday` is ambiguous about which Monday it means, while the
shortcut is explicit about the week.

Bad offsets are rejected at the prompt rather than stored. Trailing arguments
pass through to `task add`, so `t12sm16:30 golf remind:1d,2` is equivalent to
writing the offsets in the name, and any other attribute can be appended the
same way.

## Files and state

| path | role |
|---|---|
| `~/.local/bin/task-notify` | the notifier |
| `~/.config/systemd/user/task-notify.timer` | minutely trigger |
| `~/.config/systemd/user/task-notify.service` | the oneshot it starts |
| `~/.taskrc` | declares the `remind` UDA |
| `~/.config/dunst/dunstrc` | the four `taskwarrior-*` rules |
| `~/.config/i3/dunst-start.sh` | gives dunst 1.9 a runtime numeric index for the laptop panel |
| `~/.config/systemd/user/dunst.service.d/override.conf` | launches dunst through that wrapper |
| `~/.local/bin/tests/test-task-notify.sh` | notifier test suite |
| `~/.local/bin/tests/test-task-quick-add.zsh` | quick-add parser test suite |
| `$XDG_RUNTIME_DIR/task-notify/notified` | which reminders have fired |

The state file holds one `uuid field stamp offset` key per fired reminder. It
lives under `XDG_RUNTIME_DIR`, so it is cleared on reboot — nothing is lost,
because a reminder whose time passed while the machine was off must not fire
anyway. Each run rebuilds it from the keys currently in window, so it prunes
itself and cannot grow without bound. The notifier refuses to use a shared
`/tmp` fallback; tests or deliberate isolated runs can set
`TASK_NOTIFY_STATE_DIR` explicitly.

The export runs with `rc.gc=0`, so a background poll never renumbers task IDs
underneath an interactive session, and `rc.hooks=0`, so user hooks stay out of a
timer-driven read.

The service sets `DBUS_SESSION_BUS_ADDRESS` explicitly. `notify-send` needs the
session bus but not `DISPLAY`, and the bus socket path is fixed under
`XDG_RUNTIME_DIR`, so a tick that lands before the i3 session imported its
environment still works. A reminder is recorded only once `notify-send`
succeeds, so a tick that fires before dunst is up retries a minute later instead
of swallowing the popup.

`AccuracySec` is left at its one-minute default so systemd can coalesce the
wakeup. That is irrelevant slop against a ten-minute-plus lead and keeps a
per-minute poll cheap on battery. `WakeSystem` is off, so this never wakes a
suspended laptop.

## Tests

```sh
~/.local/bin/tests/test-task-notify.sh
~/.local/bin/tests/test-task-quick-add.zsh
```

Covers the window and both exclusions, deduplication and re-arming, state
pruning, the retry after a failed `notify-send`, pango escaping, the priority
mapping and default leads, the offset grammar, the smallest-open-offset rule,
malformed entries (including due-only fallback), private runtime state, body
formatting, and priority/time quick-add suffix combinations.

## Troubleshooting

**Nothing fires.** Check the timer is running and when it last did:

```sh
systemctl --user list-timers task-notify.timer
journalctl --user -u task-notify.service -n 20
```

**A specific task never fires.** Most often it is scheduled at local midnight,
or only `due` is set without an explicit `remind:`:

```sh
task <id> export | jq '{scheduled, due, priority, remind}'
```

**See what would fire, without waiting.** Widen the window and point the state
file somewhere disposable, so real suppression is untouched:

```sh
TASK_NOTIFY_LEAD_DEFAULT=1d TASK_NOTIFY_STATE_DIR=$(mktemp -d) task-notify
```

**A popup appeared and was dismissed too fast to read.** Reminders are sticky,
but everything lands in history either way:

```sh
dunstctl history | jq -r '.data[0][] | select(.appname.data == "taskwarrior")
                          | "\(.summary.data)  \(.body.data)"'
```

**Colours look wrong after editing dunstrc.** dunst 1.9.2 has no reload command.
`Super+Shift+I` runs `~/.config/i3/session-reload.sh`, which restarts dunst only
when dunstrc is newer than the running daemon; otherwise restart it by hand.
The service launches `dunst-start.sh`, which leaves the managed config alone and
writes the current laptop-panel index into a private runtime copy:

```sh
systemctl --user restart dunst.service
```

## Quick commands

```sh
task add 'Seminar' scheduled:2026-09-01T12:30 priority:H remind:1d,2,30m
task <id> modify remind:45m            # change the offsets (the default still applies)
task <id> modify remind:                # drop them, back to the priority default
task status:pending remind.any: list    # everything with explicit offsets
systemctl --user start task-notify.service   # force a run now
```
