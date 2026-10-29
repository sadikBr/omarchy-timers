import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Timers.js" as T

// Bar entry for timers. A timer glyph when nothing runs; otherwise the time
// left on the timer that ends first (or a running stopwatch), with a "+N"
// when more are going. While an alarm rings, a shaking bell and its title.
//
//   left click    open the popup
//   right click   stop the alarm, or pause / resume what the bar shows
//   middle click  snooze the alarm
//   scroll        +/- 1 minute on the timer the bar shows
BarWidget {
  id: root
  moduleName: "bsadik.timers"

  // The service is created by the shell independently of the widget, and a
  // plugin reload recreates it, so keep looking it up until it is there.
  property var service: null
  property bool popupOpen: false

  readonly property bool ready: service !== null && service.loaded === true
  readonly property bool ringing: ready && service.anyRinging
  readonly property var alarm: ringing ? service.ringing[0] : null
  // What the bar shows: the soonest running timer, else a running stopwatch,
  // else a paused timer.
  readonly property var shownItem: {
    if (!ready) return null
    if (service.soonest) return service.soonest
    if (service.runningStopwatches.length > 0) return service.runningStopwatches[0]
    var paused = service.timers.filter(function(x) { return x.state === "paused" })
    return paused.length > 0 ? paused[0] : null
  }
  readonly property int extra: ready && shownItem ? Math.max(0, service.activeCount - 1) : 0
  readonly property bool paused: shownItem !== null && (shownItem.kind === "timer" ? shownItem.state === "paused" : !shownItem.running)
  readonly property bool lastMinute: shownItem !== null && shownItem.kind === "timer" && shownItem.state === "running"
    && service.remainingMs(shownItem) <= 60000

  readonly property color barColor: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property string iconFamily: "JetBrainsMono Nerd Font"

  readonly property string glyph: ringing ? T.icons.bellRing
    : !shownItem ? T.icons.alarm
    : shownItem.kind === "stopwatch" ? T.icons.stopwatch
    : paused ? T.icons.pause
    : shownItem.at ? T.icons.alarm
    : T.icons.timer

  readonly property string label: {
    if (ringing) return T.defaultTitle(alarm)
    if (!shownItem) return ""
    var text = shownItem.kind === "stopwatch"
      ? T.stopwatchClock(service.total(shownItem, service.now), false)
      : T.compact(service.remainingMs(shownItem) / 1000)
    return text
  }

  readonly property color glyphColor: ringing || lastMinute ? accent
    : paused ? Util.alpha(barColor, 0.5)
    : shownItem ? barColor
    : Util.alpha(barColor, 0.8)

  readonly property string tooltip: {
    if (!ready) return "Timers"
    if (ringing) return T.defaultTitle(alarm) + " is ringing\nRight-click: stop · Middle-click: snooze " + service.settings.snooze + " min"
    if (service.items.length === 0) return "Timers\nClick to start a timer or stopwatch"
    var lines = []
    service.items.forEach(function(x) {
      if (x.kind === "timer" && x.state === "done") return
      if (lines.length >= 6) return
      var name = T.defaultTitle(x)
      if (x.kind === "stopwatch") lines.push(T.icons.stopwatch + "  " + name + " · " + T.stopwatchClock(service.total(x, service.now), false) + (x.running ? "" : " (paused)"))
      else lines.push((x.at ? T.icons.alarm : T.icons.timer) + "  " + name + " · " + T.clock(service.remainingMs(x) / 1000)
        + (x.state === "paused" ? " (paused)" : " · " + T.timeOfDay(x.end, service.now)))
    })
    if (lines.length === 0) return "Timers\nClick to start a timer or stopwatch"
    return lines.join("\n")
  }

  // Shape contract for shell.summon/hide/toggle routing: the bar looks for
  // open/close/opened on the widget root and picks the copy on the focused
  // monitor (the center section also keeps a hidden placeholder copy).
  readonly property bool opened: popupOpen
  function close() { popupOpen = false }
  function open() { popupOpen = true }

  function findService() {
    if (!root.bar || !root.bar.shell) return
    var s = root.bar.shell.serviceFor(root.moduleName) || null
    if (s !== root.service) root.service = s
  }

  Timer {
    interval: root.service ? 2000 : 400
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.findService()
  }

  implicitWidth: vertical ? barSize : row.implicitWidth + Style.space(14)
  implicitHeight: vertical ? column.implicitHeight + Style.space(10) : barSize

  // Accent pill behind the widget while an alarm rings.
  Rectangle {
    anchors.fill: parent
    anchors.margins: Style.space(3)
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    color: Util.alpha(root.accent, 0.22)
    visible: root.ringing
    SequentialAnimation on opacity {
      running: root.ringing
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.35; duration: 600; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.35; to: 1; duration: 600; easing.type: Easing.InOutSine }
    }
  }

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(5)

    Text {
      id: glyphText
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      color: root.glyphColor
      font.family: root.iconFamily
      font.pixelSize: Style.font.body + 1
      transformOrigin: Item.Top
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }

      SequentialAnimation on rotation {
        running: root.ringing
        loops: Animation.Infinite
        NumberAnimation { to: 18; duration: 70 }
        NumberAnimation { to: -18; duration: 140 }
        NumberAnimation { to: 10; duration: 110 }
        NumberAnimation { to: 0; duration: 80 }
        PauseAnimation { duration: 600 }
      }
      onVisibleChanged: rotation = 0
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.label !== ""
      textFormat: Text.PlainText
      text: root.ringing ? T.defaultTitle(root.alarm).slice(0, 24) : root.label
      color: root.ringing ? root.accent : root.paused ? Util.alpha(root.barColor, 0.5) : root.barColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.ringing
      font.features: { "tnum": 1 }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.extra > 0 && !root.ringing
      textFormat: Text.PlainText
      text: "+" + root.extra
      color: Util.alpha(root.barColor, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Column {
    id: column
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Style.space(2)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.glyph
      color: root.glyphColor
      font.family: root.iconFamily
      font.pixelSize: Style.font.body + 1
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.label !== "" && !root.ringing
      textFormat: Text.PlainText
      text: root.label
      color: root.barColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Thin progress line along the bottom edge for the timer the bar shows.
  Rectangle {
    visible: !root.vertical && !root.ringing && root.shownItem !== null && root.shownItem.kind === "timer"
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.leftMargin: Style.space(5)
    anchors.bottomMargin: Style.space(2)
    height: Math.max(1, Style.space(2))
    radius: height / 2
    width: Math.max(0, (parent.width - Style.space(10)) * (root.ready && root.shownItem ? root.service.progress(root.shownItem) : 0))
    color: root.lastMinute ? root.accent : Util.alpha(root.barColor, root.paused ? 0.3 : 0.6)
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        if (!root.ready) return
        if (root.ringing) root.service.dismiss(root.alarm.id)
        else if (root.shownItem) root.service.toggle(root.shownItem.id)
        else root.popupOpen = true
      } else if (mouse.button === Qt.MiddleButton) {
        if (root.ringing) root.service.snooze(root.alarm.id, 0)
      } else root.popupOpen = !root.popupOpen
    }
    onWheel: function(wheel) {
      if (!root.ready || !root.shownItem || root.shownItem.kind !== "timer") return
      root.service.extend(root.shownItem.id, wheel.angleDelta.y > 0 ? 1 : -1)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // KeyboardPanel rather than PopupCard: the popup starts with typing, and an
  // xdg-popup only gets keys after the pointer has been inside it.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: panel.focusTarget
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(panel.implicitHeight, Style.space(720))

    TimersPanel {
      id: panel
      anchors.fill: parent
      service: root.service
      opened: root.popupOpen
      foreground: root.fg
      accent: root.accent
      fontFamily: root.fontFamily
      iconFamily: root.iconFamily
      onCloseRequested: root.close()
    }
  }
}
