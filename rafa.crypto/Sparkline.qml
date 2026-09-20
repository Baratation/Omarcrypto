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
  property bool active: false
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
    if (!active || !key || proc.running || Date.now() < retryAt || Date.now() - fetchedAt < 300000) return
    requestKey = key
    proc.get(Model.klinesUrl(key, "15m", 97), 300000, 0)
  }
  onKeyChanged: { proc.cancel(); values = []; fetchedAt = 0; retryAt = 0; requestPaint(); delay.restart() }
  onActiveChanged: { if (active) { restoreCache(); delay.restart() } else { delay.stop(); proc.cancel() } }
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
    ctx.beginPath()
    for (var i = 0; i < values.length; i++) {
      var x = 2 + i / (values.length - 1) * (width - 4)
      var y = 3 + (hi - values[i]) / range * (height - 6)
      if (i === 0) ctx.moveTo(x,y); else ctx.lineTo(x,y)
    }
    ctx.strokeStyle = lineColor; ctx.lineWidth = 1.6; ctx.stroke()
  }
}
