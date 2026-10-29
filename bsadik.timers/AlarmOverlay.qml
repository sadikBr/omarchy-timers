import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Timers.js" as T

// Full-screen alarm for one monitor, shown while a timer is ringing: a
// ringing bell with ripples, the timer's title, and big Snooze / Stop
// buttons, like a phone alarm. It takes keyboard focus so the alarm can be
// handled without the mouse.
//
//   Enter / Space / Esc   stop          S   snooze
PanelWindow {
  id: win

  required property var service

  readonly property bool shown: service && service.overlayVisible
  readonly property var alarm: service && service.ringing.length > 0 ? service.ringing[0] : null
  readonly property int others: service ? Math.max(0, service.ringing.length - 1) : 0
  readonly property string backgroundPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  // Keep showing the last alarm while the overlay fades out.
  property var lastAlarm: null
  onAlarmChanged: if (alarm) lastAlarm = alarm
  readonly property var shownAlarm: alarm || lastAlarm

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color muted: Util.alpha(foreground, 0.6)
  property string fontFamily: Style.font.family
  property string iconFamily: "JetBrainsMono Nerd Font"

  visible: shown || content.opacity > 0.01
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "bsadik-timers-alarm"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onShownChanged: if (shown) Qt.callLater(function() { keys.forceActiveFocus() })

  function stop() { if (win.alarm) win.service.dismiss(win.alarm.id) }
  function snooze() { if (win.alarm) win.service.snooze(win.alarm.id, 0) }

  Item {
    id: content
    anchors.fill: parent
    opacity: win.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.background
    }

    Image {
      id: wallpaper
      anchors.fill: parent
      source: win.visible ? Util.fileUrl(win.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
      visible: false
    }

    MultiEffect {
      anchors.fill: parent
      source: wallpaper
      visible: wallpaper.status === Image.Ready
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 1.0
      blurMax: 96
      blurMultiplier: 1.2
      saturation: -0.2
    }

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Commons.Color.background, 0.7)
    }

    // A slow accent glow that breathes behind everything while it rings.
    Rectangle {
      anchors.centerIn: parent
      width: Math.max(parent.width, parent.height) * 1.2
      height: width
      radius: width / 2
      color: Util.alpha(win.accent, 0.10)
      SequentialAnimation on opacity {
        running: win.shown
        loops: Animation.Infinite
        NumberAnimation { from: 0.25; to: 1; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.25; duration: 900; easing.type: Easing.InOutSine }
      }
    }

    // Swallow every pointer event so nothing reaches the windows below.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.AllButtons
      onClicked: keys.forceActiveFocus()
      onWheel: function(wheel) { wheel.accepted = true }
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        event.accepted = true
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
          win.stop()
        else if (event.key === Qt.Key_S || event.key === Qt.Key_Z)
          win.snooze()
      }
    }

    Column {
      id: column
      anchors.centerIn: parent
      spacing: Style.space(26)
      width: Math.min(parent.width - Style.space(64), Style.space(620))

      scale: win.shown ? 1 : 0.94
      Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }

      // Bell with ripples.
      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(200)
        height: width

        Repeater {
          model: 3

          Rectangle {
            id: ripple
            required property int index
            anchors.centerIn: parent
            width: parent.width * 0.42
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(2, Style.space(2))
            border.color: win.accent
            opacity: 0

            SequentialAnimation {
              running: win.shown
              loops: Animation.Infinite
              PauseAnimation { duration: ripple.index * 600 }
              ParallelAnimation {
                NumberAnimation { target: ripple; property: "scale"; from: 1; to: 2.4; duration: 1800; easing.type: Easing.OutCubic }
                NumberAnimation { target: ripple; property: "opacity"; from: 0.7; to: 0; duration: 1800; easing.type: Easing.OutCubic }
              }
              PauseAnimation { duration: (2 - ripple.index) * 600 }
            }
          }
        }

        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.46
          height: width
          radius: width / 2
          color: Util.alpha(win.accent, 0.18)
          border.width: Math.max(1, Style.space(2))
          border.color: Util.alpha(win.accent, 0.6)
        }

        Text {
          id: bell
          anchors.centerIn: parent
          text: T.icons.bellRing
          color: win.accent
          font.family: win.iconFamily
          font.pixelSize: Style.space(52)
          transformOrigin: Item.Top

          // Shake, rest, shake: the way a phone bell rings.
          SequentialAnimation on rotation {
            running: win.shown
            loops: Animation.Infinite
            NumberAnimation { to: 16; duration: 70 }
            NumberAnimation { to: -16; duration: 140 }
            NumberAnimation { to: 12; duration: 120 }
            NumberAnimation { to: -12; duration: 120 }
            NumberAnimation { to: 6; duration: 100 }
            NumberAnimation { to: 0; duration: 80 }
            PauseAnimation { duration: 700 }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: win.shownAlarm ? T.defaultTitle(win.shownAlarm) : ""
          color: win.foreground
          font.family: win.fontFamily
          font.pixelSize: Style.font.displayLarge + Style.space(14)
          font.bold: true
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: {
            var a = win.shownAlarm
            if (!a) return ""
            var head = a.at ? "Alarm for " + T.timeOfDay(a.endedAt || a.end, win.service.now)
              : "Time's up · " + T.duration(a.duration) + " timer"
            return head + " · " + T.ago(win.service.now - (a.endedAt || a.end))
          }
          color: win.muted
          font.family: win.fontFamily
          font.pixelSize: Style.font.title + Style.space(2)
          font.features: { "tnum": 1 }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: win.others > 0
          textFormat: Text.PlainText
          text: win.others === 1 ? "1 more timer is ringing" : win.others + " more timers are ringing"
          color: win.accent
          font.family: win.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(14)

        AlarmButton {
          icon: T.icons.snooze
          label: "Snooze " + (win.service ? win.service.settings.snooze : 5) + " min"
          hint: "S"
          foreground: win.foreground
          accent: win.accent
          fontFamily: win.fontFamily
          iconFamily: win.iconFamily
          onClicked: win.snooze()
        }

        AlarmButton {
          icon: T.icons.stop
          label: "Stop"
          hint: "Enter"
          primary: true
          foreground: win.foreground
          accent: win.accent
          fontFamily: win.fontFamily
          iconFamily: win.iconFamily
          onClicked: win.stop()
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: win.others > 0
        textFormat: Text.PlainText
        text: "Stop all"
        color: stopAll.containsMouse ? win.accent : Util.alpha(win.foreground, 0.5)
        font.family: win.fontFamily
        font.pixelSize: Style.font.body
        font.underline: stopAll.containsMouse

        MouseArea {
          id: stopAll
          anchors.fill: parent
          anchors.margins: -Style.space(6)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: win.service.dismiss(0)
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "Enter, Space or Esc to stop · S to snooze"
        color: Util.alpha(win.foreground, 0.4)
        font.family: win.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
