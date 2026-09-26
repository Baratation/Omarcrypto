import QtQuick

// Staggered entrance for a panel's sections: each visible child of
// `container` fades in and rises a few pixels, one after another. Call play()
// (or flip `shown` to true) whenever the content should make an entrance —
// on open, or when a view switches. It writes each child's opacity and adds a
// Translate to its transform, so point it only at children that do not bind
// those themselves. A child's resting opacity (e.g. a 0.12 divider) is
// remembered the first time it is seen and restored as the end state.
QtObject {
  id: root

  property Item container: null
  property bool shown: false
  property int step: 55          // ms between one child and the next
  property int each: 420         // ms each child takes to settle
  property real distance: 12     // px each child rises

  property real clock: 0
  property var targets: []
  property var shifts: []
  property var bases: []
  property var known: []

  onShownChanged: if (shown) play()

  function translateFor(item) {
    var list = item.transform
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].objectName === "fxStaggerShift") return list[i]
    }
    var t = Qt.createQmlObject('import QtQuick; Translate { objectName: "fxStaggerShift" }', item)
    var next = []
    for (var j = 0; j < list.length; j++) next.push(list[j])
    next.push(t)
    item.transform = next
    return t
  }

  function restingOpacity(item) {
    for (var i = 0; i < known.length; i++) {
      if (known[i].item === item) return known[i].base
    }
    known.push({ item: item, base: item.opacity })
    return item.opacity
  }

  function play() {
    if (!container) return
    var items = []
    var moves = []
    var rest = []
    var kids = container.children
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (!kid || !kid.visible || kid.height <= 0) continue
      items.push(kid)
      moves.push(translateFor(kid))
      rest.push(restingOpacity(kid))
    }
    targets = items
    shifts = moves
    bases = rest
    anim.stop()
    clock = 0
    apply()
    anim.to = (items.length - 1) * step + each
    anim.duration = anim.to
    anim.start()
  }

  function apply() {
    for (var i = 0; i < targets.length; i++) {
      var local = Math.max(0, Math.min(1, (clock - i * step) / each))
      var eased = 1 - Math.pow(1 - local, 3)
      if (targets[i]) targets[i].opacity = eased * bases[i]
      if (shifts[i]) shifts[i].y = (1 - eased) * distance
    }
  }

  onClockChanged: apply()

  property NumberAnimation anim: NumberAnimation {
    target: root
    property: "clock"
    from: 0
    easing.type: Easing.Linear
  }
}
