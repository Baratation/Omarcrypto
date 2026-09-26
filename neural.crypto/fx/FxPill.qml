import QtQuick
import qs.Commons

// Chrome for a bar pill, placed inside the widget's button (it sits behind the
// label with z: -1). Hover lights a soft tinted capsule and grows an underline
// from the center; `alert` adds a breathing halo in the alert color; bump()
// gives a click a small squash-and-release. The halo pulses on a Timer with
// rests in between (a looping animation would keep the bar redrawing).
Item {
  id: root

  property bool hovered: false
  property bool alert: false
  property color tint: Color.accent
  property color alertColor: Color.urgent
  property real inset: Style.space(3)
  // Optional pale wash that stays on even without hover, e.g. a heat level.
  property real restAlpha: 0

  readonly property Item host: parent

  anchors.fill: parent
  z: -1

  function bump() {
    if (host) bumpAnim.restart()
  }

  Rectangle {
    id: halo
    anchors.fill: capsule
    anchors.margins: -Style.space(1)
    radius: capsule.radius + Style.space(1)
    color: "transparent"
    border.width: 1.5
    border.color: root.alertColor
    opacity: 0
    visible: root.alert

    SequentialAnimation {
      id: haloPulse
      NumberAnimation { target: halo; property: "opacity"; to: 0.85; duration: 450; easing.type: Easing.OutQuad }
      NumberAnimation { target: halo; property: "opacity"; to: 0.3; duration: 750; easing.type: Easing.InOutSine }
    }
  }

  Timer {
    interval: 3500
    repeat: true
    triggeredOnStart: true
    running: root.alert
    onTriggered: haloPulse.restart()
  }

  Rectangle {
    id: capsule
    anchors.fill: parent
    anchors.topMargin: root.inset
    anchors.bottomMargin: root.inset
    radius: Math.min(height / 2, Math.max(4, Style.cornerRadius))
    color: root.alert
      ? Qt.rgba(root.alertColor.r, root.alertColor.g, root.alertColor.b, root.hovered ? 0.24 : 0.14)
      : Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.hovered ? 0.16 : root.restAlpha)

    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
  }

  Rectangle {
    id: underline
    anchors.horizontalCenter: capsule.horizontalCenter
    anchors.bottom: capsule.bottom
    height: 1.5
    radius: 1
    width: root.hovered ? capsule.width * 0.6 : 0
    color: root.alert ? root.alertColor : root.tint
    opacity: root.hovered ? 1 : 0

    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
    Behavior on opacity { NumberAnimation { duration: 200 } }
  }

  SequentialAnimation {
    id: bumpAnim
    NumberAnimation { target: root.host; property: "scale"; to: 0.9; duration: 70; easing.type: Easing.OutQuad }
    NumberAnimation { target: root.host; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
  }
}
