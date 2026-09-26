import QtQuick
import "Model.js" as Model
import "I18n.js" as I18n
import "Cache.js" as Cache

// One cached 24h series per visible row; shared HTTP limits concurrency.
Canvas {
  id: root
  property var cacheEntry: null
  signal cached(string key, var entry)
  function restoreCache() {
    var saved = cacheEntry || Cache.get("sparks", key)
    if (saved && saved.at > fetchedAt) {
      values = saved.values; fetchedAt = saved.at
    }
  }
  onCacheEntryChanged: restoreCache()
  property string coinId: ""
  property string vs: "brl"
  // `active` polls every 5 min while the row is on screen; `prefetch` only
  // fills the row once in the background, so the first open is not empty.
  // They are separate because a binding on `fetchedAt` looped: restoring the
  // cache sets it from inside the change handler of the same binding.
  property bool active: false
  property bool prefetch: false
  property color lineColor: "#8ec07c"
  property var values: []
  property double fetchedAt: 0
  property double retryAt: 0
  property string requestKey: ""
  property string error: ""
  readonly property var pair: Model.chartPair(coinId, vs)
  readonly property string key: pair ? pair.pair : ""
  readonly property string sourceLabel: "24h · Binance · " + (pair ? pair.pair : I18n.tr("indisponível")) + (fetchedAt > 0 ? I18n.tr(" · dados de ") + new Date(fetchedAt).toLocaleTimeString(Qt.locale(), "HH:mm") : "")
  function refresh() {
    restoreCache()
    if ((!active && !prefetch) || !key || proc.running || Date.now() < retryAt || Date.now() - fetchedAt < 300000) return
    requestKey = key
    proc.get(Model.klinesUrl(key, "15m", 97), 300000, 0)
  }
  onKeyChanged: { proc.cancel(); values = []; fetchedAt = 0; retryAt = 0; requestPaint(); delay.restart() }
  onActiveChanged: { if (active) { restoreCache(); delay.restart() } else if (!prefetch) { delay.stop(); proc.cancel() } }
  onPrefetchChanged: if (prefetch) delay.restart()
  onValuesChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  Timer { id: delay; interval: 1; onTriggered: root.refresh() }
  Timer { interval: 300000; repeat: true; running: root.active; onTriggered: root.refresh() }
  Request {
    id: proc
    onCompleted: function(status, body, at) {
      if (root.requestKey !== root.key) return
      if (status !== 200) {
        root.error = I18n.tr("histórico indisponível"); root.retryAt = Date.now() + 120000
        return
      }
      try {
        root.values = Model.parseKlines(body).map(function(c) { return c.c })
        root.fetchedAt = at
        root.cached(root.key, { values: root.values, at: root.fetchedAt })
        root.error = ""
      } catch(e) { root.error = I18n.tr("histórico indisponível"); root.retryAt = Date.now() + 120000 }
    }
  }
  onPaint: {
    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
    if (values.length < 2) return
    var lo = Math.min.apply(null, values), hi = Math.max.apply(null, values)
    var range = hi - lo || Math.max(hi * 0.001, 1e-9)
    var pts = []
    for (var i = 0; i < values.length; i++)
      pts.push({ x: 2 + i / (values.length - 1) * (width - 4), y: 3 + (hi - values[i]) / range * (height - 6) })
    var rgba = function(a) {
      return "rgba(" + Math.round(lineColor.r * 255) + "," + Math.round(lineColor.g * 255) + "," + Math.round(lineColor.b * 255) + "," + a + ")"
    }
    var fill = ctx.createLinearGradient(0, 0, 0, height)
    fill.addColorStop(0, rgba(0.28)); fill.addColorStop(1, rgba(0))
    ctx.beginPath()
    for (var j = 0; j < pts.length; j++) { if (j === 0) ctx.moveTo(pts[j].x, pts[j].y); else ctx.lineTo(pts[j].x, pts[j].y) }
    ctx.lineTo(pts[pts.length - 1].x, height); ctx.lineTo(pts[0].x, height); ctx.closePath()
    ctx.fillStyle = fill; ctx.fill()
    // Glow as a wide translucent under-stroke (shadowBlur is a costly
    // software blur), then the line itself.
    ctx.lineJoin = "round"; ctx.lineCap = "round"
    ctx.beginPath()
    for (var g = 0; g < pts.length; g++) { if (g === 0) ctx.moveTo(pts[g].x, pts[g].y); else ctx.lineTo(pts[g].x, pts[g].y) }
    ctx.strokeStyle = rgba(0.18); ctx.lineWidth = 5; ctx.stroke()
    ctx.beginPath()
    for (var k = 0; k < pts.length; k++) { if (k === 0) ctx.moveTo(pts[k].x, pts[k].y); else ctx.lineTo(pts[k].x, pts[k].y) }
    ctx.strokeStyle = lineColor; ctx.lineWidth = 1.6; ctx.stroke()
  }
}
