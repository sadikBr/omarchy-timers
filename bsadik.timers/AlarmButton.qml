import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Large rounded button for the alarm overlay: icon over label, with the key
// that triggers it underneath. `primary` fills it with the accent colour.
BorderSurface {
  id: root

  property string icon: ""
  property string label: ""
  property string hint: ""
  property bool primary: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property string iconFamily: "JetBrainsMono Nerd Font"

  signal clicked()

  readonly property bool hot: mouse.containsMouse

  width: Style.space(200)
  height: Style.space(112)
  radius: Style.cornerRadius > 0 ? Style.space(18) : 0
  color: primary
    ? Util.alpha(accent, hot ? 0.42 : 0.28)
    : (hot ? Style.hoverFillFor(foreground, accent) : Util.alpha(foreground, 0.07))
  borderSpec: Border.controlSpec(primary ? "selected" : (hot ? "hover-cursor" : "normal"), foreground, accent)
  scale: mouse.pressed ? 0.97 : 1

  Behavior on scale { NumberAnimation { duration: 90 } }
  Behavior on color { ColorAnimation { duration: 120 } }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.icon
      color: root.primary ? root.accent : root.foreground
      font.family: root.iconFamily
      font.pixelSize: Style.space(30)
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.hint !== ""
      textFormat: Text.PlainText
      text: root.hint
      color: Util.alpha(root.foreground, 0.45)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
