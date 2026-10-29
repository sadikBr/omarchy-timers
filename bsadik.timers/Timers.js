.pragma library

// Pure helpers for the timers service and widget: defaults, duration parsing,
// state normalization, and formatting. No QML objects in here.
//
// An item is either a countdown timer or a stopwatch, and every time in it is
// an absolute wall-clock value in ms, so a shell restart, plugin reload or
// suspend picks up at the right moment.
//
//   timer      { id, kind: "timer", title, duration, end, left, state, endedAt }
//              state: running | paused | ringing | done
//              end is set while running, left (ms) while paused
//   stopwatch  { id, kind: "stopwatch", title, startedAt, elapsed, running, laps }
//              total = elapsed + (running ? now - startedAt : 0)

var icons = {
  timer: String.fromCodePoint(0xF051F),
  stopwatch: String.fromCodePoint(0xF13AB),
  alarm: String.fromCodePoint(0xF0020),
  bell: String.fromCodePoint(0xF009A),
  bellRing: String.fromCodePoint(0xF009E),
  snooze: String.fromCodePoint(0xF068E),
  play: String.fromCodePoint(0xF040A),
  pause: String.fromCodePoint(0xF03E4),
  stop: String.fromCodePoint(0xF04DB),
  restart: String.fromCodePoint(0xF0453),
  reset: String.fromCodePoint(0xF0450),
  flag: String.fromCodePoint(0xF023B),
  plus: String.fromCodePoint(0xF0415),
  minus: String.fromCodePoint(0xF0374),
  close: String.fromCodePoint(0xF0156),
  check: String.fromCodePoint(0xF012C),
  cog: String.fromCodePoint(0xF0493),
  volume: String.fromCodePoint(0xF057E),
  history: String.fromCodePoint(0xF02DA),
  broom: String.fromCodePoint(0xF00E2),
  clock: String.fromCodePoint(0xF0954)
}

var sounds = [
  { id: "marimba", label: "Marimba" },
  { id: "classic", label: "Classic" },
  { id: "chime", label: "Chime" }
]

var presets = [
  { label: "1m", ms: 60000 },
  { label: "3m", ms: 180000 },
  { label: "5m", ms: 300000 },
  { label: "10m", ms: 600000 },
  { label: "15m", ms: 900000 },
  { label: "25m", ms: 1500000 },
  { label: "30m", ms: 1800000 },
  { label: "1h", ms: 3600000 }
]

var limits = {
  snooze: [1, 30, 5],      // minutes
  ringFor: [1, 30, 5]      // minutes an alarm rings before it gives up
}

var MAX_MS = 100 * 3600000
var MAX_ITEMS = 50
var MAX_RECENT = 6
var MAX_LAPS = 99

function defaults() {
  return {
    settings: {
      sound: "marimba",
      fullscreen: true,
      louder: true,
      startSound: true,
      snooze: limits.snooze[2],
      ringFor: limits.ringFor[2]
    },
    items: [],
    recent: [],
    nextId: 1
  }
}

function clampInt(v, lo, hi, fallback) {
  var n = Math.round(Number(v))
  if (!isFinite(n)) return fallback
  return Math.max(lo, Math.min(hi, n))
}

function clampSetting(key, value) {
  var l = limits[key]
  return l ? clampInt(value, l[0], l[1], l[2]) : value
}

function soundLabel(id) {
  for (var i = 0; i < sounds.length; i++) if (sounds[i].id === id) return sounds[i].label
  return sounds[0].label
}

// ------------------------------------------------------------- parsing

// Turns what the user typed into a duration. Returns
//   { ms }            for a countdown ("10", "25m", "1h30", "90s", "4:30")
//   { ms, at }        for a clock time ("at 7:30", "@14:00", "7pm"): ms runs
//                     until the next time the clock shows that time
//   null              when it can't be read
// A bare number means minutes, like the stock reminder; "m:ss" and "h:mm:ss"
// read like a phone timer.
function parseDuration(input, nowMs) {
  var s = String(input || "").trim().toLowerCase()
  if (!s) return null

  var atMatch = s.match(/^(?:at\s+|@\s*)(.+)$/)
  if (atMatch) return parseClock(atMatch[1], nowMs)
  if (/^\d{1,2}(:\d{2})?\s*(am|pm)$/.test(s)) return parseClock(s, nowMs)

  s = s.replace(/^in\s+/, "").replace(/\s+/g, " ")

  var colon = s.match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?$/)
  if (colon) {
    var ms = colon[3] !== undefined
      ? (Number(colon[1]) * 3600 + Number(colon[2]) * 60 + Number(colon[3])) * 1000
      : (Number(colon[1]) * 60 + Number(colon[2])) * 1000
    return valid(ms)
  }

  if (/^\d+(\.\d+)?$/.test(s)) return valid(Number(s) * 60000)

  var units = { h: 3600000, m: 60000, s: 1000 }
  var re = /(\d+(?:\.\d+)?)\s*(hours?|hrs|hr|h|minutes?|mins|min|m|seconds?|secs|sec|s)?\s*/g
  var total = 0
  var consumed = 0
  var last = ""
  var match
  while ((match = re.exec(s)) !== null && match[0].length > 0) {
    if (match.index !== consumed) return null
    consumed += match[0].length
    var unit = match[2] ? match[2].charAt(0) : (last === "h" ? "m" : last === "m" ? "s" : "")
    if (!unit) return null
    total += Number(match[1]) * units[unit]
    last = unit
  }
  if (consumed !== s.length) return null
  return valid(total)
}

function valid(ms) {
  ms = Math.round(ms)
  return ms >= 1000 && ms <= MAX_MS ? { ms: ms } : null
}

function parseClock(text, nowMs) {
  var m = String(text).trim().match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/)
  if (!m) return null
  var h = Number(m[1])
  var min = m[2] !== undefined ? Number(m[2]) : 0
  if (m[3]) {
    if (h < 1 || h > 12) return null
    h = h % 12 + (m[3] === "pm" ? 12 : 0)
  }
  if (h > 23 || min > 59) return null
  var now = new Date(nowMs)
  var at = new Date(nowMs)
  at.setHours(h, min, 0, 0)
  if (at.getTime() <= now.getTime() + 1000) at.setDate(at.getDate() + 1)
  return { ms: at.getTime() - nowMs, at: at.getTime() }
}

// Pulls a leading duration off a title, so "10m tea" in the title field
// starts a 10 minute "Tea" timer. Returns { ms, at, title } or null.
function splitQuick(text, nowMs) {
  var words = String(text || "").trim().split(/\s+/)
  for (var k = Math.min(4, words.length - 1); k >= 1; k--) {
    var d = parseDuration(words.slice(0, k).join(" "), nowMs)
    if (d) {
      d.title = words.slice(k).join(" ")
      return d
    }
  }
  return null
}

// ------------------------------------------------------------ normalize

function cleanTitle(t) {
  return String(t === undefined || t === null ? "" : t).replace(/[\r\n\t]+/g, " ").trim().slice(0, 80)
}

function capitalize(t) {
  return t ? t.charAt(0).toUpperCase() + t.slice(1) : t
}

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : fallback
}

// Merge whatever was on disk over the defaults so a partial or older file
// never leaves a field undefined.
function normalize(raw) {
  var d = defaults()
  if (!raw || typeof raw !== "object") return d

  var s = raw.settings || {}
  if (typeof s.sound === "string" && sounds.some(function(x) { return x.id === s.sound })) d.settings.sound = s.sound
  for (var k in d.settings) if (typeof d.settings[k] === "boolean" && typeof s[k] === "boolean") d.settings[k] = s[k]
  for (var key in limits) if (s[key] !== undefined) d.settings[key] = clampSetting(key, s[key])

  var maxId = 0
  if (Array.isArray(raw.items)) {
    d.items = raw.items.map(normalizeItem).filter(function(x) { return x !== null }).slice(0, MAX_ITEMS)
    d.items.forEach(function(x) { maxId = Math.max(maxId, x.id) })
  }

  if (Array.isArray(raw.recent)) {
    d.recent = raw.recent.filter(function(r) {
      return r && isFinite(Number(r.duration)) && Number(r.duration) >= 1000
    }).map(function(r) {
      return { title: cleanTitle(r.title), duration: Math.min(MAX_MS, Math.round(Number(r.duration))) }
    }).slice(0, MAX_RECENT)
  }

  d.nextId = Math.max(clampInt(raw.nextId, 1, 1e9, 1), maxId + 1)
  return d
}

function normalizeItem(x) {
  if (!x || typeof x !== "object") return null
  var id = clampInt(x.id, 1, 1e9, 0)
  if (!id) return null
  var title = cleanTitle(x.title)

  if (x.kind === "timer") {
    var duration = clampInt(x.duration, 1000, MAX_MS, 0)
    if (!duration) return null
    var state = ["running", "paused", "ringing", "done"].indexOf(x.state) >= 0 ? x.state : "done"
    var t = {
      id: id, kind: "timer", title: title, duration: duration,
      end: num(x.end, 0), left: Math.max(0, num(x.left, 0)),
      state: state, endedAt: num(x.endedAt, 0), at: num(x.at, 0)
    }
    if (state === "running" && !t.end) t.state = "done"
    return t
  }

  if (x.kind === "stopwatch") {
    var laps = Array.isArray(x.laps) ? x.laps.map(function(l) { return Math.max(0, num(l, 0)) }).slice(-MAX_LAPS) : []
    var running = x.running === true && num(x.startedAt, 0) > 0
    return {
      id: id, kind: "stopwatch", title: title,
      startedAt: running ? num(x.startedAt, 0) : 0,
      elapsed: Math.max(0, num(x.elapsed, 0)),
      running: running, laps: laps
    }
  }
  return null
}

// ----------------------------------------------------------- formatting

function pad(n) { return n < 10 ? "0" + n : String(n) }

// 754 -> "12:34", 3725 -> "1:02:05". Rounds up, so a timer never shows 0:00
// while it still has time left.
function clock(seconds) {
  var s = Math.max(0, Math.ceil(seconds - 0.001))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : pad(m) + ":" + pad(sec)
}

// Stopwatch reading: "04:12.3", "1:04:12.3". Rounds down, like a real one.
function stopwatchClock(ms, tenths) {
  var t = Math.max(0, Math.floor(ms / 100))
  var s = Math.floor(t / 10)
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var base = (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(s % 60)
  return tenths === false ? base : base + "." + (t % 10)
}

// Compact bar label: "14m" while more than ten minutes remain, "9:42" after.
function compact(seconds) {
  var s = Math.max(0, Math.ceil(seconds - 0.001))
  if (s >= 3600) {
    var m = Math.floor((s % 3600) / 60)
    return Math.floor(s / 3600) + "h" + (m > 0 ? pad(m) + "m" : "")
  }
  if (s > 600) return Math.ceil(s / 60) + "m"
  return Math.floor(s / 60) + ":" + pad(s % 60)
}

// 5400000 -> "1h 30m", 90000 -> "1m 30s", 45000 -> "45s"
function duration(ms) {
  var s = Math.max(0, Math.round(ms / 1000))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  var parts = []
  if (h) parts.push(h + "h")
  if (m) parts.push(m + "m")
  if (sec && h === 0) parts.push(sec + "s")
  return parts.length ? parts.join(" ") : "0s"
}

// "14:32" for a wall-clock time today, "Tue 14:32" otherwise.
function timeOfDay(ms, nowMs) {
  var d = new Date(ms)
  var hm = pad(d.getHours()) + ":" + pad(d.getMinutes())
  var now = new Date(nowMs || Date.now())
  if (d.toDateString() === now.toDateString()) return hm
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()] + " " + hm
}

function defaultTitle(item) {
  if (!item) return ""
  if (item.title) return item.title
  if (item.kind === "stopwatch") return "Stopwatch"
  if (item.at) return "Alarm"
  return duration(item.duration) + " timer"
}

// "ago" text for an alarm that has been ringing a while.
function ago(ms) {
  var s = Math.max(0, Math.floor(ms / 1000))
  if (s < 60) return s + "s ago"
  return Math.floor(s / 60) + "m " + pad(s % 60) + "s ago"
}
