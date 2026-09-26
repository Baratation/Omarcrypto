import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "fx"

// Crypto price pill. The popup (Panel.qml) owns polling, retries and the
// coin list; this widget only mirrors what the panel publishes, forwards
// clicks to it and exposes the IPC surface for the shell.
BarWidget {
  id: root
  moduleName: "neural.crypto"

  readonly property var panel: panelLoader.item
  readonly property bool hasQuote: !!panel && panel.hasData
  readonly property real change: hasQuote ? panel.primaryChange : 0

  // Themes may pin crypto.gain in shell.toml; otherwise a muted green that
  // reads well on the dark bar palettes.
  readonly property color gainColor: Color.flatColor(Color.pick("crypto.gain", hue.green), hue.green)

  FxPalette { id: hue }

  readonly property bool fancy: !(root.bar && root.bar.vertical) && hasQuote && !!panel.primary
  readonly property color ink: bar ? bar.barForeground : Color.foreground
  readonly property string arrowText: hasQuote ? Model.arrow(change) : ""
  // The primary coin's last 24 h, kept fresh by the panel.
  readonly property var spark: panel && panel.primarySpark ? panel.primarySpark : []

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

  function retireLegacyAlerts() {
    if (!root.settings || root.settings.alerts === undefined) return
    var entry = Object.assign({}, root.settings, {id: root.moduleName})
    delete entry.alerts
    root.settings = entry
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, entry)
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
    target: "neural.crypto"

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
    labelVisible: !root.fancy
    active: true
    useActiveColor: true
    activeColor: root.trendColor
    horizontalMargin: 8.5
    fixedWidth: root.bar && root.bar.vertical ? -1
      : Math.max(Style.space(80), (root.fancy ? ticker.implicitWidth : labelMetrics.width) + Style.space(17))
    TextMetrics {
      id: labelMetrics
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      text: root.panel ? root.panel.label : ""
    }
    tooltipText: root.panel ? root.panel.tooltip : ""

    onPressed: function(b) {
      pill.bump()
      if (b === Qt.RightButton) root.notify()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    FxPill {
      id: pill
      hovered: button.tooltipHovered || root.opened
      alert: root.panel ? root.panel.stale : false
      alertColor: root.bar ? root.bar.urgent : Color.urgent
      tint: root.trendColor
      restAlpha: 0.06
    }

    FxSparkline {
      visible: root.fancy && root.spark.length > 1
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(5)
      anchors.rightMargin: Style.space(5)
      anchors.bottomMargin: Style.space(3)
      height: parent.height * 0.6
      values: root.spark
      color: root.trendColor
      fillAlpha: 0.2
      lineWidth: 1
      glow: 3
      glide: false
      showHead: false
      opacity: button.tooltipHovered ? 0.85 : 0.45
      Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Row {
      id: ticker
      visible: root.fancy
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        visible: root.panel ? root.panel.stale : false
        anchors.verticalCenter: parent.verticalCenter
        text: "⚠"
        color: root.bar ? root.bar.urgent : Color.urgent
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      Text {
        id: symbol
        anchors.verticalCenter: parent.verticalCenter
        text: root.panel && root.panel.primaryId ? Model.tickerFor(root.panel.primaryId) : ""
        color: hue.mix(root.ink, root.trendColor, 0.35)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true
        renderType: Text.NativeRendering

        // A new coin rotating in slides up into place.
        onTextChanged: swap.restart()
        transform: Translate { id: swapShift }
        ParallelAnimation {
          id: swap
          NumberAnimation { target: swapShift; property: "y"; from: 8; to: 0; duration: 420; easing.type: Easing.OutBack }
          NumberAnimation { target: ticker; property: "opacity"; from: 0.2; to: 1; duration: 320 }
        }
      }

      FxNumber {
        anchors.verticalCenter: parent.verticalCenter
        value: root.panel && root.panel.primary ? root.panel.primary.price : NaN
        formatter: Model.formatCompact
        snapRatio: 0.2
        baseColor: root.trendColor
        upColor: hue.mix(root.gainColor, "#ffffff", 0.35)
        downColor: hue.mix(root.bar ? root.bar.urgent : Color.urgent, "#ffffff", 0.3)
        flashOnChange: true
        // Only moves of 0.1% or more are worth a flash or a roll.
        flashThreshold: Math.abs(value) * 0.001
        rollThreshold: Math.abs(value) * 0.001
        duration: 600
        font.family: button.fontFamily
        font.pixelSize: button.fontSize

        Behavior on baseColor { ColorAnimation { duration: 500 } }
      }

      Text {
        id: arrowGlyph
        visible: root.arrowText !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.arrowText
        color: root.trendColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize - 2
        transform: Translate { id: bob }

        // The arrow nudges in its own direction when a new quote lands.
        Connections {
          target: root.panel
          function onPricesChanged() { if (arrowGlyph.visible) nudge.restart() }
        }

        SequentialAnimation {
          id: nudge
          NumberAnimation { target: bob; property: "y"; to: root.change < 0 ? 2.5 : -2.5; duration: 180; easing.type: Easing.OutQuad }
          NumberAnimation { target: bob; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBounce }
        }
      }
    }
  }
}
