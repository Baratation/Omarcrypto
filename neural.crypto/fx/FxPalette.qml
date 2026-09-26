import QtQuick
import Quickshell.Io
import qs.Commons

// The theme's full palette, not just the four shell roles. Color only exposes
// foreground/background/accent/urgent/muted; the widgets want the named hues
// too (green for "fine", yellow/orange on the way up, red at the top), so this
// reads them straight from the current theme's colors.toml and re-reads on
// every theme switch. Falls back to the ANSI slots (color1..color6) for themes
// that only ship those, and to Tokyo Night hues when neither exists.
Item {
  id: root
  visible: false

  property color red: Color.urgent
  property color green: "#9ece6a"
  property color yellow: "#e0af68"
  property color orange: "#ff9e64"
  property color cyan: "#7dcfff"
  property color blue: Color.accent
  property color magenta: "#bb9af7"

  readonly property color accent: Color.accent
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background

  function clamp01(v) { return Math.max(0, Math.min(1, Number(v) || 0)) }

  function mix(a, b, t) {
    var k = clamp01(t)
    return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k,
                   a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
  }

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // Continuous "how worried should I be" ramp: 0 green, .55 yellow, .8
  // orange, 1 red. Callers map their own thresholds onto 0..1.
  function heat(t) {
    var k = clamp01(t)
    if (k < 0.55) return mix(green, yellow, k / 0.55)
    if (k < 0.8) return mix(yellow, orange, (k - 0.55) / 0.25)
    return mix(orange, red, (k - 0.8) / 0.2)
  }

  // Maps a value to 0..1 where `calm` and below read 0 and `crit` reads 1.
  function band(value, calm, crit) {
    var v = Number(value)
    if (!isFinite(v)) return 0
    return clamp01((v - calm) / Math.max(0.0001, crit - calm))
  }

  function load(raw) {
    var named = {}
    var ansi = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!m) continue
      if (/^color\d+$/.test(m[1])) ansi[m[1]] = m[2]
      else named[m[1]] = m[2]
    }
    function pick(name, slot, fallback) {
      return named[name] || ansi[slot] || fallback
    }
    red = pick("red", "color1", Color.urgent)
    green = pick("green", "color2", "#9ece6a")
    yellow = pick("yellow", "color3", "#e0af68")
    blue = pick("blue", "color4", Color.accent)
    magenta = pick("magenta", "color5", "#bb9af7")
    cyan = pick("cyan", "color6", "#7dcfff")
    orange = named["orange"] || named["bright_yellow"] || mix(yellow, red, 0.45)
  }

  FileView {
    id: file
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.load(text())
  }

  // Theme switches rewrite the directory rather than the file in place, which
  // inotify can miss; the accent changing is the reliable signal.
  Connections {
    target: Color
    function onAccentChanged() { file.reload() }
    function onUrgentChanged() { file.reload() }
  }
}
