import QtQuick

// Language for a rafa.* widget. The widget's "language" setting in
// shell.json wins ("pt" or "en"); anything else ("auto", missing) follows
// the system: Portuguese for a pt_* locale, English for every other one.
//
// Strings stay written in the widget's own language (`source`), and tr()
// looks them up in `dict` (source text -> the other language) only when the
// widget should show the other one. A string missing from `dict` shows as
// written, so a forgotten entry degrades to the source language, never to a
// blank.
QtObject {
  id: root

  property string setting: ""
  property string source: "pt"
  property var dict: ({})

  readonly property string system: {
    var loc = Qt.locale()
    var langs = loc.uiLanguages
    var first = langs && langs.length ? String(langs[0]) : String(loc.name)
    return first.toLowerCase().indexOf("pt") === 0 ? "pt" : "en"
  }
  readonly property string lang: setting === "pt" || setting === "en" ? setting : system

  // Locale for dates and numbers in the chosen language (day names etc.).
  readonly property var locale: Qt.locale(lang === "pt" ? "pt_BR" : "en_US")

  function tr(text) {
    if (lang === source) return text
    var t = dict[text]
    return t === undefined ? text : t
  }

  // tr() with %1, %2… filled in from the extra arguments.
  function trf(text) {
    var out = tr(text)
    for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
    return out
  }
}
