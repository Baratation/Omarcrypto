import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// CoinGecko price pill. The popup (Panel.qml) owns polling, retries and the
// coin list; this widget only mirrors what the panel publishes, forwards
// clicks to it and exposes the IPC surface for the shell.
BarWidget {
  id: root
  moduleName: "rafa.crypto"

  readonly property var panel: panelLoader.item
  readonly property bool hasQuote: !!panel && panel.hasData
  readonly property real change: hasQuote ? panel.primaryChange : 0

  // Themes may pin crypto.gain in shell.toml; otherwise a muted green that
  // reads well on the dark bar palettes.
  readonly property color gainColor: Color.flatColor(Color.pick("crypto.gain", "#8ec07c"), "#8ec07c")

  readonly property color trendColor: panel && panel.stale ? (bar ? bar.urgent : Color.urgent) : !hasQuote
    ? (bar ? bar.barForeground : Color.foreground)
    : (change < 0 ? (bar ? bar.urgent : Color.urgent) : gainColor)

  function refresh() { if (panel && panel.refresh) panel.refresh() }
  function togglePanel() { if (panel && panel.toggle) panel.toggle() }

  readonly property bool opened: panel ? panel.opened === true : false

  function open() { if (panel && panel.open) panel.open() }
  function close() { if (panel && panel.close) panel.close() }

  function notify() {
    if (!bar || !panel) return
    var body = panel.summaryText
    if (!body) return
    bar.run("omarchy-notification-send Crypto " + Util.shellQuote(body))
  }

  // Deferred one tick: right after a shell restart the panel may still be
  // injecting settings, and opening the chart before that lands on the list.
  function chart() {
    if (!panel) return
    panel.open()
    Qt.callLater(function() { if (panel) panel.openChart(panel.primaryId) })
  }

  function alert() {
    if (!panel) return
    panel.open()
    Qt.callLater(function() { if (panel) panel.openAlertEditor(panel.primaryId) })
  }

  // Persist one setting into this widget's inline shell.json entry. Applied
  // locally first so the UI reacts on the click itself; the shell.json write
  // comes back through the bar as the same value.
  function setSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    // The host can inject an empty settings map while the shell config is
    // still loading; ignoring those keeps the panel from reverting to the
    // default coin list mid-session.
    if ("settings" in target && root.settings && Object.keys(root.settings).length > 0)
      target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "rafa.crypto"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
    function toggle(): void { root.broadcast("togglePanel") }
    function chart(): void { root.broadcast("chart") }
    function alert(): void { root.broadcast("alert") }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.panel ? root.panel.label : ""
    active: true
    useActiveColor: true
    activeColor: root.trendColor
    horizontalMargin: 3
    fixedWidth: root.bar && root.bar.vertical ? -1 : Math.max(Style.space(80), labelMetrics.width + Style.space(6))
    TextMetrics {
      id: labelMetrics
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      text: root.panel ? root.panel.label : ""
    }
    tooltipText: root.panel ? root.panel.tooltip : ""

    onPressed: function(b) {
      if (b === Qt.RightButton) root.notify()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
