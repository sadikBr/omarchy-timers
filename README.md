# Omarchy Timers

Named timers, alarms and stopwatches for [Omarchy](https://omarchy.org), built as an Omarchy shell (Quickshell) plugin. It replaces the stock reminder: when a timer runs out it **rings like a phone alarm**. A full-screen alarm shows the timer's title with big **Snooze** and **Stop** buttons, and the sound loops until you deal with it.

## Starting a timer

Press **SUPER+CTRL+R** (or click the alarm-clock icon next to the clock), type, press Enter:

| You type | You get |
|---|---|
| `10m tea` in the title field | a 10 minute timer called "Tea" |
| title `Laundry`, duration `45` | a 45 minute "Laundry" timer (a plain number means minutes) |
| `1h30`, `1h 30m`, `90s`, `2.5` | the obvious durations |
| `4:30`, `1:00:00` | m:ss and h:mm:ss, like a phone timer |
| `at 7:30`, `@14:00`, `7pm` | an alarm at that time of day (today, or tomorrow if it has passed) |

The line under the duration field shows what will happen ("25m · rings at 14:32 · “Report”") before you press Enter. You can also:

- Click a **preset** (1m … 1h) to start right away, using the title typed so far
- Click a **Recent** chip to run a previous timer again
- Switch to **Stopwatch** (Ctrl+Tab) and press Enter to start a stopwatch with that title

Any number of timers and stopwatches can run at the same time.

## When it rings

- The alarm sound loops. With *Get louder* on, it starts soft and rises to full volume
- A full-screen alarm covers every monitor: ringing bell, title, how long ago it went off
- **Stop**: Enter, Space or Esc. **Snooze**: S (default 5 min)
- A critical notification is sent too, so you see it even with notifications silenced
- If nobody answers for *Ring for* minutes (default 5), it stops and you get a "Missed" notification
- Timers that ran out while the shell was restarting or the laptop was asleep ring when it comes back. If that was too long ago, they count as missed

## Bar widget

Alarm-clock icon when idle. Otherwise it shows the time left on the timer that ends first (or a running stopwatch) with a progress line, plus `+N` when more are running. It turns accent-coloured in the last minute, and shakes and shows the title while ringing.

| Mouse | Action |
|---|---|
| Left click | Open the popup |
| Right click | Stop the alarm, or pause / resume what the bar shows |
| Middle click | Snooze the alarm |
| Scroll | ±1 minute on the timer the bar shows |

## Popup list

Each timer shows a progress ring, title, end time and the time left, with pause/resume, **+1 min** and remove buttons. Finished timers can be started again (an alarm restarts for the same time tomorrow). Stopwatches have **lap** and **reset** and list their last laps with splits. **Clear finished** removes finished timers.

## Settings (gear icon)

| Setting | Default |
|---|---|
| Alarm sound: Marimba, Classic (beep-beep-beep-beep) or Chime. Click one to hear it | Marimba |
| Full-screen alarm (off: sound, notification and bar only) | on |
| Get louder | on |
| Start sound (short tick when a timer starts) | on |
| Snooze length | 5 min |
| Ring for | 5 min |

## Keys

| Key | Action |
|---|---|
| SUPER+CTRL+R | Toggle the popup |
| SUPER+CTRL+ALT+R | Start a stopwatch |
| SUPER+SHIFT+CTRL+R | Stop the ringing alarm |

These replace the stock reminder bindings. The **Trigger > Reminder** entries in the Omarchy menu open the plugin too.

## Command line

The plugin registers a `bsadik.timers` IPC target:

```bash
omarchy-shell bsadik.timers start 10m "Tea"      # start a timer (any duration from the table above)
omarchy-shell bsadik.timers start "at 7:30" "Wake up"
omarchy-shell bsadik.timers stopwatch "Run"      # start a stopwatch
omarchy-shell bsadik.timers list                 # human-readable list with ids
omarchy-shell bsadik.timers status               # JSON
omarchy-shell bsadik.timers stop                 # stop every ringing alarm
omarchy-shell bsadik.timers snooze               # snooze every ringing alarm
omarchy-shell bsadik.timers toggle 3             # pause / resume #3
omarchy-shell bsadik.timers extend 3 5           # add 5 minutes to #3
omarchy-shell bsadik.timers remove 3
omarchy-shell bsadik.timers clearDone            # remove finished timers
omarchy-shell bsadik.timers clear                # remove everything
omarchy-shell bsadik.timers panel                # toggle the popup
```

## Install

```bash
./install.sh              # install or update
./install.sh --uninstall  # remove it and give the keys and menu back to the stock reminder
```

The installer copies `bsadik.timers/` to `~/.config/omarchy/plugins/`, puts the widget after the clock in `~/.config/omarchy/shell.json`, adds a marked block to `~/.config/hypr/bindings.lua` and to `~/.config/omarchy/extensions/omarchy-menu.jsonc`, and restarts the shell. It is safe to re-run. Needs `jq`, `rsync` and `pw-play` (PipeWire), which Omarchy ships.

State (timers, recent list, settings) lives in `~/.local/state/omarchy/bsadik-timers.json`.

## Sounds

The alarm sounds in `bsadik.timers/sounds/` are synthesized from scratch by `tools/make-sounds.py` (standard library only). Edit the patterns there and run `python3 tools/make-sounds.py` to regenerate them, then `./install.sh`.

## Files

| File | What it does |
|---|---|
| `Service.qml` | Engine: timers, persistence, alarm sound loop, notifications, IPC |
| `Timers.js` | Pure helpers: duration parsing, formatting, state normalization |
| `BarWidget.qml` | Bar entry |
| `TimersPanel.qml` | Popup: new timer form, list, settings |
| `ItemRow.qml` | One timer or stopwatch in the list |
| `AlarmOverlay.qml`, `AlarmButton.qml` | Full-screen alarm |
| `SettingRow.qml`, `Stepper.qml` | Small form controls (shared with the pomodoro plugin) |
