import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.Commons

// Progress ring (or arc) with an eased value, a soft glow, and an optional
// needle. `value` is 0..1; values above 1 draw a full ring. The first reading
// sweeps in from zero, which doubles as the "the panel just opened" moment.
Item {
  id: root

  property real value: 0
  property color color: Color.accent
  property color trackColor: Qt.rgba(color.r, color.g, color.b, 0.18)
  property real thickness: Math.max(1.5, Math.min(width, height) * 0.13)
  property real startAngle: -90
  property real sweep: 360
  property bool needle: false
  // Extra degrees on the needle only, for idle wobble without moving the arc.
  property real needleOffset: 0
  property real glow: 0.6
  property int duration: 900
  property bool bounce: true
  // Changes smaller than this land instantly: a ring fed every second (time
  // used today) would otherwise be animating nearly all the time.
  property real snapBelow: 0.02

  property real shown: 0

  readonly property real radius: Math.min(width, height) / 2 - thickness / 2 - 0.5
  readonly property real ratio: Math.max(0, Math.min(1, shown))

  implicitWidth: 16
  implicitHeight: 16

  onValueChanged: {
    var next = Math.max(0, Number(value) || 0)
    if (Math.abs(next - shown) < snapBelow) {
      settle.enabled = false
      shown = next
      settle.enabled = true
    } else {
      shown = next
    }
  }
  Component.onCompleted: shown = Math.max(0, Number(value) || 0)

  Behavior on shown {
    id: settle
    NumberAnimation {
      duration: root.duration
      easing.type: root.bounce ? Easing.OutBack : Easing.OutCubic
      easing.overshoot: 1.2
    }
  }

  Shape {
    id: shape
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: root.glow > 0
    layer.samples: 4
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: root.color
      shadowBlur: root.glow
      shadowOpacity: 0.85
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
      blurMax: 12
    }

    ShapePath {
      strokeColor: root.trackColor
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.radius
        radiusY: root.radius
        startAngle: root.startAngle
        sweepAngle: root.sweep
      }
    }

    ShapePath {
      strokeColor: root.ratio > 0.002 ? root.color : "transparent"
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.radius
        radiusY: root.radius
        startAngle: root.startAngle
        sweepAngle: root.sweep * Math.max(0.002, root.ratio)
      }
    }
  }

  Rectangle {
    visible: root.needle
    width: Math.max(1, root.thickness * 0.6)
    height: root.radius * 0.8
    radius: width / 2
    color: root.color
    antialiasing: true
    x: root.width / 2 - width / 2
    y: root.height / 2 - height
    transformOrigin: Item.Bottom
    rotation: root.startAngle + 90 + root.sweep * root.ratio + root.needleOffset
  }
}
