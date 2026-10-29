import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Timers.js" as T

// Popup body: a Timer / Stopwatch switch, a title field, the duration field
// with quick presets and recent timers, the list of everything running, and
// the alarm settings. The title field has focus when the popup opens, so
// SUPER+CTRL+R, "10m tea", Enter starts a timer without touching the mouse.
//
//   Enter      start (from the title field: jump to duration if it's empty)
//   Tab        next field            Ctrl+Tab   switch Timer / Stopwatch
//   Esc        close the popup
Item {
  id: root

  property var service: null
  property bool opened: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property string iconFamily: "JetBrainsMono Nerd Font"

  property string mode: "timer"
  property bool showSettings: false
  readonly property Item focusTarget: titleField

  readonly property bool ready: service !== null && service.loaded === true
  readonly property var items: ready ? service.items : []
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color urgent: Commons.Color.urgent
  readonly property real now: ready ? service.now : Date.now()

  // What would start if Enter were pressed now.
  readonly property var parsed: {
    var t = Date.now() + 0 * root.now
    var d = T.parseDuration(durationField.text, t)
    if (d) return { ms: d.ms, at: d.at || 0, title: titleField.text }
    if (durationField.text.trim() === "") {
      var q = T.splitQuick(titleField.text, t)
      if (q) return { ms: q.ms, at: q.at || 0, title: q.title }
    }
    return null
  }
  readonly property bool durationInvalid: durationField.text.trim() !== "" && T.parseDuration(durationField.text, Date.now()) === null
  readonly property bool hasDone: items.some(function(x) { return x.kind === "timer" && x.state === "done" })

  signal closeRequested()

  implicitHeight: content.implicitHeight

  function setMode(m) {
    root.mode = m
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }

  function reset() {
    titleField.text = ""
    durationField.text = ""
  }

  function start() {
    if (!root.ready) return
    if (root.mode === "stopwatch") {
      root.service.startStopwatch(titleField.text)
      root.reset()
      return
    }
    var p = root.parsed
    if (!p) {
      durationField.forceActiveFocus()
      return
    }
    root.service.startMs(p.ms, T.capitalize(T.cleanTitle(p.title)), p.at)
    root.reset()
    titleField.forceActiveFocus()
  }

  function startPreset(ms) {
    if (!root.ready) return
    root.service.startMs(ms, T.capitalize(T.cleanTitle(titleField.text)), 0)
    root.reset()
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.closeRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
      root.setMode(root.mode === "timer" ? "stopwatch" : "timer")
      event.accepted = true
    }
  }

  onOpenedChanged: if (opened) { root.reset(); root.showSettings = false }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(10)

    // ------------------------------------------------------- header

    Item {
      width: parent.width
      height: Math.max(modeRow.height, settingsButton.height)

      Row {
        id: modeRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Button {
          iconText: T.icons.timer
          text: "Timer"
          bordered: true
          selected: root.mode === "timer"
          foreground: root.foreground
          accent: root.accent
          onClicked: root.setMode("timer")
        }

        Button {
          iconText: T.icons.stopwatch
          text: "Stopwatch"
          bordered: true
          selected: root.mode === "stopwatch"
          foreground: root.foreground
          accent: root.accent
          onClicked: root.setMode("stopwatch")
        }
      }

      PanelActionButton {
        id: settingsButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: T.icons.cog
        tooltipText: root.showSettings ? "Hide alarm settings" : "Alarm settings"
        fontFamily: root.iconFamily
        foreground: root.showSettings ? root.accent : root.foreground
        onClicked: root.showSettings = !root.showSettings
      }
    }

    // ------------------------------------------------------- new item

    TextField {
      id: titleField
      width: parent.width
      placeholderText: root.mode === "timer" ? "What's it for? (or type “10m tea”)" : "What are you timing?"
      foreground: root.foreground
      accent: root.accent
      font.family: root.fontFamily
      KeyNavigation.tab: root.mode === "timer" ? durationField : titleField
      Keys.onPressed: function(event) { root.handleKey(event) }
      onAccepted: {
        if (root.mode === "timer" && !root.parsed) durationField.forceActiveFocus()
        else root.start()
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.mode === "timer"

      TextField {
        id: durationField
        width: parent.width
        placeholderText: "How long? 10m · 1h30 · 4:30 · 90s · at 7:30"
        foreground: root.durationInvalid ? root.urgent : root.foreground
        accent: root.accent
        font.family: root.fontFamily
        KeyNavigation.tab: titleField
        Keys.onPressed: function(event) { root.handleKey(event) }
        onAccepted: root.start()
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: root.durationInvalid ? "Can't read that. Try 10, 25m, 1h30, 4:30 or at 7:30"
          : root.parsed ? (root.parsed.at ? "Rings at " + T.timeOfDay(root.parsed.at, root.now) + " · in " + T.duration(root.parsed.ms)
                                          : T.duration(root.parsed.ms) + " · rings at " + T.timeOfDay(Date.now() + 0 * root.now + root.parsed.ms, root.now))
            + (root.parsed.title ? " · “" + T.capitalize(T.cleanTitle(root.parsed.title)) + "”" : "")
          : "A plain number means minutes"
        color: root.durationInvalid ? root.urgent : root.parsed ? root.accent : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Quick presets: one click starts a timer with the title typed so far.
    Flow {
      width: parent.width
      spacing: Style.space(5)
      visible: root.mode === "timer"

      Repeater {
        model: T.presets

        Button {
          required property var modelData
          text: modelData.label
          tooltipText: "Start a " + T.duration(modelData.ms) + " timer now"
          bordered: true
          horizontalPadding: Style.space(9)
          verticalPadding: Style.space(4)
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          accent: root.accent
          onClicked: root.startPreset(modelData.ms)
        }
      }
    }

    Button {
      width: parent.width
      iconText: root.mode === "timer" ? T.icons.play : T.icons.stopwatch
      text: root.mode === "stopwatch" ? "Start stopwatch"
        : root.parsed ? (root.parsed.at ? "Set alarm for " + T.timeOfDay(root.parsed.at, root.now) : "Start " + T.duration(root.parsed.ms) + " timer")
        : "Start timer"
      bordered: true
      selected: root.mode === "stopwatch" || root.parsed !== null
      enabled: root.ready && (root.mode === "stopwatch" || root.parsed !== null)
      opacity: enabled ? 1 : 0.45
      foreground: root.foreground
      accent: root.accent
      onClicked: root.start()
    }

    // Recent timers, to run again with one click.
    Column {
      width: parent.width
      spacing: Style.space(5)
      visible: root.mode === "timer" && root.ready && root.service.recent.length > 0

      Item {
        width: parent.width
        height: recentLabel.implicitHeight

        Text {
          id: recentLabel
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: T.icons.history + "  Recent"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: "Forget"
          color: forgetMouse.containsMouse ? root.urgent : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            id: forgetMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.service.forgetRecent()
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(5)

        Repeater {
          model: root.ready ? root.service.recent : []

          Button {
            required property var modelData
            text: (modelData.title ? modelData.title + " · " : "") + T.duration(modelData.duration)
            tooltipText: "Start again"
            bordered: true
            horizontalPadding: Style.space(9)
            verticalPadding: Style.space(4)
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            accent: root.accent
            onClicked: root.service.startMs(modelData.duration, modelData.title, 0)
          }
        }
      }
    }

    // ----------------------------------------------------------- list

    PanelSeparator {
      width: parent.width
      foreground: root.foreground
      visible: root.items.length > 0
    }

    Flickable {
      id: listScroll
      width: parent.width
      height: Math.min(listColumn.implicitHeight, Style.space(340))
      contentWidth: width
      contentHeight: listColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      visible: root.items.length > 0

      Column {
        id: listColumn
        width: listScroll.width
        spacing: Style.space(6)

        Repeater {
          model: root.items

          ItemRow {
            required property var modelData
            item: modelData
            service: root.service
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            iconFamily: root.iconFamily
          }
        }
      }
    }

    Item {
      width: parent.width
      height: Math.max(countText.implicitHeight, clearButton.height)
      visible: root.items.length > 0

      Text {
        id: countText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: {
          if (!root.ready) return ""
          var n = root.service.activeCount
          return n === 0 ? "Nothing running" : n === 1 ? "1 running" : n + " running"
        }
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        id: clearButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasDone
        iconText: T.icons.broom
        text: "Clear finished"
        bordered: true
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        accent: root.accent
        onClicked: root.service.clearDone()
      }
    }

    // ------------------------------------------------------- settings

    PanelSeparator {
      width: parent.width
      foreground: root.foreground
      visible: root.showSettings
    }

    Column {
      width: parent.width
      spacing: Style.space(10)
      visible: root.showSettings && root.ready

      PanelSectionHeader {
        text: "Alarm"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      SettingRow {
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        iconFamily: root.iconFamily
        icon: T.icons.volume
        label: "Sound"
        hint: root.ready && root.service.previewing !== "" ? "Playing " + T.soundLabel(root.service.previewing) + "…" : "Click to hear it"

        Row {
          spacing: Style.space(4)

          Repeater {
            model: T.sounds

            Button {
              required property var modelData
              text: modelData.label
              bordered: true
              selected: root.ready && root.service.settings.sound === modelData.id
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              fontSize: Style.font.bodySmall
              iconText: root.ready && root.service.previewing === modelData.id ? T.icons.stop : ""
              foreground: root.foreground
              accent: root.accent
              onClicked: {
                root.service.setSetting("sound", modelData.id)
                root.service.preview(modelData.id)
              }
            }
          }
        }
      }

      SettingRow {
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        iconFamily: root.iconFamily
        icon: T.icons.bellRing
        label: "Full-screen alarm"
        hint: "Off: just the sound, a notification and the bar"
        ToggleSwitch {
          checked: root.ready && root.service.settings.fullscreen
          foreground: root.foreground
          accent: root.accent
          interactive: root.ready
          onToggled: root.service.setSetting("fullscreen", !root.service.settings.fullscreen)
        }
      }

      SettingRow {
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        iconFamily: root.iconFamily
        icon: T.icons.volume
        label: "Get louder"
        hint: "Start soft and rise to full volume"
        ToggleSwitch {
          checked: root.ready && root.service.settings.louder
          foreground: root.foreground
          accent: root.accent
          interactive: root.ready
          onToggled: root.service.setSetting("louder", !root.service.settings.louder)
        }
      }

      SettingRow {
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        iconFamily: root.iconFamily
        icon: T.icons.play
        label: "Start sound"
        hint: "A short tick when a timer starts"
        ToggleSwitch {
          checked: root.ready && root.service.settings.startSound
          foreground: root.foreground
          accent: root.accent
          interactive: root.ready
          onToggled: root.service.setSetting("startSound", !root.service.settings.startSound)
        }
      }

      SettingRow {
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        iconFamily: root.iconFamily
        icon: T.icons.snooze
        label: "Snooze"
        Stepper {
          value: root.ready ? root.service.settings.snooze : T.limits.snooze[2]
          from: T.limits.snooze[0]
          to: T.limits.snooze[1]
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onModified: function(v) { root.service.setSetting("snooze", v) }
        }
      }

      SettingRow {
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        iconFamily: root.iconFamily
        icon: T.icons.alarm
        label: "Ring for"
        hint: "Then it stops and counts as missed"
        Stepper {
          value: root.ready ? root.service.settings.ringFor : T.limits.ringFor[2]
          from: T.limits.ringFor[0]
          to: T.limits.ringFor[1]
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onModified: function(v) { root.service.setSetting("ringFor", v) }
        }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "Enter start · Tab next · Ctrl+Tab switch · Esc close"
      color: Util.alpha(root.foreground, 0.38)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
