import QtQuick
import qs.Commons

// A number that rolls to its new value instead of jumping, and can flash
// toward an up/down color for a moment when it moves. The first reading lands
// without animation so nothing counts up from zero at startup.
Text {
  id: root

  property real value: NaN
  property int decimals: 0
  property string prefix: ""
  property string suffix: ""
  property string placeholder: "--"
  // Custom formatter for the rolling value (e.g. compact prices); receives
  // the in-flight number and returns the text body between prefix/suffix.
  property var formatter: null

  property color baseColor: Color.foreground
  property color upColor: baseColor
  property color downColor: baseColor
  property bool flashOnChange: false
  // Moves smaller than this roll quietly; only real jumps flash.
  property real flashThreshold: 0
  // At most one flash per this many ms: a jittery feed should not keep the
  // bar lit (every animated frame redraws the whole bar).
  property int flashCooldown: 10000
  property double lastFlashAt: 0
  property int duration: 650
  // False lands every change instantly (e.g. while its panel is closed: any
  // running animation, even in a hidden window, makes the bar redraw).
  property bool animate: true
  // Jumps bigger than this fraction of the new value land instantly instead
  // of rolling (a price arriving from 0, a ticker switching coins).
  property real snapRatio: Infinity
  // Moves smaller than this land instantly too: a 1° wobble on a 1 Hz feed
  // is not worth a redraw of the whole bar for half a second.
  property real rollThreshold: 0

  property real shown: 0
  property real flash: 0
  property int direction: 0
  property bool primed: false

  readonly property bool valid: isFinite(value)

  function body(n) {
    if (formatter) return formatter(n)
    return Number(n).toFixed(decimals)
  }

  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                   a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }

  textFormat: Text.PlainText
  renderType: Text.NativeRendering
  text: valid ? prefix + body(shown) + suffix : placeholder
  color: flash > 0.001 ? mix(baseColor, direction > 0 ? upColor : downColor, flash) : baseColor

  onValueChanged: {
    // Not `valid`: that binding may still hold the previous value here.
    if (!isFinite(value)) return
    if (!primed) {
      shown = value
      primed = true
      return
    }
    var delta = value - shown
    direction = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
    if (!animate || Math.abs(delta) > Math.abs(value) * snapRatio || Math.abs(delta) < rollThreshold) {
      primed = false
      shown = value
      primed = true
      return
    }
    shown = value
    var now = Date.now()
    if (animate && flashOnChange && direction !== 0 && Math.abs(delta) >= flashThreshold
        && now - lastFlashAt >= flashCooldown) {
      lastFlashAt = now
      flashAnim.restart()
    }
  }

  Component.onCompleted: if (isFinite(value)) { shown = value; primed = true }

  Behavior on shown {
    enabled: root.primed
    NumberAnimation { duration: root.duration; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: flashAnim
    NumberAnimation { target: root; property: "flash"; to: 1; duration: 80; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 160 }
    NumberAnimation { target: root; property: "flash"; to: 0; duration: 480; easing.type: Easing.InOutSine }
  }
}
