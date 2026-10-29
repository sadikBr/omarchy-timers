import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Timers.js" as T

// One timer or stopwatch in the popup list: a progress ring with the kind's
// icon, the title and state, the time, and the actions that fit the state.
// A ringing timer gets Snooze / Stop; a stopwatch lists its latest laps.
BorderSurface {
  id: row

  required property var item
  property var service: null
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property string iconFamily: "JetBrainsMono Nerd Font"

  readonly property bool isTimer: item.kind === "timer"
  readonly property bool ringing: isTimer && item.state === "ringing"
  readonly property bool done: isTimer && item.state === "done"
  readonly property bool paused: isTimer ? item.state === "paused" : !item.running
  readonly property real now: service ? service.now : Date.now()
  readonly property real totalMs: isTimer ? 0 : service.total(item, now)
  readonly property real progress: isTimer ? service.progress(item) : 0
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color urgent: Commons.Color.urgent
  readonly property bool hot: hover.hovered

  readonly property string timeText: isTimer
    ? (done ? T.duration(item.duration) : ringing ? "00:00" : T.clock(service.remainingMs(item) / 1000))
    : T.stopwatchClock(totalMs)

  readonly property string subtitle: {
    if (!isTimer) {
      var n = item.laps.length
      if (n === 0) return item.running ? "Stopwatch · running" : (item.elapsed > 0 ? "Stopwatch · paused" : "Stopwatch")
      return "Stopwatch · " + n + (n === 1 ? " lap" : " laps") + (item.running ? "" : " · paused")
    }
    if (ringing) return "Ringing · " + T.ago(now - item.endedAt)
    if (done) return "Finished " + T.timeOfDay(item.endedAt || item.end, now)
    if (paused) return T.duration(item.duration) + " timer · paused"
    return (item.at ? "Alarm" : T.duration(item.duration) + " timer") + " · ends " + T.timeOfDay(item.end, now)
  }

  // Most recent laps first, each with its split from the lap before.
  readonly property var lapRows: {
    if (isTimer || item.laps.length === 0) return []
    var out = []
    for (var i = item.laps.length - 1; i >= 0 && out.length < 4; i--) {
      out.push({ n: i + 1, at: item.laps[i], split: item.laps[i] - (i > 0 ? item.laps[i - 1] : 0) })
    }
    return out
  }

  width: parent ? parent.width : 0
  height: body.implicitHeight + Style.space(16)
  radius: Style.cornerRadius
  color: ringing ? Util.alpha(accent, 0.16)
    : hot ? Util.alpha(foreground, 0.06)
    : Util.alpha(foreground, 0.03)
  borderSpec: Border.controlSpec(ringing ? "selected" : "normal", foreground, accent)
  opacity: done ? 0.7 : 1

  HoverHandler { id: hover }

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    spacing: Style.space(6)

    Item {
      width: parent.width
      height: Math.max(ring.height, textCol.implicitHeight)

      // Progress ring with the kind's icon in the middle. Drains as a timer
      // runs; a stopwatch sweeps once a minute.
      Canvas {
        id: ring
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        height: width
        property real value: row.isTimer ? 1 - row.progress : (row.totalMs % 60000) / 60000
        property color trackColor: Util.alpha(row.foreground, 0.12)
        property color fillColor: row.ringing ? row.accent : row.paused ? row.muted : row.accent
        onValueChanged: requestPaint()
        onFillColorChanged: requestPaint()
        onTrackColorChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var lw = Math.max(2, width * 0.09)
          var r = (Math.min(width, height) - lw) / 2
          ctx.lineWidth = lw
          ctx.lineCap = "round"
          ctx.strokeStyle = trackColor
          ctx.beginPath()
          ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
          ctx.stroke()
          if (value > 0.002) {
            ctx.strokeStyle = fillColor
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * value)
            ctx.stroke()
          }
        }

        Text {
          anchors.centerIn: parent
          text: row.ringing ? T.icons.bellRing
            : !row.isTimer ? T.icons.stopwatch
            : row.done ? T.icons.check
            : row.item.at ? T.icons.alarm : T.icons.timer
          color: row.ringing || (!row.paused && !row.done) ? row.accent : row.muted
          font.family: row.iconFamily
          font.pixelSize: Style.font.icon
        }
      }

      Column {
        id: textCol
        anchors.left: ring.right
        anchors.leftMargin: Style.space(10)
        anchors.right: timeLabel.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: T.defaultTitle(row.item)
          color: row.foreground
          font.family: row.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.subtitle
          color: row.ringing ? row.accent : row.muted
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: timeLabel
        anchors.right: actions.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.timeText
        color: row.ringing ? row.accent : row.paused || row.done ? row.muted : row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.heading + Style.space(2)
        font.bold: true
        font.features: { "tnum": 1 }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)
        visible: !row.ringing

        PanelActionButton {
          visible: !row.done
          iconText: row.paused ? T.icons.play : T.icons.pause
          tooltipText: row.paused ? "Resume" : "Pause"
          fontFamily: row.iconFamily
          foreground: row.foreground
          onClicked: row.service.toggle(row.item.id)
        }

        PanelActionButton {
          visible: row.isTimer && !row.done
          iconText: T.icons.plus
          tooltipText: "Add a minute (scroll on the bar icon for ±1)"
          fontFamily: row.iconFamily
          foreground: row.foreground
          onClicked: row.service.extend(row.item.id, 1)
        }

        PanelActionButton {
          visible: !row.isTimer && row.item.running
          iconText: T.icons.flag
          tooltipText: "Lap"
          fontFamily: row.iconFamily
          foreground: row.foreground
          onClicked: row.service.lap(row.item.id)
        }

        PanelActionButton {
          visible: row.done || (!row.isTimer && row.totalMs > 0)
          iconText: row.isTimer ? T.icons.restart : T.icons.reset
          tooltipText: row.isTimer ? (row.item.at ? "Same time tomorrow" : "Start again") : "Reset"
          fontFamily: row.iconFamily
          foreground: row.foreground
          onClicked: row.service.restart(row.item.id)
        }

        PanelActionButton {
          iconText: T.icons.close
          tooltipText: "Remove"
          fontFamily: row.iconFamily
          foreground: row.foreground
          hoverColor: row.urgent
          onClicked: row.service.remove(row.item.id)
        }
      }
    }

    // Snooze / Stop for a ringing timer.
    Row {
      visible: row.ringing
      width: parent.width
      spacing: Style.space(6)
      readonly property real cell: (width - spacing) / 2

      Button {
        width: parent.cell
        iconText: T.icons.snooze
        text: "Snooze " + (row.service ? row.service.settings.snooze : 5) + " min"
        bordered: true
        foreground: row.foreground
        accent: row.accent
        onClicked: row.service.snooze(row.item.id, 0)
      }

      Button {
        width: parent.cell
        iconText: T.icons.stop
        text: "Stop"
        bordered: true
        selected: true
        foreground: row.foreground
        accent: row.accent
        onClicked: row.service.dismiss(row.item.id)
      }
    }

    // Latest laps for a stopwatch.
    Column {
      visible: row.lapRows.length > 0
      width: parent.width
      leftPadding: ring.width + Style.space(10)
      spacing: Style.space(1)

      Repeater {
        model: row.lapRows

        Item {
          required property var modelData
          width: parent.width - parent.leftPadding
          height: lapText.implicitHeight

          Text {
            id: lapText
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: "Lap " + modelData.n
            color: row.muted
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            textFormat: Text.PlainText
            text: "+" + T.stopwatchClock(modelData.split) + "   " + T.stopwatchClock(modelData.at)
            color: row.muted
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
        }
      }
    }
  }
}
