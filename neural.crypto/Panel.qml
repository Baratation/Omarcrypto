import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "fx"
import "I18n.js" as I18n
import "Cache.js" as Cache
import "Http.js" as Http

// Market poller and detail popup for the neural.crypto bar pill. The pill
// forwards clicks and IPC here; configuration (`coins`, `provider`, `vs`,
// `vs2`, `rotate`) is read from this widget's inline shell.json entry and
// hot-reloads on save. The middle of the panel is the coin picker, which
// writes the same entry back through the host widget.
Panel {
  id: root
  moduleName: "neural.crypto"
  ipcTarget: "neural.crypto"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string provider: Model.normalizedProvider(setting("provider", "binance"))
  readonly property var coins: Model.canonicalCoins(Model.normalizedCoins(setting("coins", [])))
  readonly property string vs: Model.normalizedVs(setting("vs", "brl"))
  readonly property string vs2: {
    var raw = String(setting("vs2", vs === "brl" ? "usd" : "brl"))
    return raw.trim() === "" ? "" : Model.normalizedVs(raw)
  }
  // Currencies to fetch: the two display ones plus every currency an armed
  // alert was stored in, so alerts keep being checked after a switch.
  readonly property var currencies: {
    var out = [vs]
    if (vs2 !== "" && vs2 !== vs) out.push(vs2)
    for (var i = 0; i < alerts.length; i++) {
      if (alerts[i].armed && out.indexOf(alerts[i].vs) === -1) out.push(alerts[i].vs)
    }
    return out
  }
  readonly property string vsLabel: (provider === "binance" && vs === "usd" ? "USDT" : vs.toUpperCase()) + (vs2 !== "" && vs2 !== vs ? "/" + (provider === "binance" && vs2 === "usd" ? "USDT" : vs2.toUpperCase()) : "")
  property var savedAlerts: []
  property bool alertsReady: false
  property string alertError: ""
  property var alertQueue: []
  // Alerts live in their own file, changed only by the `alerts` script that
  // ships next to this panel (lock + atomic replace, shared by all monitors).
  readonly property string alertsBackend: decodeURIComponent(Qt.resolvedUrl("alerts").toString().replace(/^file:\/\//, ""))
  readonly property var alerts: Model.normalizedAlerts(savedAlerts)
  function applyAlerts(raw) {
    try {
      var data = JSON.parse(raw)
      if (!Array.isArray(data.alerts)) return
      savedAlerts = data.alerts
      alertsReady = true
      if (hostWidget && hostWidget.retireLegacyAlerts) hostWidget.retireLegacyAlerts()
    } catch (e) { alertError = I18n.tr("Não foi possível ler os alertas; arquivo preservado") }
  }
  function alertCommand(op, payload) {
    alertQueue = alertQueue.concat([{op: op, payload: payload || {}}])
    nextAlertCommand()
  }
  function nextAlertCommand() {
    if (alertWriter.running || !alertQueue.length) return
    var command = alertQueue[0]
    alertQueue = alertQueue.slice(1)
    alertError = ""
    alertWriter.command = [root.alertsBackend, command.op, JSON.stringify(command.payload)]
    alertWriter.running = true
  }
  FileView {
    id: alertsFile
    path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/omarchy/crypto/alerts.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyAlerts(text())
    property bool attempted: false
    onLoadFailed: if (!attempted) { attempted = true; root.alertCommand("init", {}) }
  }
  Process {
    id: alertWriter
    stdout: StdioCollector { onStreamFinished: root.applyAlerts(text) }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) root.alertError = text.trim() }
    onExited: function(code) {
      alertsFile.reload()
      if (code !== 0 && !root.alertError) root.alertError = I18n.tr("Não foi possível salvar os alertas")
      Qt.callLater(root.nextAlertCommand)
    }
  }
  readonly property int armedAlertCount: {
    var count = 0
    for (var i = 0; i < alerts.length; i++) if (alerts[i].armed) count++
    return count
  }
  readonly property string chartTf: Model.normalizedChartInterval(setting("chartTf", "1h"))
  readonly property int rotateSeconds: Math.max(0, Math.floor(Number(setting("rotate", 0)) || 0))
  // Last non-zero interval, so the cycle switch in the panel can be turned
  // back on without forgetting the user's cadence.
  property int rotateMemory: 10
  readonly property bool cycling: rotateSeconds > 0 && coins.length > 1
  readonly property string pinnedId: Model.normalizedPin(setting("pin", ""), coins)

  property var basePrices: ({})
  property double baseFetchedAt: 0
  property var fxRates: ({})
  property double fxAt: 0
  property double fxRetryAt: 0
  property bool fxFresh: false
  property string fxRequestUrl: ""
  property string fxError: ""
  readonly property bool needsFx: root.provider === "binance" && root.currencies.some(function(c) { return c !== "usd" && c !== "brl" })
  readonly property var fetchCurrencies: root.needsFx && root.currencies.indexOf("usd") < 0 ? root.currencies.concat(["usd"]) : root.currencies
  // Pairs Binance answered as unknown (a typo in shell.json, a coin added
  // under CoinGecko). One of them fails the whole batch, so after a per-pair
  // probe they stay out of it for the rest of the session.
  property var badPairs: []
  property bool probing: false
  readonly property string quoteUrl: Model.apiUrl(root.provider, root.coins, root.fetchCurrencies, root.badPairs)
  // Coins the last successful answer had no price for (delisted, unknown).
  property var missingCoins: []
  readonly property string priceCacheKey: root.provider + ":" + root.coins.join(",") + ":" + root.currencies.join(",")
  readonly property string fxUrl: Model.coingeckoUrl(["tether"], Model.CURRENCIES.filter(function(c) { return c !== "usd" && c !== "brl" }))
  property var prices: ({})
  property bool restoredPrices: false
  property bool loading: false
  property bool fetchFailed: false
  property bool rateLimited: false
  property string apiError: ""
  property double cooldownUntil: 0
  property double fetchedAt: 0
  property int retries: 0
  property int rotateIndex: 0
  property int clockTick: 0
  property bool cycleParsed: false
  property bool primed: false
  property bool refreshPending: false
  property string lastUrl: ""

  // Embedded views: the coin list (default) or the candle chart of one coin.
  property string view: "list"

  FxPalette { id: hue }
  property string listTab: "coins"
  property bool settingsExpanded: false
  property bool currenciesExpanded: false
  onSettingsExpandedChanged: if (!settingsExpanded) currenciesExpanded = false
  property string sortMode: "custom"
  property var sparkCache: ({})
  function rememberSpark(key, entry) {
    // The emitting delegate already owns the values; mutation keeps a copy for
    // future delegates without invalidating every row's cache binding.
    root.sparkCache[key] = entry
    Cache.put("sparks", key, entry)
  }
  readonly property bool stale: restoredPrices || fetchFailed || apiError !== "" || ageSeconds > 150
  readonly property var displayedCoins: {
    var list = coins.slice()
    if (sortMode === "change") list.sort(function(a,b) {
      var qa = root.quoteFor(a, root.vs), qb = root.quoteFor(b, root.vs)
      return (qb && qb.change !== null ? qb.change : -Infinity) - (qa && qa.change !== null ? qa.change : -Infinity)
    })
    else if (sortMode === "name") list.sort(function(a,b) { return Model.tickerFor(a).localeCompare(Model.tickerFor(b)) })
    return list
  }
  property string selectedCoin: ""
  property string selectedAlert: ""
  readonly property string actionCoin: root.coins.indexOf(selectedCoin) >= 0 ? selectedCoin : root.primaryId
  function moveSelection(delta) {
    if (!delta) return
    var alertTab = root.listTab === "alerts"
    var list = alertTab ? root.alerts.map(function(a) { return a.id }) : root.displayedCoins
    if (!list.length) return
    var current = list.indexOf(alertTab ? root.selectedAlert : root.selectedCoin)
    var index = Math.max(0, Math.min(list.length - 1, current < 0 ? 0 : current + delta))
    if (alertTab) root.selectedAlert = list[index]
    else root.selectedCoin = list[index]
    var row = (alertTab ? alertRepeater : coinRepeater).itemAt(index)
    if (row) {
      var top = row.mapToItem(column, 0, 0).y
      if (top < scroll.contentY) scroll.contentY = top
      else if (top + row.height > scroll.contentY + scroll.height) scroll.contentY = Math.max(0, top + row.height - scroll.height)
    }
  }
  function activateSelection() {
    if (root.view === "chart") return
    if (root.listTab === "alerts") root.editAlert(root.selectedAlert || (root.alerts[0] ? root.alerts[0].id : ""))
    else root.openChart(root.actionCoin)
  }
  ListModel { id: coinRows }
  function syncCoinRows() {
    var wanted = root.displayedCoins
    if (wanted.indexOf(root.selectedCoin) < 0) root.selectedCoin = wanted[0] || ""
    for (var i = coinRows.count - 1; i >= 0; i--)
      if (wanted.indexOf(coinRows.get(i).coinId) < 0) coinRows.remove(i)
    for (var target = 0; target < wanted.length; target++) {
      var found = target
      while (found < coinRows.count && coinRows.get(found).coinId !== wanted[target]) found++
      if (found === coinRows.count) coinRows.insert(target, {coinId: wanted[target]})
      else if (found !== target) coinRows.move(found, target, 1)
    }
  }
  onDisplayedCoinsChanged: Qt.callLater(root.syncCoinRows)
  function moveCoin(id, offset) {
    var list = coins.slice(), from = list.indexOf(id)
    var to = Math.max(0, Math.min(list.length - 1, from + offset))
    if (from < 0 || from === to) return
    list.splice(from, 1); list.splice(to, 0, id)
    root.sortMode = "custom"
    root.setCoins(list)
  }
  function nearestAlert(id) {
    var result = "", distance = Infinity
    root.alertsFor(id).forEach(function(a) {
      var q = root.quoteFor(id, a.vs)
      if (!a.armed || !q || !(q.price > 0)) return
      var d = Math.abs(a.price / q.price - 1)
      if (d < distance) { distance = d; result = Model.alertDistance(a, q.price) }
    })
    return result
  }
  function presetAlert(percent) {
    var q = root.alertQuote()
    if (q) alertField.text = Model.formatNumber(q.price * (1 + percent / 100), q.price < 1 ? 8 : 2)
  }
  property string chartCoin: ""

  // Inline alert editor, opened from the bell button or a right click on a
  // coin row. `alertTarget` is raw text, parsed on save so pt-BR formats work.
  property string alertCoin: ""
  property string alertTarget: ""
  property string editingAlertId: ""
  property string alertVs: "brl"
  property string alertDirection: "auto"
  property bool alertWasArmed: true
  readonly property string targetDirection: alertDirection !== "auto" ? alertDirection
    : (alertQuote() && alertTargetValue() < alertQuote().price ? "below" : "above")

  // Coin picker state. `remoteResults` comes from the live provider search
  // that fills in whatever the curated catalogue does not cover.
  property string searchQuery: ""
  property int pickerIndex: 0
  property var remoteResults: []
  property bool remoteLoading: false
  property bool remoteFailed: false
  property bool remotePending: false
  property var binanceBases: []
  property bool binanceLoaded: false
  readonly property var pickerResults: Model.mergePickerResults(
    Model.searchCatalog(searchQuery, coins, provider),
    remoteResults,
    coins
  )

  readonly property bool hasData: Object.keys(prices).length > 0
  readonly property string rotateId: coins.length > 0
    ? coins[((rotateIndex % coins.length) + coins.length) % coins.length]
    : ""
  // Cycling and pinning are alternatives: an explicit pin wins, otherwise the
  // pill follows the rotate timer (or stays on the first coin when it is off).
  readonly property string primaryId: pinnedId !== "" ? pinnedId : rotateId
  readonly property var primary: primaryId !== "" && prices[primaryId] ? prices[primaryId][vs] || null : null
  readonly property real primaryChange: primary && primary.change !== null ? primary.change : 0

  // The pill draws the primary coin's last 24 h. The list sparklines only
  // poll while the panel is open, so the pill keeps its own 5-minute series,
  // and its last point follows the live quote so the line never lags the
  // number next to it (only when the series is in the quote's currency).
  property var primarySparkValues: []
  property string primarySparkKey: ""
  readonly property var primarySpark: {
    var values = primarySparkValues
    var pair = Model.chartPair(primaryId, vs)
    if (!pair || pair.pair !== primarySparkKey || values.length < 2) return []
    if (!primary || pair.currency !== vs) return values
    var out = values.slice()
    out[out.length - 1] = primary.price
    return out
  }
  function refreshPrimarySpark() {
    var pair = Model.chartPair(root.primaryId, root.vs)
    if (!pair) { primarySparkReq.cancel(); root.primarySparkValues = []; root.primarySparkKey = ""; return }
    if (pair.pair !== root.primarySparkKey) {
      var saved = root.sparkCache[pair.pair] || Cache.get("sparks", pair.pair)
      root.primarySparkValues = saved ? saved.values : []
      root.primarySparkKey = pair.pair
      if (saved && Date.now() - saved.at < 300000) return
    }
    primarySparkReq.get(Model.klinesUrl(pair.pair, "15m", 97), 240000, 1)
  }
  Request {
    id: primarySparkReq
    onCompleted: function(status, body, at) {
      if (status !== 200) return
      try {
        var key = Model.chartPair(root.primaryId, root.vs)
        var values = Model.parseKlines(body).map(function(c) { return c.c })
        if (!key || key.pair !== root.primarySparkKey || values.length < 2) return
        root.primarySparkValues = values
        root.rememberSpark(key.pair, { values: values, at: at })
      } catch (e) {}
    }
  }
  Timer {
    interval: 300000
    repeat: true
    running: root.primed
    onTriggered: root.refreshPrimarySpark()
  }
  onPrimaryIdChanged: if (root.primed) root.refreshPrimarySpark()

  function quoteFor(id, currency) {
    var entry = prices[id]
    if (!entry || !entry[currency]) return null
    return entry[currency]
  }

  readonly property int ageSeconds: {
    var tick = clockTick
    return fetchedAt > 0 ? Math.max(0, Math.floor((Date.now() - fetchedAt) / 1000)) : -1
  }

  readonly property string label: {
    if (primary) {
      var direction = Model.arrow(primaryChange)
      return (root.stale ? "⚠ " : "") + Model.tickerFor(primaryId) + " "
        + Model.formatCompact(primary.price) + (direction !== "" ? " " + direction : "")
    }
    if (fetchFailed) return "⚠"
    return primaryId !== "" ? Model.tickerFor(primaryId) + " …" : "⚠"
  }

  readonly property string tooltip: {
    if (primary) {
      var text = Model.coinName(primaryId) + " " + Model.quotePrice(primary.price, root.provider, vs)
      var second = vs2 !== "" ? root.quoteFor(primaryId, vs2) : null
      if (second) text += " (" + Model.quotePrice(second.price, root.provider, vs2) + ")"
      return text + " " + Model.arrow(primaryChange) + Model.formatChange(primaryChange) + " (24h)"
        + (root.stale ? I18n.tr(" · cotação antiga · há ") + Model.formatAge(root.ageSeconds) : "")
    }
    return fetchFailed ? I18n.tr("Cotação indisponível") : I18n.tr("Consultando ") + Model.coinName(primaryId) + "…"
  }

  readonly property string summaryText: {
    var parts = []
    for (var i = 0; i < coins.length; i++) {
      var quote = root.quoteFor(coins[i], vs)
      if (!quote) continue
      var text = Model.tickerFor(coins[i]) + " " + Model.quotePrice(quote.price, root.provider, vs)
      var second = vs2 !== "" ? root.quoteFor(coins[i], vs2) : null
      if (second) text += " (" + Model.quotePrice(second.price, root.provider, vs2) + ")"
      parts.push(text + " " + Model.arrow(quote.change) + Model.formatChange(quote.change))
    }
    return parts.join(" · ")
  }

  readonly property int cooldownRemaining: {
    var tick = clockTick
    return cooldownUntil > 0 ? Math.max(0, Math.ceil((cooldownUntil - Date.now()) / 1000)) : 0
  }

  readonly property string statusText: {
    if (loading && !hasData) return I18n.tr("consultando…")
    if (restoredPrices) return I18n.tr("cache · há ") + Model.formatAge(ageSeconds)
    if (root.needsFx && root.fxError) return root.fxError
    if (rateLimited) return I18n.tr("limite da API")
    if (apiError !== "") return I18n.tr("erro na API")
    if (fetchFailed) return I18n.tr("sem conexão")
    if (ageSeconds >= 0) return I18n.tr("atualizado há ") + Model.formatAge(ageSeconds)
    return I18n.tr("aguardando")
  }

  readonly property string statusDetail: {
    if (rateLimited) return I18n.tr("limite do provedor · nova tentativa em ") + Model.formatAge(cooldownRemaining)
    if (apiError !== "") return apiError
    if (fetchFailed && hasData) return I18n.tr("sem conexão · último preço há ") + Model.formatAge(ageSeconds)
    if (fetchFailed) return I18n.tr("sem resposta do provedor · r tenta de novo")
    if (root.needsFx) return I18n.tr("Binance × CoinGecko · convertido") + (root.fxError ? " · " + root.fxError : "")
    return I18n.tr("fonte: ") + (provider === "coingecko" ? "CoinGecko" : "Binance") + " · " + root.vsLabel
      + I18n.tr(" · r atualiza · u moeda · c cicla")
  }

  function open() {
    if (hasData && Date.now() - root.fetchedAt < 15000) {
      root.controller.show()
      return
    }
    root.controller.show()
    root.refresh()
  }

  function close() {
    root.currenciesExpanded = false
    coinSearch.text = ""
    root.searchQuery = ""
    root.pickerIndex = 0
    root.closeAlertEditor()
    root.backToList()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    // A config change can land while a request is in flight; queue it instead
    // of dropping it, or the coin list would stay stale until the next tick.
    if (priceProc.running) {
      root.refreshPending = true
      return
    }
    if (root.rateLimited && Date.now() < root.cooldownUntil) return
    root.refreshFx()
    var url = root.quoteUrl
    root.loading = true
    root.cycleParsed = false
    root.lastUrl = url
    priceProc.get(url, 1000, 5)
  }

  function cycleRefresh() {
    root.retries = 0
    root.refresh()
  }

  function handleFailure() {
    if (root.rateLimited) return
    root.fetchFailed = true
    if (root.retries < 2) {
      root.retries += 1
      retryTimer.restart()
    }
  }

  function beginCooldown() {
    root.rateLimited = true
    root.fetchFailed = true
    root.retries = 0
    root.cooldownUntil = Date.now() + 120000
  }

  // ---- coin picker: persists straight into this widget's shell.json entry.

  function setCoins(list) {
    if (hostWidget && hostWidget.setSetting) hostWidget.setSetting("coins", list)
  }

  function addCoin(id) {
    if (coins.indexOf(id) !== -1) return
    var next = coins.slice()
    next.push(id)
    root.setCoins(next)
    // Clear the field as well, so the next search starts fresh (it is only
    // one-way bound to `searchQuery`).
    coinSearch.text = ""
    root.searchQuery = ""
    root.pickerIndex = 0
  }

  function removeCoin(id) {
    if (coins.length <= 1) return
    var next = []
    for (var i = 0; i < coins.length; i++) if (coins[i] !== id) next.push(coins[i])
    if (root.pinnedId === id && hostWidget && hostWidget.setSetting) hostWidget.setSetting("pin", "")
    // Alerts for a coin that is gone would never have a quote to fire on.
    root.alertsFor(id).forEach(function(a) { root.alertCommand("remove", {id: a.id}) })
    if (root.alertCoin === id) root.closeAlertEditor()
    if (root.chartCoin === id) root.backToList()
    root.setCoins(next)
  }

  function toggleCoin(id) {
    if (coins.indexOf(id) !== -1) root.removeCoin(id)
    else root.addCoin(id)
  }

  // ---- pill controls: main currency, cycling and pinning.

  function setCurrency(next) {
    if (!hostWidget || !hostWidget.setSetting) return
    var clean = Model.normalizedVs(next)
    var old = root.vs
    if (root.vs2 === clean) hostWidget.setSetting("vs2", old)
    hostWidget.setSetting("vs", clean)
  }

  function toggleCurrency() {
    root.setCurrency(root.vs2 && root.vs2 !== root.vs ? root.vs2 : Model.CURRENCIES[(Model.CURRENCIES.indexOf(root.vs) + 1) % Model.CURRENCIES.length])
  }

  function setCycling(on) {
    if (!hostWidget || !hostWidget.setSetting) return
    if (on) {
      if (root.coins.length < 2) return
      // Start the cycle from the coin on screen (pinned or current) instead of
      // jumping back to the first one.
      var anchor = root.coins.indexOf(root.pinnedId)
      if (anchor >= 0) root.rotateIndex = anchor
      hostWidget.setSetting("pin", "")
      hostWidget.setSetting("rotate", root.rotateMemory > 0 ? root.rotateMemory : 10)
    } else {
      // Turning cycling off pins the coin that was being shown.
      hostWidget.setSetting("pin", root.primaryId)
      hostWidget.setSetting("rotate", 0)
    }
  }

  function togglePin(id) {
    if (!hostWidget || !hostWidget.setSetting) return
    if (root.pinnedId === id) {
      hostWidget.setSetting("pin", "")
      return
    }
    // Pinning means parking the pill, so it also stops the cycle.
    hostWidget.setSetting("pin", id)
    if (root.rotateSeconds > 0) hostWidget.setSetting("rotate", 0)
  }

  function commitPicker() {
    var results = root.pickerResults
    if (results.length === 0) return
    var index = Math.max(0, Math.min(root.pickerIndex, results.length - 1))
    root.toggleCoin(results[index].id)
  }

  function focusSearch() {
    root.listTab = "coins"
    root.settingsExpanded = true
    Qt.callLater(function() {
      coinSearch.text = ""
      coinSearch.forceActiveFocus()
    })
  }

  // ---- chart view ----------------------------------------------------------

  // Keep the primary chart warm after each price refresh. The shared HTTP job
  // is reused if the user clicks while it is still in flight.
  function warmChart() {
    if (root.view !== "list") return
    var pair = Model.chartPair(root.primaryId, root.vs)
    if (!pair) return
    var chart = root.chartItem()
    var currentReady = chart && chart.coinId === root.primaryId && chart.interval === root.chartTf
      && chart.fetchedAt > 0 && Date.now() - chart.fetchedAt < 60000
    if (!currentReady)
      chartWarmup.get(Model.klinesUrl(pair.pair, root.chartTf, 180), 60000, 2)
    // The period presets are the most likely next clicks. Warming their raw
    // responses lets Chart parse them immediately without extra network wait.
    chartWarmDay.get(Model.klinesUrl(pair.pair, "15m", 180), 60000, 1)
    chartWarmWeek.get(Model.klinesUrl(pair.pair, "1h", 180), 60000, 1)
    chartWarmMonth.get(Model.klinesUrl(pair.pair, "4h", 181), 60000, 1)
  }
  Request { id: chartWarmup }
  Request { id: chartWarmDay }
  Request { id: chartWarmWeek }
  Request { id: chartWarmMonth }
  function chartItem() {
    return chartLoader.item
  }

  function injectChart() {
    var chart = root.chartItem()
    if (!chart) return
    chart.bar = root.bar
    chart.coinId = root.chartCoin
    chart.vs = root.vs
    chart.interval = root.chartTf
    chart.alerts = root.alertsFor(root.chartCoin).filter(function(a) { return a.armed })
    chart.quoteProvider = root.provider
    chart.active = root.opened && root.view === "chart"
  }

  function openChart(id) {
    var target = id && id !== "" ? id : (root.coins.length > 0 ? root.coins[0] : "")
    if (!target) return
    root.closeAlertEditor()
    coinSearch.text = ""
    root.searchQuery = ""
    root.pickerIndex = 0
    root.chartCoin = target
    root.view = "chart"
    root.injectChart()
  }

  function backToList() {
    root.view = "list"
    root.injectChart()
  }

  function chartRefresh() {
    var chart = root.chartItem()
    if (chart && chart.refresh) chart.refresh(false, true)
  }

  function stepChartTf(direction) {
    if (direction === 0) return
    var options = Model.CHART_INTERVALS
    var index = 0
    for (var i = 0; i < options.length; i++) if (options[i].id === root.chartTf) index = i
    var next = Math.max(0, Math.min(options.length - 1, index + direction))
    if (options[next].id !== root.chartTf) root.setChartTf(options[next].id)
  }

  function setChartTf(value) {
    if (hostWidget && hostWidget.setSetting) hostWidget.setSetting("chartTf", Model.normalizedChartInterval(value))
  }

  // ---- price alerts --------------------------------------------------------



  function alertsFor(id) {
    var out = []
    for (var i = 0; i < alerts.length; i++) if (alerts[i].coin === id) out.push(alerts[i])
    return out
  }

  function openAlertEditor(id) {
    if (!id) return
    if (root.view === "chart") root.backToList()
    root.listTab = "alerts"
    root.editingAlertId = ""
    root.alertVs = root.vs
    root.alertDirection = "auto"
    root.alertWasArmed = true
    root.alertCoin = id
    alertField.text = ""
    root.alertTarget = ""
    Qt.callLater(function() { alertField.forceActiveFocus() })
  }

  function editAlert(id) {
    var found = root.alerts.filter(function(a) { return a.id === id })[0]
    if (!found) return
    root.openAlertEditor(found.coin)
    root.editingAlertId = found.id
    root.alertVs = found.vs
    root.alertDirection = found.dir
    root.alertWasArmed = found.armed
    alertField.text = I18n.inputNumber(found.price)
  }

  function closeAlertEditor() {
    root.alertCoin = ""
    root.editingAlertId = ""
    root.alertTarget = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    // Hidden items should not keep the key focus, or the panel-wide key
    // catcher stays blocked after the editor goes away.
    if (alertField) alertField.focus = false
  }

  function alertQuote() {
    return root.alertCoin !== "" ? root.quoteFor(root.alertCoin, root.alertVs) : null
  }

  function alertTargetValue() {
    return Model.parseLocalNumber(root.alertTarget)
  }

  function saveAlert() {
    var target = root.alertTargetValue()
    var quote = root.alertQuote()
    if (!isFinite(target) || (!quote && root.alertDirection === "auto")) return
    var current = root.alerts.filter(function(a) { return a.id === root.editingAlertId })[0]
    if (root.editingAlertId && !current) { root.closeAlertEditor(); return }
    var armed = current ? current.armed : true
    var alert = {
      coin: root.alertCoin, dir: root.targetDirection, price: target, vs: root.alertVs,
      armed: armed, paused: !armed, firedAt: 0, firedPrice: 0
    }
    if (!root.alertsReady) return
    var normalized = Model.normalizedAlerts([alert])
    if (!normalized.length) return
    root.alertCommand("upsert", {alert: normalized[0], oldId: root.editingAlertId, expected: current || null})
    root.closeAlertEditor()
  }

  function removeAlert(id) {
    if (root.editingAlertId === id) root.closeAlertEditor()
    root.alertCommand("remove", {id: id})
  }

  function rearmAlert(id) {
    root.alertCommand("toggle", {id: id})
  }

  // One-shot trigger check, run after every successful quote refresh. Fired
  // alerts stay listed (disarmed) until the user re-arms them.
  function checkAlerts() {
    if (!root.alertsReady || root.restoredPrices || root.alerts.length === 0 || alertWriter.running) return
    var events = []
    for (var i = 0; i < root.alerts.length; i++) {
      var alert = root.alerts[i]
      if (!alert.armed) continue
      var quote = root.quoteFor(alert.coin, alert.vs)
      if (!quote || (quote.fxAt && (!root.fxFresh || Date.now() - quote.fxAt > 150000)) || !Model.alertCrossed(alert, quote.price)) continue
      events.push({id: alert.id, expected: alert, price: quote.price, message: Model.alertMessage(alert, quote.price)})
    }
    if (events.length) root.alertCommand("fire", {events: events})
  }

  function notifyAlert(alert, price) {
    if (!root.bar || typeof root.bar.run !== "function") return
    var message = Model.alertMessage(alert, price)
    root.bar.run("omarchy-notification-send --app-name Crypto -u normal -g "
      + Util.shellQuote(Model.tickerFor(alert.coin))
      + " " + Util.shellQuote(message.title)
      + " " + Util.shellQuote(message.body))
  }

  // Live search: the catalogue answers instantly, then the provider fills in
  // the rest (Binance matches its whole spot symbol list, fetched once and
  // cached; CoinGecko searches per query) so any listed coin can be added.
  function runPickerSearch() {
    var query = root.searchQuery.trim()
    if (query.length < 2) {
      root.remoteResults = []
      root.remoteFailed = false
      root.remoteLoading = false
      return
    }
    if (root.provider === "binance") {
      if (root.binanceLoaded) {
        root.remoteResults = Model.binancePickerResults(root.binanceBases, query, root.coins)
        root.remoteFailed = false
        root.remoteLoading = false
        return
      }
      if (symbolsProc.running) {
        root.remotePending = true
        return
      }
      root.remoteFailed = false
      root.remoteLoading = true
      symbolsProc.command = ["sh", "-c", Model.binanceSymbolsCommand()]
      symbolsProc.running = true
      return
    }
    if (searchProc.running) {
      root.remotePending = true
      return
    }
    root.remoteFailed = false
    root.remoteLoading = true
    searchProc.command = ["curl", "-sS", "--max-time", "8", "-w", "\\n%{http_code}", Model.coingeckoSearchUrl(query)]
    searchProc.running = true
  }

  function refreshFx() {
    if (!root.needsFx || fxProc.running || Date.now() < root.fxRetryAt || (root.fxFresh && Date.now() - root.fxAt < 60000)) return
    root.fxRequestUrl = root.fxUrl
    fxProc.get(root.fxUrl, 60000, 5)
  }
  function rebuildPrices() {
    if (!Object.keys(root.basePrices).length) return
    root.prices = root.needsFx ? Model.convertQuotes(root.basePrices, root.fxRates, root.currencies, root.fxAt) : root.basePrices
    root.fetchedAt = root.needsFx && root.fxAt > 0 ? Math.min(root.baseFetchedAt, root.fxAt) : root.baseFetchedAt
    Cache.put("quotes", root.priceCacheKey, { prices: root.prices, at: root.fetchedAt })
  }
  Request {
    id: fxProc
    onCompleted: function(status, body, at) {
      if (status !== 200) {
        root.fxError = I18n.tr("câmbio indisponível")
        root.fxFresh = false
        root.fxRetryAt = Date.now() + 120000
        return
      }
      try {
        var data = JSON.parse(body).tether
        var stamp = Number(data && data.last_updated_at) * 1000
        var rates = Model.parseCoingecko(body, Model.CURRENCIES).tether
        if (!rates || !isFinite(stamp) || stamp <= 0 || stamp > Date.now() + 60000) throw new Error("invalid rates")
        root.fxRates = rates; root.fxAt = Math.min(at, stamp)
        root.fxFresh = Date.now() - root.fxAt < 150000
        root.fxError = root.fxFresh ? "" : I18n.tr("câmbio desatualizado")
        Cache.put("quotes", root.fxUrl, { prices: {tether: rates}, at: root.fxAt })
        root.rebuildPrices()
        if (!root.restoredPrices && Date.now() - root.baseFetchedAt < 150000) root.checkAlerts()
      } catch(e) { root.fxError = I18n.tr("câmbio indisponível"); root.fxFresh = false; root.fxRetryAt = Date.now() + 120000 }
    }
  }

  function acceptPrices(status, body, at) {
    if (status === 429 || status === 418) {
      root.beginCooldown()
      return
    }
    if (status !== 200 || !body) {
      // No answer at all (timeout, dead connection) is a connection problem,
      // not an API error; handleFailure flags it as such.
      root.apiError = status === 0 ? "" : Model.apiError(root.provider, status, body)
      root.cycleParsed = false
      if (root.provider === "binance" && Model.isUnknownSymbol(status, body)) root.probePairs()
      return
    }

    try {
      var parsed = Model.parseQuotes(root.provider, body, root.coins, root.fetchCurrencies)
      if (Object.keys(parsed).length === 0) return
      root.missingCoins = root.coins.filter(function(id) { return !parsed[id] })
      root.basePrices = parsed
      root.baseFetchedAt = at
      root.restoredPrices = false
      root.rebuildPrices()
      root.fetchFailed = false
      root.rateLimited = false
      root.apiError = ""
      root.cooldownUntil = 0
      root.retries = 0
      root.cycleParsed = true
      root.checkAlerts()
      Qt.callLater(root.warmChart)
    } catch (e) {
      root.cycleParsed = false
    }
  }
  // Asks for each pair on its own to find the ones Binance does not know,
  // then retries the batch without them.
  function probePairs() {
    if (root.probing) return
    var pairs = Model.binancePairs(root.coins, root.fetchCurrencies, root.badPairs)
    if (!pairs.length) return
    root.probing = true
    probeDeadline.restart()
    var serial = ++root.probeSerial, pending = pairs.length, unknown = []
    pairs.forEach(function(pair) {
      Http.request(Model.binanceTickerUrl(pair), 60000, 4, function(response) {
        if (serial !== root.probeSerial) return
        if (Model.isUnknownSymbol(response.status, response.body)) unknown.push(pair)
        if (--pending > 0) return
        root.probing = false
        probeDeadline.stop()
        if (!unknown.length) return
        console.warn("crypto: Binance does not list " + unknown.join(", ") + "; leaving them out")
        root.badPairs = root.badPairs.concat(unknown)
        Qt.callLater(root.cycleRefresh)
      })
    })
  }
  property int probeSerial: 0
  Timer { id: probeDeadline; interval: 15000; onTriggered: { root.probeSerial++; root.probing = false } }

  Request {
    id: priceProc
    onCompleted: function(status, body, at) {
      if (root.lastUrl !== root.quoteUrl) {
        root.loading = false; root.refreshPending = false
        Qt.callLater(root.refresh)
        return
      }
      root.acceptPrices(status, body, at)
      root.loading = false
      if (status !== 200 || !root.cycleParsed) root.handleFailure()
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  // Trading USDT base symbols from Binance, trimmed by jq and cached for the
  // session, so later searches match locally.
  Process {
    id: symbolsProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var bases = Model.binanceBaseSymbols(text)
          if (bases.length === 0) {
            root.remoteFailed = true
            return
          }
          root.binanceBases = bases
          root.binanceLoaded = true
        } catch (e) {
          root.remoteFailed = true
        }
      }
    }

    onExited: function(exitCode) {
      root.remoteLoading = false
      if (exitCode !== 0 || !root.binanceLoaded) root.remoteFailed = true
      else root.remoteResults = Model.binancePickerResults(root.binanceBases, root.searchQuery, root.coins)
      if (root.remotePending) {
        root.remotePending = false
        Qt.callLater(root.runPickerSearch)
      }
    }
  }

  Process {
    id: searchProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var newline = raw.lastIndexOf("\n")
        if (newline < 0) return
        var status = raw.slice(newline + 1).trim()
        var body = raw.slice(0, newline).trim()
        if (status !== "200" || !body) {
          root.remoteResults = []
          root.remoteFailed = true
          return
        }
        try {
          root.remoteResults = Model.coingeckoPickerResults(body, root.coins)
          root.remoteFailed = false
        } catch (e) {
          root.remoteResults = []
          root.remoteFailed = true
        }
      }
    }

    onExited: function(exitCode) {
      root.remoteLoading = false
      if (exitCode !== 0) root.remoteFailed = true
      if (root.remotePending) {
        root.remotePending = false
        Qt.callLater(root.runPickerSearch)
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 2500
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshTimer
    // Armed alerts need a tighter loop so a crossing is caught quickly, and a
    // panel being watched deserves fresher numbers; the pill alone is fine at
    // one minute.
    interval: root.armedAlertCount > 0 || root.opened ? 30000 : 60000
    repeat: true
    running: true
    onTriggered: root.cycleRefresh()
  }

  Timer {
    id: configDebounce
    interval: 250
    onTriggered: {
      root.rebuildPrices()
      root.refreshFx()
      root.refreshPrimarySpark()
      if (root.quoteUrl !== root.lastUrl) root.cycleRefresh()
    }
  }

  Timer {
    id: searchDebounce
    interval: 350
    onTriggered: root.runPickerSearch()
  }

  Timer {
    id: rotateTimer
    repeat: true
    interval: Math.max(1, root.rotateSeconds) * 1000
    running: root.cycling
    onTriggered: root.rotateIndex = (root.rotateIndex + 1) % root.coins.length
  }

  Timer {
    id: ageTimer
    interval: root.opened ? 1000 : 15000
    repeat: true
    running: true
    onTriggered: root.clockTick += 1
  }

  onRotateSecondsChanged: if (root.rotateSeconds > 0) root.rotateMemory = root.rotateSeconds
  onSearchQueryChanged: if (root.primed) searchDebounce.restart()
  onCoinsChanged: if (root.primed) configDebounce.restart()
  onVsChanged: if (root.primed) configDebounce.restart()
  onVs2Changed: if (root.primed) configDebounce.restart()
  onProviderChanged: if (root.primed) {
    root.prices = ({}); root.basePrices = ({}); root.baseFetchedAt = 0; root.fetchedAt = 0; root.restoredPrices = false
    root.missingCoins = []
    root.restorePrices(); configDebounce.restart()
  }
  // A new armed alert in a currency that was not being fetched must trigger a
  // request; configDebounce compares URLs and catches the change.
  onAlertsChanged: {
    if (!root.alerts.some(function(a) { return a.id === root.selectedAlert })) root.selectedAlert = root.alerts.length ? root.alerts[0].id : ""
    var edited = root.alerts.filter(function(a) { return a.id === root.editingAlertId })[0]
    if (edited) root.alertWasArmed = edited.armed
    root.injectChart(); if (root.primed) configDebounce.restart()
  }
  onChartTfChanged: root.injectChart()
  onChartCoinChanged: root.injectChart()
  onViewChanged: {
    root.injectChart()
    if (root.opened) sectionStagger.play()
  }
  onListTabChanged: if (root.opened) sectionStagger.play()
  onOpenedChanged: {
    root.injectChart()
    if (root.opened) {
      sectionStagger.play()
      rowStagger.play()
    }
    if (root.opened) Qt.callLater(root.warmChart)
    else diskCache.flush()
  }

  // The host injects this widget's settings right after the panel loads; a
  // short defer lets that land first so the boot costs a single request with
  // the real coin list instead of a default-BTC fetch plus a follow-up.
  Timer {
    id: bootTimer
    interval: 120
    onTriggered: {
      root.primed = true
      root.restorePrices()
      root.cycleRefresh()
      root.refreshPrimarySpark()
    }
  }

  function restorePrices() {
    var fx = Cache.get("quotes", root.fxUrl)
    if (fx && fx.at > root.fxAt) { root.fxRates = fx.prices.tether || ({}); root.fxAt = fx.at; root.fxFresh = false }
    var saved = Cache.get("quotes", root.priceCacheKey)
    if (saved && saved.at > root.fetchedAt) {
      root.prices = saved.prices; root.fetchedAt = saved.at; root.restoredPrices = true
    }
    root.sparkCache = Cache.entries("sparks")
    var chart = root.chartItem()
    if (chart && !chart.candles.length) Qt.callLater(chart.invalidateSeries)
  }
  PersistentCache {
    id: diskCache
    onReady: root.restorePrices()
  }
  Component.onCompleted: { root.syncCoinRows(); bootTimer.start() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // The chart needs room for seven timeframe chips and the price scale.
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: (coinSearch.visible && coinSearch.activeFocus) || (alertField.visible && alertField.activeFocus)

      // Esc unwinds one level at a time: chart -> list, editor -> list, panel -> closed.
      onCloseRequested: {
        if (root.view === "chart") root.backToList()
        else if (root.alertCoin !== "") root.closeAlertEditor()
        else root.close()
      }
      onTabRequested: function(direction) { root.listTab = root.listTab === "coins" ? "alerts" : "coins"; scroll.contentY = 0; root.closeAlertEditor() }
      onReturnRequested: if (root.view === "chart") root.chartRefresh()
      onActivateRequested: root.activateSelection()
      onMoveRequested: function(dx, dy) { if (root.view === "chart") root.stepChartTf(dx); else root.moveSelection(dy) }
      onTextKey: function(t) {
        if (root.view === "chart") {
          if (t === "r") root.chartRefresh()
          return
        }
        if (t === "r") root.cycleRefresh()
        else if (t === "c") root.setCycling(!root.cycling)
        else if (t === "u") root.toggleCurrency()
        else if (t === "/" || t === "a") root.focusSearch()
        else if (t === "g") root.openChart(root.actionCoin)
        else if (t === "n") root.openAlertEditor(root.actionCoin)
        else if (t === "p") { if (root.listTab === "alerts") root.rearmAlert(root.selectedAlert); else root.togglePin(root.actionCoin) }
        else if (t === "e" && root.listTab === "alerts") root.editAlert(root.selectedAlert)
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroll.width
          spacing: Style.space(12)

          FxStagger { id: sectionStagger; container: column; step: 45 }

          Item {
            width: parent.width
            height: Style.space(24)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Rectangle {
                id: backButton
                visible: root.view === "chart"
                width: Style.space(20)
                height: Style.space(20)
                radius: Math.min(4, Style.cornerRadius)
                color: backArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent
                  text: "‹"
                  color: backArea.containsMouse ? Style.hoverStateColor(root.bar.foreground, Color.accent) : Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                }

                MouseArea {
                  id: backArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.backToList()
                }

                PanelToolTip {
                  visible: backArea.containsMouse
                  text: I18n.tr("voltar para a lista (esc)")
                  fontFamily: root.bar.fontFamily
                }
              }

              Text {
                text: root.view === "chart" ? Model.tickerFor(root.chartCoin) + " · " + root.chartTf : "CRYPTO"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                visible: root.view !== "chart"
                text: root.vsLabel
                color: Qt.darker(root.bar.foreground, 1.8)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: root.statusText
                width: Math.min(implicitWidth, Style.space(150))
                elide: Text.ElideRight
                color: root.rateLimited || root.fetchFailed ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }

              Rectangle {
                id: refreshButton
                width: Style.space(20)
                height: Style.space(20)
                radius: Math.min(4, Style.cornerRadius)
                color: refreshArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent
                  text: "󰑐"
                  color: refreshArea.containsMouse ? Style.hoverStateColor(root.bar.foreground, Color.accent) : Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body

                  RotationAnimator on rotation {
                    running: root.loading || (root.view === "chart" && root.chartItem() !== null && root.chartItem().loading)
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                  }
                }

                MouseArea {
                  id: refreshArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.view === "chart" ? root.chartRefresh() : root.cycleRefresh()
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          Text {
            visible: root.alertError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.alertError
            wrapMode: Text.Wrap
            color: root.bar ? root.bar.urgent : Color.urgent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          ButtonGroup {
            visible: root.view === "list"
            width: parent.width
            options: [{ value: "coins", label: I18n.tr("Moedas") }, { value: "alerts", label: I18n.tr("Alertas · ") + root.armedAlertCount }]
            value: root.listTab
            foreground: root.bar.foreground
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onChanged: function(next) { root.listTab = next; root.closeAlertEditor(); coinSearch.focus = false }
          }
          ButtonGroup {
            visible: root.view === "list" && root.listTab === "coins"
            options: [{ value: "custom", label: I18n.tr("Minha ordem") }, { value: "change", label: I18n.tr("Variação 24h") }, { value: "name", label: I18n.tr("Nome") }]
            value: root.sortMode
            foreground: root.bar.foreground
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.caption
            onChanged: function(next) { root.sortMode = next }
          }
          Text {
            visible: root.view === "list" && root.listTab === "alerts" && root.alerts.length === 0 && root.alertCoin === ""
            text: I18n.tr("Nenhum alerta. Use o sino de uma moeda para criar.")
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            visible: root.view === "list" && !root.hasData
            textFormat: Text.PlainText
            text: root.fetchFailed || root.apiError !== "" ? I18n.tr("Sem resposta do provedor.") : I18n.tr("Consultando cotações…")
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          Column {
            id: coinList
            visible: root.view === "list" && root.listTab === "coins"
            width: parent.width
            spacing: Style.space(6)

            FxStagger { id: rowStagger; container: coinList; step: 40; distance: 16 }

            Repeater {
              id: coinRepeater
              model: coinRows

              Item {
                id: coinRow
                required property string coinId
                readonly property string modelData: coinId
                required property int index
                readonly property var quote: root.quoteFor(modelData, root.vs)
                readonly property var quote2: root.vs2 !== "" ? root.quoteFor(modelData, root.vs2) : null
                readonly property real change: quote && quote.change !== null ? quote.change : 0
                readonly property bool pinned: root.pinnedId === modelData
                readonly property bool shown: root.primaryId === modelData
                readonly property color changeColor: quote && quote.change !== null && quote.change < 0
                  ? root.bar.urgent
                  : Color.flatColor(Color.pick("crypto.gain", hue.green), hue.green)
                readonly property bool hasAlerts: root.alertsFor(modelData).length > 0

                width: parent.width
                readonly property bool missing: root.missingCoins.indexOf(modelData) >= 0
                height: Math.max(Style.space(62), coinLeft.height + Style.space(12), coinRight.height + Style.space(12))

                // Row-wide click: left opens the candle chart, right the alert
                // editor. The pin/bell/remove areas are siblings on top and
                // swallow their own clicks before they reach this one.
                MouseArea {
                  id: rowClick
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    root.selectedCoin = coinRow.modelData
                    if (mouse.button === Qt.RightButton) root.openAlertEditor(coinRow.modelData)
                    else root.openChart(coinRow.modelData)
                  }
                }

                Rectangle {
                  anchors.fill: parent
                  anchors.leftMargin: -Style.space(6)
                  anchors.rightMargin: -Style.space(6)
                  radius: Math.min(4, Style.cornerRadius)
                  color: (coinHover.hovered || root.selectedCoin === coinRow.modelData) ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                }

                Rectangle {
                  id: pinButton
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: Math.min(4, Style.cornerRadius)
                  color: pinArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(14)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.centerIn: parent
                    text: coinRow.shown ? "●" : "○"
                    color: coinRow.shown ? Color.accent : Qt.darker(root.bar.foreground, 1.6)
                    opacity: coinRow.shown || pinArea.containsMouse ? 1 : 0.45
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  MouseArea {
                    id: pinArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePin(coinRow.modelData)
                  }

                  PanelToolTip {
                    visible: pinArea.containsMouse
                    text: coinRow.pinned ? I18n.tr("deixar de fixar na barra") : I18n.tr("fixar na barra")
                    fontFamily: root.bar.fontFamily
                  }
                }

                Text {
                  text: "⋮"
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.pixelSize: Style.font.title
                  visible: root.sortMode === "custom"
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    preventStealing: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property real startY: 0
                    onPressed: function(mouse) { startY = mapToItem(coinList, mouse.x, mouse.y).y }
                    onReleased: function(mouse) {
                      var delta = mapToItem(coinList, mouse.x, mouse.y).y - startY
                      root.moveCoin(coinRow.modelData, Math.round(delta / (coinRow.height + coinList.spacing)))
                    }
                  }
                }
                Column {
                  id: coinLeft
                  anchors.left: pinButton.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(60, coinSpark.x - x - Style.space(8))
                  spacing: Style.space(3)
                  Text {
                    text: Model.tickerFor(coinRow.modelData)
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Model.coinName(coinRow.modelData) + (coinRow.missing ? " · " + I18n.tr("sem cotação") : "")
                    color: coinRow.missing ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.nearestAlert(coinRow.modelData).replace(I18n.tr("faltam "), I18n.tr("Alvo a ")).replace(I18n.tr(" para o alvo"), "")
                    visible: text !== ""
                    color: Color.accent
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                Sparkline {
                  id: coinSpark
                  anchors.right: coinRight.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(72)
                  height: Style.space(30)
                  coinId: coinRow.modelData
                  vs: root.vs
                  // Fetch once in the background after boot so the first open
                  // is already populated; continue polling only while visible.
                  active: root.opened && root.view === "list" && root.listTab === "coins"
                  prefetch: root.primed && coinRow.index < 12
                  lineColor: coinRow.changeColor
                  cacheEntry: root.sparkCache[key] || null
                  onCached: function(key, entry) { root.rememberSpark(key, entry) }
                  Text {
                    anchors.centerIn: parent
                    visible: coinSpark.values.length < 2
                    text: "—"
                    color: Qt.darker(root.bar.foreground, 1.8)
                  }
                  HoverHandler { id: sparkHover }
                  PanelToolTip {
                    visible: sparkHover.hovered
                    text: coinSpark.sourceLabel + (coinSpark.error ? " · " + coinSpark.error : "")
                    fontFamily: root.bar.fontFamily
                  }
                }
                PanelToolTip {
                  visible: coinHover.hovered && !sparkHover.hovered && !alertArea.containsMouse && !pinArea.containsMouse
                  text: Model.quoteSource(root.provider, coinRow.modelData, root.vs)
                  fontFamily: root.bar.fontFamily
                }

                Column {
                  id: coinRight
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(20) + (root.coins.length > 1 ? Style.space(22) : 0)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  width: Math.max(Style.space(130), priceText.implicitWidth, price2Text.implicitWidth, changeText.implicitWidth)

                  Text {
                    id: priceText
                    font.bold: true
                    textFormat: Text.PlainText
                    text: coinRow.quote ? Model.quotePrice(coinRow.quote.price, root.provider, root.vs) : "—"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                  }

                  Text {
                    id: price2Text
                    textFormat: Text.PlainText
                    visible: coinRow.quote2 !== null
                    text: coinRow.quote2 ? Model.quotePrice(coinRow.quote2.price, root.provider, root.vs2) : ""
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                  }

                  Text {
                    id: changeText
                    textFormat: Text.PlainText
                    text: coinRow.quote && coinRow.quote.change !== null
                      ? Model.arrow(coinRow.change) + " " + Model.formatChange(coinRow.change) + " · 24h"
                      : "—"
                    color: coinRow.changeColor
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                  }
                }

                HoverHandler {
                  id: coinHover
                  cursorShape: Qt.PointingHandCursor
                }

                Rectangle {
                  id: alertButton
                  visible: coinHover.hovered || coinRow.hasAlerts
                  anchors.right: parent.right
                  anchors.rightMargin: root.coins.length > 1 ? Style.space(22) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: Math.min(4, Style.cornerRadius)
                  color: alertArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: ""
                    color: coinRow.hasAlerts ? Color.accent : Qt.darker(root.bar.foreground, 1.4)
                    opacity: coinRow.hasAlerts || alertArea.containsMouse ? 1 : 0.6
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  MouseArea {
                    id: alertArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAlertEditor(coinRow.modelData)
                  }

                  PanelToolTip {
                    visible: alertArea.containsMouse
                    text: I18n.tr("criar alerta de preço")
                    fontFamily: root.bar.fontFamily
                  }
                }

                Rectangle {
                  id: removeButton
                  visible: coinHover.hovered && root.coins.length > 1
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: Math.min(4, Style.cornerRadius)
                  color: removeArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  MouseArea {
                    id: removeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removeCoin(coinRow.modelData)
                  }
                }
              }
            }
          }

          // Inline alert editor: target price in the main currency, direction
          // inferred from the target versus the current quote.
          Column {
            visible: root.view === "list" && root.alertCoin !== ""
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: Math.max(alertTitle.implicitHeight, alertPriceNow.implicitHeight)

              Row {
                id: alertTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  text: ""
                  color: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: (root.editingAlertId ? I18n.tr("Editar — ") : I18n.tr("Alerta — ")) + Model.coinName(root.alertCoin)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Text {
                id: alertPriceNow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.alertQuote() ? I18n.tr("agora ") + Model.quotePrice(root.alertQuote().price, root.provider, root.alertVs) : I18n.tr("sem cotação")
                color: Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            ButtonGroup {
              options: [{ value: "-10", label: "−10%" }, { value: "-5", label: "−5%" }, { value: "5", label: "+5%" }, { value: "10", label: "+10%" }]
              foreground: root.bar.foreground
              accent: Color.accent
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.caption
              onChanged: function(next) { root.presetAlert(Number(next)) }
            }
            ButtonGroup {
              options: [{value: "above", label: I18n.tr("▲ Acima")}, {value: "below", label: I18n.tr("▼ Abaixo")}]
              value: root.targetDirection
              foreground: root.bar.foreground; accent: Color.accent
              fontFamily: root.bar.fontFamily; fontSize: Style.font.caption
              onChanged: function(next) { root.alertDirection = next }
            }
            Text {
              text: I18n.tr("Moeda: ") + Model.quoteCurrency(root.provider, root.alertVs) + (root.alertWasArmed ? I18n.tr(" · ativo após salvar") : I18n.tr(" · permanece pausado"))
              color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
            }
            TextField {
              id: alertField
              width: parent.width
              placeholderText: I18n.tr("digite o preço alvo") + " (" + Model.formatNumber(350000, 2) + ")"
              foreground: root.bar.foreground
              accent: Color.accent

              onTextChanged: root.alertTarget = text
              onAccepted: root.saveAlert()

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.closeAlertEditor()
                  event.accepted = true
                }
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: {
                var quote = root.alertQuote()
                var target = root.alertTargetValue()
                if (!quote && root.alertDirection === "auto") return I18n.tr("cotação indisponível no momento")
                if (!isFinite(target)) return I18n.tr("digite o preço alvo")
                if (root.targetDirection === "above")
                  return I18n.tr("▲ avisa quando o preço subir para ") + Model.quotePrice(target, root.provider, root.alertVs)
                return I18n.tr("▼ avisa quando o preço cair para ") + Model.quotePrice(target, root.provider, root.alertVs)
              }
              color: {
                var target = root.alertTargetValue()
                if (!root.alertQuote() || !isFinite(target)) return Qt.darker(root.bar.foreground, 1.6)
                return root.targetDirection === "above"
                  ? Color.flatColor(Color.pick("crypto.gain", hue.green), hue.green)
                  : root.bar.urgent
              }
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)

              Button {
                text: I18n.tr("Cancelar")
                foreground: root.bar.foreground
                background: "transparent"
                accent: Color.accent
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.closeAlertEditor()
              }

              Button {
                text: root.editingAlertId ? I18n.tr("Salvar alterações") : I18n.tr("Criar alerta")
                selected: enabled
                enabled: (root.alertQuote() !== null || root.alertDirection !== "auto") && isFinite(root.alertTargetValue())
                foreground: root.bar.foreground
                background: "transparent"
                accent: Color.accent
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.saveAlert()
              }
            }
          }

          // Armed and fired alerts. Fired ones stay visible so they can be
          // acknowledged or armed again.
          Column {
            visible: root.view === "list" && root.listTab === "alerts" && root.alerts.length > 0
            width: parent.width
            spacing: Style.space(2)

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: I18n.tr("ALERTAS")
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.alerts.length + (root.armedAlertCount > 0 ? " · " + root.armedAlertCount + I18n.tr(" ativo") : "")
                color: Qt.darker(root.bar.foreground, 1.8)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Repeater {
              id: alertRepeater
              model: root.alerts

              Item {
                id: alertRow
                required property var modelData
                readonly property var quoteNow: root.quoteFor(modelData.coin, modelData.vs)
                readonly property bool fired: !modelData.armed && !modelData.paused

                width: parent.width
                height: alertLine.height + Style.space(8)

                Rectangle {
                  anchors.fill: parent
                  anchors.leftMargin: -Style.space(6)
                  anchors.rightMargin: -Style.space(6)
                  radius: Math.min(4, Style.cornerRadius)
                  color: (alertHover.hovered || root.selectedAlert === alertRow.modelData.id) ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                }

                Column {
                  id: alertLine
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(80)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Row {
                    spacing: Style.space(6)

                    Text {
                      text: Model.tickerFor(alertRow.modelData.coin)
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: Model.alertGoalText(alertRow.modelData).replace(Model.currencySymbol(alertRow.modelData.vs), Model.quoteCurrency(root.provider, alertRow.modelData.vs))
                      color: alertRow.modelData.dir === "below" ? root.bar.urgent
                        : Color.flatColor(Color.pick("crypto.gain", hue.green), hue.green)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: {
                      var tick = root.clockTick
                      var alert = alertRow.modelData
                      if (alert.paused) return I18n.tr("pausado")
                      if (alert.armed) {
                        return alertRow.quoteNow
                          ? Model.alertDistance(alert, alertRow.quoteNow.price) + I18n.tr(" · agora ") + Model.quotePrice(alertRow.quoteNow.price, root.provider, alert.vs)
                          : I18n.tr("aguardando")
                      }
                      var when = alert.firedAt > 0 ? I18n.tr("há ") + Model.formatAge((Date.now() - alert.firedAt) / 1000) : ""
                      var at = alert.firedPrice > 0 ? I18n.tr(" em ") + Model.formatPrice(alert.firedPrice, alert.vs) : ""
                      return I18n.tr("disparou ") + when + at
                    }
                    color: alertRow.fired ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                HoverHandler {
                  id: alertHover
                  cursorShape: Qt.PointingHandCursor
                }

                Row {
                  visible: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Rectangle {
                    width: Style.space(18)
                    height: Style.space(18)
                    radius: Math.min(4, Style.cornerRadius)
                    color: rearmArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                    Text {
                      anchors.centerIn: parent
                      text: alertRow.modelData.armed ? "Ⅱ" : "▶"
                      color: rearmArea.containsMouse ? Style.hoverStateColor(root.bar.foreground, Color.accent) : Qt.darker(root.bar.foreground, 1.4)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    MouseArea {
                      id: rearmArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.rearmAlert(alertRow.modelData.id)
                    }

                    PanelToolTip {
                      visible: rearmArea.containsMouse
                      text: alertRow.modelData.armed ? I18n.tr("pausar alerta") : (alertRow.fired ? I18n.tr("armar de novo") : I18n.tr("retomar alerta"))
                      fontFamily: root.bar.fontFamily
                    }
                  }

                  Rectangle {
                    width: Style.space(22); height: Style.space(22)
                    radius: Math.min(4, Style.cornerRadius)
                    color: editArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                    Text { anchors.centerIn: parent; text: "✎"; color: root.bar.foreground; font.family: root.bar.fontFamily }
                    MouseArea { id: editArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.editAlert(alertRow.modelData.id) }
                    PanelToolTip { visible: editArea.containsMouse; text: I18n.tr("editar alerta"); fontFamily: root.bar.fontFamily }
                  }

                  Rectangle {
                    width: Style.space(18)
                    height: Style.space(18)
                    radius: Math.min(4, Style.cornerRadius)
                    color: alertRemoveArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                    Text {
                      anchors.centerIn: parent
                      text: "✕"
                      color: Qt.darker(root.bar.foreground, 1.3)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    MouseArea {
                      id: alertRemoveArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.removeAlert(alertRow.modelData.id)
                    }

                    PanelToolTip {
                      visible: alertRemoveArea.containsMouse
                      text: I18n.tr("remover alerta")
                      fontFamily: root.bar.fontFamily
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.view === "list" && root.listTab === "alerts" && root.armedAlertCount > 0
            width: parent.width
            textFormat: Text.PlainText
            text: I18n.tr("Alertas conferidos a cada 30 s; um pico entre duas consultas pode passar despercebido.")
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            visible: root.view === "list" && root.listTab === "coins"
            text: root.settingsExpanded ? I18n.tr("Fechar ajustes e busca ▴") : I18n.tr("+ Moedas e ajustes ▾")
            foreground: root.bar.foreground
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: { root.settingsExpanded = !root.settingsExpanded; coinSearch.focus = false; keyCatcher.forceActiveFocus() }
          }
          Column {
            visible: root.view === "list" && root.listTab === "coins" && root.settingsExpanded
            width: parent.width
            spacing: Style.space(4)

            TextField {
              id: coinSearch
              width: parent.width
              placeholderText: I18n.tr("adicionar moeda (ex: dash, aero, solana)")
              foreground: root.bar.foreground
              accent: Color.accent

              onTextChanged: {
                root.searchQuery = text
                root.pickerIndex = 0
              }

              onAccepted: root.commitPicker()

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                  root.pickerIndex = Math.min(root.pickerIndex + 1, Math.max(0, root.pickerResults.length - 1))
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  root.pickerIndex = Math.max(0, root.pickerIndex - 1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  text = ""
                  root.searchQuery = ""
                  focus = false
                  Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                  event.accepted = true
                }
              }
            }

            Text {
              visible: root.searchQuery !== "" && root.pickerResults.length === 0
              textFormat: Text.PlainText
              text: root.remoteLoading
                ? I18n.tr("buscando…")
                : (root.remoteFailed ? I18n.tr("nenhuma moeda encontrada · busca online indisponível") : I18n.tr("nenhuma moeda encontrada"))
              color: Qt.darker(root.bar.foreground, 1.8)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }

            Repeater {
              model: root.searchQuery !== "" ? root.pickerResults : []

              Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: pickerRow.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: index === root.pickerIndex
                  ? Style.hoverFillFor(root.bar.foreground, Color.accent)
                  : (pickerHover.hovered ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")

                Row {
                  id: pickerRow
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Text {
                    text: modelData.glyph !== "" ? modelData.glyph : modelData.symbol
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    width: Style.space(20)
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.symbol
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.added ? "✓" : "+"
                  color: modelData.added ? Color.accent : Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                HoverHandler {
                  id: pickerHover
                  cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                  onTapped: root.toggleCoin(modelData.id)
                }
              }
            }
          }

          Button {
            visible: root.view === "list" && root.listTab === "coins" && root.settingsExpanded
            text: I18n.tr("Moedas de cotação") + " · " + root.vsLabel + (root.currenciesExpanded ? " ▴" : " ▾")
            foreground: root.bar.foreground; accent: Color.accent
            fontFamily: root.bar.fontFamily; fontSize: Style.font.caption
            onClicked: root.currenciesExpanded = !root.currenciesExpanded
          }
          Column {
            visible: root.view === "list" && root.listTab === "coins" && root.settingsExpanded && root.currenciesExpanded
            width: parent.width
            spacing: Style.space(6)
            Text { text: I18n.tr("Cotação principal"); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
            Flow {
              width: parent.width; spacing: Style.space(4)
              Repeater {
                model: Model.CURRENCIES
                Button {
                  required property string modelData
                  text: modelData === "usd" && root.provider === "binance" ? "USDT" : modelData.toUpperCase()
                  selected: root.vs === modelData
                  foreground: root.bar.foreground; accent: Color.accent; fontFamily: root.bar.fontFamily; fontSize: Style.font.caption
                  onClicked: root.setCurrency(modelData)
                }
              }
            }
            Text { text: I18n.tr("Cotação secundária"); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
            Flow {
              width: parent.width; spacing: Style.space(4)
              Repeater {
                model: [""].concat(Model.CURRENCIES)
                Button {
                  required property string modelData
                  text: modelData === "" ? I18n.tr("Nenhuma") : (modelData === "usd" && root.provider === "binance" ? "USDT" : modelData.toUpperCase())
                  selected: root.vs2 === modelData
                  enabled: modelData !== root.vs
                  foreground: root.bar.foreground; accent: Color.accent; fontFamily: root.bar.fontFamily; fontSize: Style.font.caption
                  onClicked: if (root.hostWidget) root.hostWidget.setSetting("vs2", modelData)
                }
              }
            }
            Text {
              visible: root.needsFx
              width: parent.width; wrapMode: Text.WordWrap
              text: I18n.tr("Conversão via USDT/CoinGecko. O gráfico mantém o par original e a moeda indicada.")
              color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
            }
            Row {
              spacing: Style.space(8)
              Text { text: I18n.tr("Alternar moedas na barra"); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
              ToggleSwitch {
                checked: root.cycling; busy: root.coins.length < 2
                foreground: root.bar.foreground; accent: Color.accent
                onToggled: root.setCycling(!root.cycling)
              }
            }
          }

          Loader {
            id: chartLoader
            active: true
            visible: root.view === "chart"
            width: parent.width
            source: Qt.resolvedUrl("Chart.qml")

            onLoaded: {
              root.injectChart()
              item.backRequested.connect(root.backToList)
              item.intervalRequested.connect(function(id) { root.setChartTf(id) })
            }
          }

          Text {
            visible: root.view === "list"
            text: root.listTab === "coins" ? I18n.tr("↑↓ escolher · Enter gráfico · N alerta · P fixar · Tab alertas") : I18n.tr("↑↓ escolher · Enter editar · P pausar/retomar · Tab moedas")
            width: parent.width; wrapMode: Text.WordWrap
            color: Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
          }
          Text {
            visible: root.view !== "chart"
            textFormat: Text.PlainText
            text: root.statusDetail
            width: parent.width
            elide: Text.ElideRight
            color: root.rateLimited || root.fetchFailed || root.apiError !== "" ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.8)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
