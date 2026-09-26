import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n
import "Cache.js" as Cache
import "fx"

// Candlestick chart for one coin, embedded in the neural.crypto panel. Fetches
// Binance klines for the selected timeframe and draws candles, volume and a
// last-price tag on a Canvas; the pointer inspects OHLC values. The panel
// owns currency/interval choices and injects them from the outside.
Item {
  id: root

  property var bar: null
  property string coinId: ""
  property string vs: "brl"
  property string interval: "1h"
  // True while the chart is actually on screen; gates fetching and the
  // auto-refresh timer so a closed panel stays idle.
  property bool active: false
  property var alerts: []
  property string quoteProvider: "binance"
  property int periodDays: 0
  property string requestKey: ""
  property string loadedKey: ""
  property var seriesCache: ({})
  property bool restoredSeries: false
  property var cacheOrder: []
  function saveSeries() {
    if (!root.loadedKey || !root.candles.length) return
    root.seriesCache[root.loadedKey] = { candles: root.candles, at: root.fetchedAt,
      start: root.viewStart, end: root.viewEnd, ended: root.historyEnded, restored: root.restoredSeries }
    var order = root.cacheOrder.filter(function(k) { return k !== root.loadedKey })
    order.push(root.loadedKey)
    while (order.length > 8) delete root.seriesCache[order.shift()]
    root.cacheOrder = order
    Cache.put("charts", root.loadedKey, root.seriesCache[root.loadedKey])
  }
  property bool requestOlder: false
  property bool historyEnded: false
  property double retryAt: 0
  readonly property string seriesKey: (pair ? pair.pair : "") + ":" + interval
  readonly property var chartAlerts: alerts.filter(function(a) {
    // An alert on a converted BRL quote cannot be drawn on a USDT axis.
    return a.vs === root.chartCurrency && (a.vs === "brl" || root.quoteProvider === "binance")
  })
  function selectPeriod(days) {
    root.periodDays = days
    var next = Model.periodInterval(days)
    if (root.interval !== next) root.intervalRequested(next)
    else { root.resetViewPending = true; root.refresh() }
  }
  function invalidateSeries() {
    root.saveSeries()
    proc.cancel(); root.loading = false
    root.loadedKey = root.seriesKey
    var saved = root.seriesCache[root.seriesKey] || Cache.get("charts", root.seriesKey)
    root.restoredSeries = !!(saved && saved.restored)
    root.hoverIndex = -1
    root.candles = saved ? saved.candles : []
    root.fetchedAt = saved ? saved.at : 0
    root.viewStart = saved ? saved.start : 0
    root.viewEnd = saved ? saved.end : 0
    root.historyEnded = saved ? saved.ended : false
    root.resetViewPending = !saved
    if (saved && root.periodDays > 0) root.resetView()
    root.error = ""
    if (root.active && (!saved || Date.now() - saved.at > 15000)) root.refresh()
  }
  onSeriesKeyChanged: Qt.callLater(root.invalidateSeries)
  onChartAlertsChanged: root.schedulePaint()

  signal backRequested()
  signal intervalRequested(string id)

  readonly property var pair: Model.chartPair(root.coinId, root.vs)
  readonly property string chartCurrency: root.pair ? root.pair.currency : "usd"
  readonly property color gainColor: Color.flatColor(Color.pick("crypto.gain", hue.green), hue.green)
  FxPalette { id: hue }
  readonly property color lossColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color tagTextColor: root.bar ? root.bar.background : Color.background
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  // Right-hand price axis width, shared by the painter and the pointer math.
  readonly property int plotInset: 64

  property var candles: []
  property bool loading: false
  property string error: ""
  property double fetchedAt: 0
  property int clockTick: 0
  property int hoverIndex: -1
  // Accumulator for partial wheel deltas (high-resolution/smooth wheels).
  property real wheelAccum: 0

  // Visible candle window into `candles` (end exclusive). Zoom and pan move
  // this window; a refresh keeps it, and a timeframe/coin change or a double
  // click resets it to the whole series.
  property int viewStart: 0
  property int viewEnd: 0
  property bool resetViewPending: false
  property real lastPointerX: -1
  readonly property int viewCount: {
    var total = candles.length
    if (total === 0) return 0
    var count = viewEnd - viewStart
    if (count <= 0 || count > total) return total
    return count
  }

  // Plot geometry from the last full paint, published so the crosshair
  // overlay can position itself without redrawing the candles.
  property real plotX0: 0
  property real plotDx: 1
  property real plotWidth: 0
  property int plotStart: 0
  property int plotCount: 0
  property real plotMin: 0
  property real plotSpan: 1
  property real plotTop: 0
  property real plotBottom: 0
  property real plotPriceBottom: 0
  property real plotPriceH: 1

  // Inspected candle: the hovered one, or the newest visible when the pointer
  // is out.
  readonly property var shown: hoverIndex >= 0 && hoverIndex < candles.length
    ? candles[hoverIndex]
    : (candles.length > 0 ? candles[Math.max(0, Math.min(candles.length - 1, viewEnd - 1))] : null)
  // Hovering shows the candle's own move; otherwise the move across the
  // visible window.
  readonly property bool showPeriodChange: !(hoverIndex >= 0 && hoverIndex < candles.length)
  readonly property real shownChange: {
    if (!shown) return 0
    if (showPeriodChange) {
      var first = candles[viewStart] || candles[0]
      return first && first.o > 0 ? (shown.c - first.o) / first.o * 100 : 0
    }
    return shown.o > 0 ? (shown.c - shown.o) / shown.o * 100 : 0
  }
  readonly property string ageLabel: {
    var tick = clockTick
    return fetchedAt > 0 ? Model.formatAge(Math.max(0, Math.floor((Date.now() - fetchedAt) / 1000))) : ""
  }

  implicitHeight: column.implicitHeight

  function refresh(older, force) {
    older = older === true
    if (!root.active || !root.pair || Date.now() < root.retryAt) return
    if (older && (root.historyEnded || root.candles.length === 0)) return
    if (proc.running) return
    if (root.loadedKey !== root.seriesKey) { Qt.callLater(root.invalidateSeries); return }
    root.requestKey = root.seriesKey
    root.requestOlder = older
    root.loading = true
    root.error = ""
    proc.get(Model.klinesUrl(root.pair.pair, root.interval, root.periodDays === 30 ? 181 : 180,
      older ? root.candles[0].t - 1 : 0), force === true ? 0 : (older ? 300000 : 60000), 10)
  }

  function schedulePaint() { if (root.active) canvas.requestPaint() }
  // Candles only repaint when the data, the zoom window or the size changes;
  // moving the pointer just redraws the thin crosshair overlay on top.
  onCandlesChanged: {
    root.schedulePaint()
    if (root.active) overlay.requestPaint()
  }
  onViewStartChanged: {
    root.schedulePaint()
    if (root.active) overlay.requestPaint()
  }
  onViewEndChanged: {
    root.schedulePaint()
    if (root.active) overlay.requestPaint()
  }
  onHoverIndexChanged: if (root.active) overlay.requestPaint()
  onWidthChanged: {
    root.schedulePaint()
    if (root.active) overlay.requestPaint()
  }
  onHeightChanged: {
    root.schedulePaint()
    if (root.active) overlay.requestPaint()
  }

  onActiveChanged: {
    if (root.active) root.schedulePaint()
    // Fresh enough data should not be re-fetched just because the view was
    // reopened; the auto-refresh timer takes over from here.
    if (active && (root.fetchedAt === 0 || Date.now() - root.fetchedAt > 15000)) root.refresh()
    else if (!active) { root.hoverIndex = -1; proc.cancel(); root.loading = false; root.saveSeries() }
  }

  Component.onCompleted: Qt.callLater(root.invalidateSeries)

  function css(color, alpha) {
    var a = alpha === undefined ? color.a : alpha
    return "rgba(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255) + ","
      + Math.round(color.b * 255) + "," + a + ")"
  }

  // ---- zoom / pan -----------------------------------------------------------

  function resetView() {
    root.viewStart = root.periodDays > 0 ? Model.periodStart(root.candles, root.periodDays) : 0
    root.viewEnd = root.candles.length
  }

  function clampView() {
    var total = root.candles.length
    if (total === 0) {
      root.viewStart = 0
      root.viewEnd = 0
      return
    }
    var count = root.viewCount > 0 ? root.viewCount : total
    var start = Math.max(0, Math.min(total - count, root.viewStart))
    root.viewStart = start
    root.viewEnd = start + count
  }

  function panBy(candles) {
    var total = root.candles.length
    var count = root.viewCount
    if (total === 0 || count === 0 || !candles) return
    var start = Math.max(0, Math.min(total - count, root.viewStart + candles))
    if (root.viewStart + candles < 0 && !proc.running) root.refresh(true)
    if (start === root.viewStart) return
    root.viewStart = start
    root.viewEnd = start + count
    if (root.lastPointerX >= 0) root.hoverAt(root.lastPointerX)
  }

  // steps > 0 zooms in (fewer candles), steps < 0 zooms out. `fraction` is the
  // pointer position across the plot (0..1) and stays anchored, so the candle
  // under the cursor does not move.
  function zoomAt(fraction, steps) {
    var total = root.candles.length
    if (total === 0 || !steps) return
    var count = root.viewCount
    var f = Math.max(0, Math.min(1, Number(fraction)))
    var anchor = root.viewStart + f * count
    var next = Math.round(count * Math.pow(0.8, steps))
    next = Math.max(Math.min(20, total), Math.min(total, next))
    if (next === count) return
    var start = Math.max(0, Math.min(total - next, Math.round(anchor - f * next)))
    root.viewStart = start
    root.viewEnd = start + next
    if (root.lastPointerX >= 0) root.hoverAt(root.lastPointerX)
  }

  // Maps a local x to the candle under it. Uses the live window (not the last
  // paint) so hovering right after a zoom still lands on the right candle.
  function hoverAt(x) {
    root.lastPointerX = x
    var total = root.candles.length
    var count = root.viewCount
    if (total === 0 || count === 0 || root.width <= 0) {
      root.hoverIndex = -1
      return
    }
    var plotW = Math.max(10, root.width - root.plotInset)
    var rel = Math.floor(x / plotW * count)
    var index = root.viewStart + Math.max(0, Math.min(count - 1, rel))
    root.hoverIndex = Math.max(0, Math.min(total - 1, index))
  }

  // Crosshair overlay: two dashed lines and a dot, positioned from the last
  // full-paint geometry.
  function paintCrosshair(ctx) {
    var w = overlay.width
    var h = overlay.height
    ctx.clearRect(0, 0, w, h)
    var index = root.hoverIndex
    if (index < root.plotStart || index >= root.plotStart + root.plotCount) return
    var candle = root.candles[index]
    if (!candle) return
    var x = Math.round(root.plotX0 + (index - root.plotStart) * root.plotDx) + 0.5
    var y = Math.round(root.plotPriceBottom - ((candle.c - root.plotMin) / root.plotSpan) * root.plotPriceH) + 0.5
    ctx.save()
    ctx.setLineDash([2, 2])
    ctx.beginPath()
    ctx.moveTo(x, root.plotTop)
    ctx.lineTo(x, root.plotBottom)
    ctx.moveTo(0, y)
    ctx.lineTo(root.plotWidth, y)
    ctx.strokeStyle = root.css(root.foreground, 0.4)
    ctx.lineWidth = 1
    ctx.stroke()
    ctx.restore()
    ctx.beginPath()
    ctx.arc(x, y, 2.6, 0, Math.PI * 2)
    ctx.fillStyle = root.css(candle.c >= candle.o ? root.gainColor : root.lossColor, 1)
    ctx.fill()
  }

  function acceptCandles(status, body, at) {
    if (root.requestKey !== root.seriesKey) return
    if (status === 429 || status === 418) {
      root.retryAt = Date.now() + 120000
      root.error = I18n.tr("limite da API · nova tentativa em 2 min")
      return
    }
    if (status !== 200 || !body) {
      root.error = I18n.tr("erro na API (HTTP ") + status + ")"
      return
    }
    try {
      var parsed = Model.parseKlines(body)
      if (parsed.length === 0) {
        if (root.requestOlder) { root.historyEnded = true; return }
        root.error = I18n.tr("sem dados para ") + root.pair.pair
        return
      }
      // Preserve the zoom window across the 30 s refresh: a panned view
      // stays put, a view at the right edge follows the new candles.
      var oldCount = root.viewCount
      var oldTotal = root.candles.length
      var wasAtRight = oldTotal === 0 || root.viewEnd >= oldTotal
      var oldStartTime = oldTotal > 0 ? root.candles[root.viewStart].t : 0
      var merged = root.requestOlder ? Model.mergeCandles(parsed, root.candles) : Model.mergeCandles(root.candles, parsed)
      if (root.requestOlder && merged.length === oldTotal) root.historyEnded = true
      root.candles = merged
      root.hoverIndex = -1
      root.error = ""
      if (!root.requestOlder) root.restoredSeries = false
      if (!root.requestOlder) root.fetchedAt = at
      if (root.resetViewPending || oldTotal === 0) {
        root.resetViewPending = false
        root.resetView()
      } else if (wasAtRight && oldCount > 0 && !root.requestOlder) {
        root.viewEnd = merged.length
        root.viewStart = Math.max(0, merged.length - oldCount)
      } else {
        var start = 0
        while (start < merged.length - 1 && merged[start].t < oldStartTime) start++
        root.viewStart = start
        root.viewEnd = Math.min(merged.length, start + oldCount)
      }
      if (root.lastPointerX >= 0) root.hoverAt(root.lastPointerX)
      root.saveSeries()
    } catch (e) {
      root.error = I18n.tr("falha ao ler os dados")
    }
  }
  Request {
    id: proc
    onCompleted: function(status, body, at) {
      root.loading = false
      root.acceptCandles(status, body, at)
    }
  }

  Timer {
    id: autoRefresh
    interval: 30000
    repeat: true
    running: root.active
    onTriggered: root.refresh()
  }

  Timer {
    id: ageTimer
    interval: 1000
    repeat: true
    running: root.active
    onTriggered: root.clockTick += 1
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(8)

    Row {
      spacing: Style.space(8)
      Text { text: I18n.tr("PERÍODO"); color: Qt.darker(root.foreground, 1.5); font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
      ButtonGroup {
        options: [{ value: "1", label: I18n.tr("1 dia") }, { value: "7", label: I18n.tr("1 semana") }, { value: "30", label: I18n.tr("1 mês") }]
        value: String(root.periodDays)
        foreground: root.foreground; accent: Color.accent
        fontFamily: root.fontFamily; fontSize: Style.font.caption
        onChanged: function(next) { root.selectPeriod(Number(next)) }
      }
      Button {
        text: I18n.tr("Restaurar zoom")
        foreground: root.foreground; accent: Color.accent
        fontFamily: root.fontFamily; fontSize: Style.font.caption
        onClicked: root.resetView()
      }
    }
    Text {
      text: I18n.tr("INTERVALO DE CADA CANDLE")
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily; font.pixelSize: Style.font.caption
    }
    ButtonGroup {
      id: tfChips
      width: parent.width
      options: Model.chartIntervalOptions()
      value: root.interval
      foreground: root.foreground
      background: "transparent"
      accent: Color.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      focusable: false
      onChanged: function(next) { root.periodDays = 0; root.intervalRequested(next) }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: root.shown ? Model.quotePrice(root.shown.c, "binance", root.chartCurrency) : "—"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: root.shown !== null
        text: (Model.arrow(root.shownChange) !== "" ? Model.arrow(root.shownChange) + " " : "")
          + Model.formatChange(root.shownChange) + (root.showPeriodChange ? I18n.tr(" no período") : "")
        color: root.shownChange < 0 ? root.lossColor : root.gainColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      elide: Text.ElideRight
      visible: root.shown !== null
      text: {
        var s = root.shown
        if (!s) return ""
        return (root.hoverIndex >= 0 ? Model.formatChartTime(s.t, root.interval) + " · " : "")
          + I18n.tr("ab ") + Model.formatCompact(s.o) + I18n.tr(" · máx ") + Model.formatCompact(s.h)
          + I18n.tr(" · mín ") + Model.formatCompact(s.l) + I18n.tr(" · fec ") + Model.formatCompact(s.c)
          + I18n.tr(" · vol ") + Model.formatCompact(s.v)
      }
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      width: parent.width
      height: Style.space(240)

      Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
          var ctx = getContext("2d")
          var w = canvas.width
          var h = canvas.height
          ctx.clearRect(0, 0, w, h)
          if (!(w > 1) || !(h > 1) || root.candles.length === 0) return

          var axisW = root.plotInset
          var timeH = 18
          var gap = 6
          var plotW = Math.max(10, w - axisW)
          var plotTop = 4
          var plotBottom = h - timeH - gap
          var volH = Math.round((plotBottom - plotTop) * 0.16)
          var priceH = plotBottom - plotTop - volH - gap
          var priceBottom = plotTop + priceH

          // The window may be zoomed/panned; everything below maps slots
          // 0..n-1 to absolute candle indices first+slot.
          var first = root.viewStart
          var n = root.viewCount
          if (n === 0) return
          var min = Infinity
          var max = -Infinity
          var maxVol = 0
          for (var i = first; i < first + n; i++) {
            var c = root.candles[i]
            if (c.l < min) min = c.l
            if (c.h > max) max = c.h
            if (c.v > maxVol) maxVol = c.v
          }
          var span = max - min
          if (!(span > 0)) span = Math.max(1e-9, Math.abs(max) * 0.02)
          min -= span * 0.05
          max += span * 0.05
          span = max - min

          function priceY(v) {
            return priceBottom - ((v - min) / span) * priceH
          }
          function timeX(index) {
            return plotW * (index + 0.5) / n
          }

          // Published for paintCrosshair()/hoverAt(); the overlay reuses this
          // geometry instead of recomputing the whole plot.
          root.plotX0 = timeX(0)
          root.plotDx = plotW / n
          root.plotWidth = plotW
          root.plotStart = first
          root.plotCount = n
          root.plotMin = min
          root.plotSpan = span
          root.plotTop = plotTop
          root.plotBottom = h - timeH
          root.plotPriceBottom = priceBottom
          root.plotPriceH = priceH

          ctx.font = Style.font.caption + "px '" + root.fontFamily + "'"
          ctx.textBaseline = "middle"

          // Horizontal grid + right-side price scale.
          for (var g = 0; g <= 4; g++) {
            var ratio = g / 4
            var gy = Math.round(plotTop + priceH * ratio) + 0.5
            var value = max - span * ratio
            ctx.beginPath()
            ctx.moveTo(0, gy)
            ctx.lineTo(plotW, gy)
            ctx.strokeStyle = root.css(root.foreground, g === 4 ? 0.16 : 0.07)
            ctx.lineWidth = 1
            ctx.stroke()
            ctx.fillStyle = root.css(root.foreground, 0.45)
            ctx.textAlign = "left"
            ctx.fillText(Model.formatCompact(value), plotW + 6, gy)
          }

          // Volume pane.
          for (var v = 0; v < n; v++) {
            var k = root.candles[first + v]
            var vh = maxVol > 0 ? Math.max(1, Math.round((k.v / maxVol) * volH)) : 0
            if (vh === 0) continue
            var vx = timeX(v)
            ctx.fillStyle = root.css(k.c >= k.o ? root.gainColor : root.lossColor, 0.32)
            ctx.fillRect(vx - Math.max(0.5, plotW / n * 0.32), h - timeH - vh, Math.max(1, plotW / n * 0.64), vh)
          }

          // Candles.
          var candleW = Math.max(1, Math.floor(plotW / n * 0.62))
          for (var j = 0; j < n; j++) {
            var kk = root.candles[first + j]
            var x = Math.round(timeX(j)) + 0.5
            var up = kk.c >= kk.o
            var color = up ? root.gainColor : root.lossColor
            ctx.strokeStyle = root.css(color, 1)
            ctx.fillStyle = root.css(color, 1)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(x, priceY(kk.h))
            ctx.lineTo(x, priceY(kk.l))
            ctx.stroke()
            if (candleW <= 2) {
              ctx.fillRect(x - 1, Math.min(priceY(kk.o), priceY(kk.c)), 2, Math.max(1, Math.abs(priceY(kk.c) - priceY(kk.o))))
            } else {
              var bodyTop = priceY(Math.max(kk.o, kk.c))
              var bodyH = Math.max(1, Math.abs(priceY(kk.c) - priceY(kk.o)))
              ctx.fillRect(x - candleW / 2, bodyTop, candleW, bodyH)
            }
          }

          // Targets use the same quote currency as the chart. Out-of-range
          // levels get an edge label without distorting the candle scale.
          ctx.save()
          ctx.font = Style.font.caption + "px '" + root.fontFamily + "'"
          ctx.textAlign = "left"
          ctx.strokeStyle = root.css(Color.accent, 0.85)
          ctx.fillStyle = root.css(Color.accent, 1)
          ctx.setLineDash([5, 4])
          for (var ai = 0; ai < root.chartAlerts.length; ai++) {
            var target = root.chartAlerts[ai].price
            var ay = priceY(target)
            if (ay >= plotTop && ay <= priceBottom) {
              ctx.beginPath(); ctx.moveTo(0, ay); ctx.lineTo(plotW, ay); ctx.stroke()
            }
            var labelY = Math.max(plotTop + 12, Math.min(priceBottom - 6, ay - 5))
            ctx.fillText((target > max ? "↑ " : target < min ? "↓ " : "") + I18n.tr("alvo ") + Model.formatCompact(target), 4, labelY)
          }
          ctx.restore()

          // Time labels, deduped so narrow windows do not overprint.
          ctx.fillStyle = root.css(root.foreground, 0.45)
          var labelIdx = [0, Math.floor(n / 3), Math.floor(2 * n / 3), n - 1]
          var lastLabel = -1
          for (var l = 0; l < labelIdx.length; l++) {
            var li = labelIdx[l]
            if (li < 0 || li >= n || li === lastLabel) continue
            lastLabel = li
            var lx = timeX(li)
            ctx.textAlign = l === 0 ? "left" : (l === labelIdx.length - 1 ? "right" : "center")
            var lxx = l === 0 ? 2 : (l === labelIdx.length - 1 ? plotW - 2 : lx)
            ctx.fillText(Model.formatChartTime(root.candles[first + li].t, root.interval), lxx, h - timeH / 2)
          }

          // Last price line + tag, only while the newest candle is in view.
          if (first + n === root.candles.length) {
            var last = root.candles[root.candles.length - 1]
            var lastY = Math.round(priceY(last.c)) + 0.5
            ctx.save()
            ctx.setLineDash([2, 3])
            ctx.beginPath()
            ctx.moveTo(0, lastY)
            ctx.lineTo(plotW, lastY)
            ctx.strokeStyle = root.css(last.c >= last.o ? root.gainColor : root.lossColor, 0.65)
            ctx.lineWidth = 1
            ctx.stroke()
            ctx.restore()

            var tag = Model.formatCompact(last.c)
            ctx.font = Style.font.caption + "px '" + root.fontFamily + "'"
            var tagW = ctx.measureText(tag).width + 8
            ctx.fillStyle = root.css(last.c >= last.o ? root.gainColor : root.lossColor, 1)
            ctx.fillRect(plotW + 2, lastY - 8, Math.min(axisW, tagW + 2), 16)
            ctx.fillStyle = root.css(root.tagTextColor, 0.95)
            ctx.textAlign = "left"
            ctx.fillText(tag, plotW + 6, lastY)
          }
        }
      }

      // Thin overlay for the pointer crosshair. Keeping it off the candle
      // canvas means pointer motion never re-rasterizes ~180 candles.
      Canvas {
        id: overlay
        anchors.fill: parent
        onPaint: root.paintCrosshair(getContext("2d"))
      }

      // Pointer: hover inspects, dragging pans, wheel zooms, double click
      // resets. The press is accepted here so the panel's Flickable does not
      // fight the drag.
      MouseArea {
        id: chartPointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: dragLastX >= 0 ? Qt.ClosedHandCursor : Qt.CrossCursor
        property real dragLastX: -1

        onPressed: function(mouse) { dragLastX = mouse.x }
        onReleased: dragLastX = -1
        onPositionChanged: function(mouse) {
          if (pressed && dragLastX >= 0 && root.plotDx > 0) {
            var candles = Math.round((dragLastX - mouse.x) / root.plotDx)
            if (candles !== 0) {
              root.panBy(candles)
              dragLastX = mouse.x
            }
          }
          root.hoverAt(mouse.x)
        }
        onExited: {
          root.lastPointerX = -1
          root.hoverIndex = -1
        }
        onDoubleClicked: root.resetView()

        // Wheel events land here, not on a WheelHandler (this shell's panels
        // never deliver them to pointer handlers). Partial deltas accumulate
        // so smooth/high-resolution wheels zoom one notch at a time, and
        // pixelDelta-only devices still work.
        onWheel: function(wheel) {
          if (root.candles.length === 0 || root.plotWidth <= 0) {
            wheel.accepted = false
            return
          }
          var dy = wheel.angleDelta ? wheel.angleDelta.y : 0
          if (dy === 0 && wheel.pixelDelta) dy = wheel.pixelDelta.y * 8
          if (dy === 0) {
            wheel.accepted = false
            return
          }
          var notches
          if (Math.abs(dy) >= 120) {
            // Normal wheel notch: one event, one step.
            notches = Math.round(dy / 120)
            root.wheelAccum = 0
          } else {
            // Smooth/high-resolution wheels dribble smaller deltas.
            root.wheelAccum += dy
            notches = root.wheelAccum > 0
              ? Math.floor(root.wheelAccum / 120)
              : Math.ceil(root.wheelAccum / 120)
            root.wheelAccum -= notches * 120
          }
          if (notches === 0) {
            wheel.accepted = true
            return
          }
          var localX = wheel.x !== undefined && !isNaN(wheel.x) ? wheel.x : root.lastPointerX
          if (!(localX >= 0)) localX = root.plotWidth / 2
          root.zoomAt(localX / root.plotWidth, Math.max(-3, Math.min(3, notches)))
          wheel.accepted = true
        }
      }

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: root.error !== "" || root.candles.length === 0
        textFormat: Text.PlainText
        text: root.error !== "" ? root.error : (root.loading ? I18n.tr("carregando ") + (root.pair ? root.pair.pair : "") + "…" : I18n.tr("sem dados"))
        color: root.error !== "" ? root.lossColor : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: {
        var source = root.pair ? root.pair.pair : I18n.tr("par indisponível")
        var hint = "Binance · " + source + I18n.tr(" · candle ") + root.interval
        if (root.restoredSeries) hint += " · cache"
        if (root.ageLabel !== "") hint += I18n.tr(" · há ") + root.ageLabel
        if (root.viewCount < root.candles.length) hint += " · " + root.viewCount + "/" + root.candles.length + I18n.tr(" velas")
        if (root.loading && root.requestOlder) hint += I18n.tr(" · carregando histórico…")
        if (root.alerts.length > root.chartAlerts.length) hint += I18n.tr(" · alvos em outra moeda não são sobrepostos")
        return hint + I18n.tr(" · scroll amplia · arraste para ver o histórico")
      }
      color: Qt.darker(root.foreground, 1.8)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

}
