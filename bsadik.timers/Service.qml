import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import "Timers.js" as T

// Timers engine. One instance per shell: it owns every timer and stopwatch,
// persists them to disk, rings the alarm, and shows the alarm overlay on
// every screen. Bar widgets (one per monitor) only read from it and call
// into it.
//
// A timer that runs out starts ringing: the alarm sound loops (getting
// louder if enabled) until it is stopped or snoozed, or until `ringFor`
// minutes pass, at which point it is marked missed.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/bsadik-timers.json"
  readonly property string soundDir: Qt.resolvedUrl("sounds/").toString().replace(/^file:\/\//, "")

  // ---------------------------------------------------------------- state

  property var settings: T.defaults().settings
  property var items: []
  property var recent: []
  property int nextId: 1

  property bool loaded: false
  property real now: Date.now()
  // Sound being previewed from the settings, or "" when none.
  property string previewing: ""

  readonly property var timers: items.filter(function(x) { return x.kind === "timer" })
  readonly property var stopwatches: items.filter(function(x) { return x.kind === "stopwatch" })
  readonly property var ringing: timers.filter(function(x) { return x.state === "ringing" })
  readonly property var runningTimers: timers.filter(function(x) { return x.state === "running" })
    .sort(function(a, b) { return a.end - b.end })
  readonly property var runningStopwatches: stopwatches.filter(function(x) { return x.running })
  readonly property bool anyRinging: ringing.length > 0
  readonly property bool anyActive: items.some(function(x) {
    return x.kind === "timer" ? x.state !== "done" : (x.running || x.elapsed > 0)
  })
  readonly property int activeCount: items.filter(function(x) {
    return x.kind === "timer" ? x.state !== "done" : (x.running || x.elapsed > 0)
  }).length
  // The timer that finishes first, for the bar label.
  readonly property var soonest: runningTimers.length > 0 ? runningTimers[0] : null
  readonly property bool fast: runningStopwatches.length > 0
  readonly property bool overlayVisible: loaded && anyRinging && settings.fullscreen

  // ------------------------------------------------------------- lifecycle

  function applyState(text) {
    var raw = null
    try { raw = text ? JSON.parse(text) : null } catch (e) { raw = null }
    var s = T.normalize(raw)
    root.settings = s.settings
    root.items = s.items
    root.recent = s.recent
    root.nextId = s.nextId
    root.now = Date.now()
    root.loaded = true
    // Catch up on anything that ran out while the shell was down. Alarms
    // that rang out long ago are reported as missed rather than rung now.
    var t = root.now
    var limit = root.settings.ringFor * 60000
    var list = root.copy(root.items)
    var missed = []
    list.forEach(function(x) {
      if (x.kind !== "timer") return
      if (x.state === "running" && x.end <= t) { x.state = "ringing"; x.endedAt = x.end }
      if (x.state === "ringing" && t - x.endedAt > limit) { x.state = "done"; missed.push(x) }
    })
    root.items = list
    missed.forEach(function(x) { root.notify("Missed: " + T.defaultTitle(x), "Ended at " + T.timeOfDay(x.endedAt, t), T.icons.alarm) })
    root.save()
  }

  function snapshot() {
    return { settings: root.settings, items: root.items, recent: root.recent, nextId: root.nextId }
  }

  function save() {
    if (root.loaded) saveDebounce.restart()
  }

  // ---------------------------------------------------------------- engine

  function tick() {
    root.now = Date.now()
    if (!root.loaded) return
    var t = root.now
    var limit = root.settings.ringFor * 60000
    var changed = false
    var list = root.items
    var fired = []
    var missed = []
    for (var i = 0; i < list.length; i++) {
      var x = list[i]
      if (x.kind !== "timer") continue
      if (x.state === "running" && x.end <= t) fired.push(x.id)
      else if (x.state === "ringing" && t - x.endedAt > limit) missed.push(x.id)
    }
    if (fired.length === 0 && missed.length === 0) return

    list = root.copy(list)
    list.forEach(function(x) {
      if (fired.indexOf(x.id) >= 0) {
        x.state = "ringing"
        x.endedAt = x.end
        root.notify(T.defaultTitle(x), x.at ? "It's " + T.timeOfDay(x.end, t) : "Time's up · " + T.duration(x.duration) + " timer", T.icons.bellRing, true)
      } else if (missed.indexOf(x.id) >= 0) {
        x.state = "done"
        root.notify("Missed: " + T.defaultTitle(x), "Rang for " + root.settings.ringFor + " min, ended at " + T.timeOfDay(x.endedAt, t), T.icons.alarm)
      }
    })
    root.items = list
    root.save()
  }

  function find(id) {
    for (var i = 0; i < root.items.length; i++) if (root.items[i].id === id) return root.items[i]
    return null
  }

  // Applies `fn` to a copy of item `id` and stores the result.
  function update(id, fn) {
    var list = root.copy(root.items)
    var hit = false
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) { fn(list[i]); hit = true; break }
    }
    if (!hit) return "missing"
    root.items = list
    root.now = Date.now()
    root.save()
    return "ok"
  }

  function add(item) {
    item.id = root.nextId
    root.nextId += 1
    var list = root.copy(root.items)
    list.unshift(item)
    // Drop the oldest finished items when there are too many.
    while (list.length > T.MAX_ITEMS) {
      var idx = -1
      for (var i = list.length - 1; i >= 0; i--) {
        if (list[i].kind === "timer" && list[i].state === "done") { idx = i; break }
      }
      list.splice(idx >= 0 ? idx : list.length - 1, 1)
    }
    root.items = list
    root.now = Date.now()
    root.save()
    return item.id
  }

  // Starts a countdown. `spec` is anything parseDuration reads ("10m",
  // "1h30", "at 7:30"); a duration in the title ("10m tea") is used when
  // `spec` is empty. Returns the new id, or 0 when nothing could be read.
  function startTimer(spec, title) {
    var t = Date.now()
    var d = T.parseDuration(spec, t)
    var name = T.cleanTitle(title)
    if (!d && !String(spec || "").trim()) {
      var quick = T.splitQuick(name, t)
      if (quick) { d = quick; name = T.cleanTitle(quick.title) }
    }
    if (!d) return 0
    return root.startMs(d.ms, T.capitalize(name), d.at || 0)
  }

  function startMs(ms, title, at) {
    var t = Date.now()
    var id = root.add({
      kind: "timer", title: T.cleanTitle(title), duration: Math.round(ms),
      end: t + Math.round(ms), left: 0, state: "running", endedAt: 0, at: at || 0
    })
    if (!at) root.remember(title, ms)
    root.playSound("start")
    return id
  }

  function startStopwatch(title) {
    var id = root.add({
      kind: "stopwatch", title: T.capitalize(T.cleanTitle(title)),
      startedAt: Date.now(), elapsed: 0, running: true, laps: []
    })
    root.playSound("start")
    return id
  }

  function remember(title, ms) {
    var t = T.cleanTitle(title)
    var list = root.recent.filter(function(r) { return !(r.title === t && r.duration === ms) })
    list.unshift({ title: t, duration: ms })
    root.recent = list.slice(0, T.MAX_RECENT)
  }

  function forgetRecent() {
    root.recent = []
    root.save()
  }

  function pause(id) {
    return root.update(id, function(x) {
      var t = Date.now()
      if (x.kind === "timer" && x.state === "running") {
        x.left = Math.max(0, x.end - t)
        x.state = "paused"
        x.at = 0
      } else if (x.kind === "stopwatch" && x.running) {
        x.elapsed += t - x.startedAt
        x.startedAt = 0
        x.running = false
      }
    })
  }

  function resume(id) {
    return root.update(id, function(x) {
      var t = Date.now()
      if (x.kind === "timer" && x.state === "paused") {
        x.end = t + x.left
        x.left = 0
        x.state = "running"
      } else if (x.kind === "stopwatch" && !x.running) {
        x.startedAt = t
        x.running = true
      }
    })
  }

  function toggle(id) {
    var x = root.find(id)
    if (!x) return "missing"
    if (x.kind === "timer") {
      if (x.state === "ringing") return root.dismiss(id)
      if (x.state === "done") return root.restart(id)
      return x.state === "running" ? root.pause(id) : root.resume(id)
    }
    return x.running ? root.pause(id) : root.resume(id)
  }

  // Adds (or with a negative value removes) minutes from a running or paused
  // timer. Never takes it below five seconds.
  function extend(id, minutes) {
    var delta = Math.round(Number(minutes) || 0) * 60000
    if (!delta) return "ignored"
    return root.update(id, function(x) {
      if (x.kind !== "timer") return
      var t = Date.now()
      if (x.state === "running") {
        x.end = Math.max(t + 5000, x.end + delta)
        x.at = 0
      } else if (x.state === "paused") {
        x.left = Math.max(5000, x.left + delta)
      } else return
      x.duration = Math.max(1000, x.duration + delta)
    })
  }

  function restart(id) {
    return root.update(id, function(x) {
      var t = Date.now()
      if (x.kind === "timer") {
        if (x.at) {
          // An alarm restarts for the same time tomorrow.
          var d = new Date(x.endedAt || x.end)
          var next = T.parseClock(d.getHours() + ":" + T.pad(d.getMinutes()), t)
          x.end = next.at
          x.at = next.at
          x.duration = next.ms
        } else x.end = t + x.duration
        x.left = 0
        x.state = "running"
        x.endedAt = 0
      } else {
        x.elapsed = 0
        x.laps = []
        x.startedAt = x.running ? t : 0
      }
    })
  }

  function lap(id) {
    return root.update(id, function(x) {
      if (x.kind !== "stopwatch" || x.laps.length >= T.MAX_LAPS) return
      x.laps.push(root.total(x, Date.now()))
    })
  }

  // Stops a ringing timer (all of them when id is 0).
  function dismiss(id) {
    var any = false
    var list = root.copy(root.items)
    list.forEach(function(x) {
      if (x.kind === "timer" && x.state === "ringing" && (!id || x.id === id)) { x.state = "done"; any = true }
    })
    if (!any) return "ignored"
    root.items = list
    root.save()
    return "ok"
  }

  // Snoozes a ringing timer (all of them when id is 0) for `minutes`, or for
  // the snooze setting when that is 0.
  function snooze(id, minutes) {
    var ms = (Math.round(Number(minutes) || 0) || root.settings.snooze) * 60000
    var any = false
    var t = Date.now()
    var list = root.copy(root.items)
    list.forEach(function(x) {
      if (x.kind === "timer" && x.state === "ringing" && (!id || x.id === id)) {
        x.state = "running"
        x.end = t + ms
        x.endedAt = 0
        x.at = 0
        any = true
      }
    })
    if (!any) return "ignored"
    root.items = list
    root.save()
    return "ok"
  }

  function remove(id) {
    var list = root.items.filter(function(x) { return x.id !== id })
    if (list.length === root.items.length) return "missing"
    root.items = list
    root.save()
    return "ok"
  }

  function clearDone() {
    root.items = root.items.filter(function(x) { return !(x.kind === "timer" && x.state === "done") })
    root.save()
  }

  function clearAll() {
    root.items = []
    root.save()
  }

  function setSetting(key, value) {
    if (!(key in root.settings)) return
    var next = root.copy(root.settings)
    if (key === "sound") next[key] = String(value)
    else if (typeof next[key] === "boolean") next[key] = !!value
    else next[key] = T.clampSetting(key, value)
    root.settings = next
    root.save()
  }

  // ----------------------------------------------------------- read helpers

  function total(x, t) {
    return x.elapsed + (x.running ? (t || root.now) - x.startedAt : 0)
  }

  function remainingMs(x) {
    if (!x || x.kind !== "timer") return 0
    if (x.state === "running") return Math.max(0, x.end - root.now)
    if (x.state === "paused") return x.left
    return 0
  }

  function progress(x) {
    if (!x || x.kind !== "timer" || x.duration <= 0) return 0
    if (x.state === "ringing" || x.state === "done") return 1
    return Math.max(0, Math.min(1, 1 - root.remainingMs(x) / x.duration))
  }

  function status() {
    var t = Date.now()
    return JSON.stringify(root.items.map(function(x) {
      if (x.kind === "timer") return {
        id: x.id, kind: x.kind, title: T.defaultTitle(x), state: x.state,
        duration: Math.round(x.duration / 1000),
        remaining: Math.ceil(root.remainingMs(x) / 1000),
        ends: x.state === "running" ? T.timeOfDay(x.end, t) : ""
      }
      return {
        id: x.id, kind: x.kind, title: T.defaultTitle(x), running: x.running,
        elapsed: Math.floor(root.total(x, t) / 1000), laps: x.laps.length
      }
    }))
  }

  // Human-readable list for the command line.
  function listText() {
    if (root.items.length === 0) return "No timers"
    var t = Date.now()
    root.now = t
    return root.items.map(function(x) {
      var name = T.defaultTitle(x)
      if (x.kind === "stopwatch") return "#" + x.id + "  " + T.icons.stopwatch + "  " + name + "  " + T.stopwatchClock(root.total(x, t)) + (x.running ? "" : " (paused)")
      var state = x.state === "running" ? T.clock(root.remainingMs(x) / 1000) + " left, ends " + T.timeOfDay(x.end, t)
        : x.state === "paused" ? T.clock(x.left / 1000) + " left (paused)"
        : x.state === "ringing" ? "ringing" : "done"
      return "#" + x.id + "  " + T.icons.timer + "  " + name + "  " + state
    }).join("\n")
  }

  // ---------------------------------------------------------------- output

  function copy(value) { return JSON.parse(JSON.stringify(value)) }

  function notify(title, body, glyph, critical) {
    var args = [root.omarchyPath + "/bin/omarchy-notification-send", "--app-name", "Timers"]
    if (glyph) args.push("-g", glyph)
    if (critical) args.push("-u", "critical")
    args.push(title)
    if (body) args.push(body)
    Quickshell.execDetached(args)
  }

  function playSound(name) {
    if (name === "start" && !root.settings.startSound) return
    Quickshell.execDetached(["pw-play", "--volume=0.6", root.soundDir + name + ".wav"])
  }

  function preview(sound) {
    root.previewing = root.previewing === sound ? "" : sound
  }

  // ---------------------------------------------------------------- alarm

  // The alarm loop runs as one bash process so it can be stopped as a whole.
  // It starts quiet and steps up to full volume when "louder" is on, and
  // quits by itself if the shell goes away so a crash never leaves it ringing.
  readonly property string ringScript: '
    file=$1; v=$2; step=$3; parent=$PPID; p=
    trap \'[ -n "$p" ] && kill $p 2>/dev/null; exit 0\' TERM INT HUP
    while kill -0 "$parent" 2>/dev/null; do
      pw-play --volume="$v" "$file" & p=$!
      wait $p; p=
      v=$(awk -v v="$v" -v s="$step" \'BEGIN { v += s; if (v > 1) v = 1; print v }\')
      sleep 0.15
    done'

  readonly property string ringSound: previewing !== "" ? previewing : settings.sound
  readonly property bool shouldRing: loaded && (anyRinging || previewing !== "")

  Process {
    id: ringer
    running: root.shouldRing
    command: ["bash", "-c", root.ringScript, "bsadik-timers-ring",
      root.soundDir + root.ringSound + ".wav",
      root.previewing === "" && root.settings.louder ? "0.35" : "0.9",
      root.previewing === "" && root.settings.louder ? "0.13" : "0"]
  }

  // Restart the loop when the sound is switched mid-ring so it changes now.
  onRingSoundChanged: if (ringer.running) { ringer.running = false; ringer.running = Qt.binding(function() { return root.shouldRing }) }

  // A preview plays a couple of loops and stops.
  Timer {
    interval: 4500
    running: root.previewing !== ""
    onTriggered: root.previewing = ""
  }

  // ------------------------------------------------------------- plumbing

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
  }

  Timer {
    id: saveDebounce
    interval: 150
    onTriggered: stateFile.setText(JSON.stringify(root.snapshot(), null, 2) + "\n")
  }

  Timer {
    interval: root.fast ? 100 : 250
    repeat: true
    running: root.loaded && (root.runningTimers.length > 0 || root.fast || root.anyRinging)
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  IpcHandler {
    target: "bsadik.timers"

    // omarchy-shell bsadik.timers start 10m "Tea"
    function start(spec: string, title: string): string {
      var id = root.startTimer(spec, title)
      return id ? String(id) : "error: can't read duration '" + spec + "'"
    }
    function stopwatch(title: string): string { return String(root.startStopwatch(title)) }
    function stop(): string { return root.dismiss(0) }
    function snooze(): string { return root.snooze(0, 0) }
    function pause(id: int): string { return root.pause(id) }
    function resume(id: int): string { return root.resume(id) }
    function toggle(id: int): string { return root.toggle(id) }
    function extend(id: int, minutes: int): string { return root.extend(id, minutes) }
    function remove(id: int): string { return root.remove(id) }
    function clearDone(): void { root.clearDone() }
    function clear(): void { root.clearAll() }
    function list(): string { return root.listText() }
    function status(): string { return root.status() }
    function panel(): void { if (root.shell) root.shell.toggle("bsadik.timers", "") }
  }

  Variants {
    model: Quickshell.screens

    AlarmOverlay {
      required property var modelData
      screen: modelData
      service: root
    }
  }
}
