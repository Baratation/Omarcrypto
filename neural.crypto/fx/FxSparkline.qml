import QtQuick
import qs.Commons

// Small live line chart: glowing stroke, gradient fill, and a pulsing dot on
// the newest sample. When a sample arrives the whole line glides one step to
// the left instead of snapping, so a 1 Hz feed reads as continuous motion.
// The glide moves the already-painted canvas on the scene graph; the canvas
// itself repaints once per sample, never per frame.
Item {
  id: root

  property var values: []
  property color color: Color.accent
  property real minValue: NaN     // NaN = auto from the data
  property real maxValue: NaN
  property real lineWidth: 1.4
  property real fillAlpha: 0.30
  property real glow: 5
  property bool showHead: true
  property bool glide: true
  property int glideDuration: 850
  // Draw-in: 0 hides everything, 1 shows the full line; animate it to reveal
  // the chart left-to-right.
  property real reveal: 1

  property real slide: 0

  readonly property int count: values ? values.length : 0
  readonly property real dx: count > 1 ? width / (count - 1) : width
  readonly property var head: headPoint()

  clip: true

  function css(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
      + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a) + ")"
  }

  function domain() {
    var lo = minValue, hi = maxValue
    if (!isFinite(lo) || !isFinite(hi)) {
      var dlo = Infinity, dhi = -Infinity
      for (var i = 0; i < count; i++) {
        var v = Number(values[i])
        if (!isFinite(v)) continue
        if (v < dlo) dlo = v
        if (v > dhi) dhi = v
      }
      if (!isFinite(dlo)) { dlo = 0; dhi = 1 }
      var pad = (dhi - dlo) * 0.12 || Math.max(Math.abs(dhi) * 0.02, 1)
      if (!isFinite(lo)) lo = dlo - pad
      if (!isFinite(hi)) hi = dhi + pad
    }
    return { lo: lo, hi: Math.max(hi, lo + 1e-9) }
  }

  function yFor(v, d, inset) {
    var h = height - inset * 2
    var t = (Number(v) - d.lo) / (d.hi - d.lo)
    return inset + (1 - Math.max(0, Math.min(1, t))) * h
  }

  function points() {
    var d = domain()
    var inset = Math.max(root.lineWidth, 1.5)
    var pts = []
    for (var i = 0; i < count; i++) {
      var v = Number(values[i])
      if (!isFinite(v)) continue
      pts.push({ x: i * root.dx, y: yFor(v, d, inset) })
    }
    return pts
  }

  function headPoint() {
    var pts = points()
    return pts.length > 0 ? pts[pts.length - 1] : null
  }

  onValuesChanged: {
    if (glide && count > 1) {
      glideAnim.stop()
      slide = 1
      glideAnim.start()
    }
    canvas.requestPaint()
  }
  onRevealChanged: canvas.requestPaint()
  onColorChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()

  NumberAnimation {
    id: glideAnim
    target: root
    property: "slide"
    to: 0
    duration: root.glideDuration
    easing.type: Easing.OutCubic
  }

  Canvas {
    id: canvas
    width: parent.width
    height: parent.height
    transform: Translate { x: root.slide * root.dx }
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var pts = root.points()
      if (pts.length < 2 || root.reveal <= 0) return

      ctx.save()
      ctx.beginPath()
      ctx.rect(0, 0, width * root.reveal, height)
      ctx.clip()

      function trace() {
        ctx.moveTo(pts[0].x, pts[0].y)
        for (var i = 1; i < pts.length - 1; i++) {
          var mx = (pts[i].x + pts[i + 1].x) / 2
          var my = (pts[i].y + pts[i + 1].y) / 2
          ctx.quadraticCurveTo(pts[i].x, pts[i].y, mx, my)
        }
        ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y)
      }

      if (root.fillAlpha > 0) {
        var g = ctx.createLinearGradient(0, 0, 0, height)
        g.addColorStop(0, root.css(root.color, root.fillAlpha))
        g.addColorStop(1, root.css(root.color, 0))
        ctx.beginPath()
        trace()
        ctx.lineTo(pts[pts.length - 1].x, height)
        ctx.lineTo(pts[0].x, height)
        ctx.closePath()
        ctx.fillStyle = g
        ctx.fill()
      }

      // Fade the tail so old samples recede and the eye lands on "now".
      var stroke = ctx.createLinearGradient(0, 0, width, 0)
      stroke.addColorStop(0, root.css(root.color, 0.15))
      stroke.addColorStop(0.55, root.css(root.color, 0.75))
      stroke.addColorStop(1, root.css(root.color, 1))
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      // Glow as a wide translucent under-stroke: Canvas shadowBlur is a
      // software blur and costs far more than a second stroke.
      if (root.glow > 0) {
        ctx.beginPath()
        trace()
        ctx.lineWidth = root.lineWidth + root.glow
        ctx.strokeStyle = root.css(root.color, 0.16)
        ctx.stroke()
      }

      ctx.beginPath()
      trace()
      ctx.lineWidth = root.lineWidth
      ctx.strokeStyle = stroke
      ctx.stroke()
      ctx.restore()
    }
  }

  // Newest sample: solid core plus an expanding ring, drawn as items so the
  // pulse runs on the scene graph instead of repainting the canvas.
  Item {
    id: headDot
    visible: root.showHead && !!root.head && root.reveal >= 1
    x: root.head ? root.head.x + root.slide * root.dx - width / 2 : 0
    y: root.head ? root.head.y - height / 2 : 0
    width: Math.max(3, root.lineWidth * 2.4)
    height: width

    Rectangle {
      id: ring
      anchors.centerIn: parent
      width: parent.width
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: root.color
      opacity: 0

      SequentialAnimation on scale {
        running: headDot.visible && root.visible
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 3.2; duration: 1400; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 400 }
      }
      SequentialAnimation on opacity {
        running: headDot.visible && root.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0.9; to: 0; duration: 1400; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 400 }
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: root.color
    }
  }
}
