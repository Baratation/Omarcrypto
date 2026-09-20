import QtQuick
import Quickshell
import Quickshell.Io
import "Cache.js" as Cache

Item {
  id: root
  visible: false
  signal ready()
  readonly property string directory: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omarchy/crypto"
  property bool initialized: false
  property bool saving: false
  property int writingRevision: 0
  function flush() {
    if (!initialized || saving || !Cache.claim(root) || !Cache.dirty()) return
    writingRevision = Cache.revision
    saving = true
    disk.setText(Cache.snapshot())
  }
  Process {
    id: directoryInit
    command: ["mkdir", "-p", root.directory]
    onExited: function(code) {
      if (code === 0) disk.path = root.directory + "/market-v1.json"
      else root.ready()
    }
  }
  FileView {
    id: disk
    atomicWrites: true
    printErrors: false
    onLoaded: {
      Cache.restore(text())
      root.initialized = true
      root.ready()
    }
    onLoadFailed: { if (disk.path !== "") { root.initialized = true; root.ready() } }
    onSaved: { Cache.saved(root.writingRevision); root.saving = false }
    onSaveFailed: { root.saving = false }
  }
  Timer { interval: 5000; repeat: true; running: root.initialized; onTriggered: root.flush() }
  Component.onCompleted: directoryInit.running = true
  Component.onDestruction: Cache.release(root)
}
