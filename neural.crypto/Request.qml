import QtQuick
import "Http.js" as Http

// Each consumer owns its cancellation and timeout; a shared request survives
// as long as another consumer still needs it (e.g. a second monitor).
QtObject {
  id: root
  property bool running: false
  property var ticket: null
  property int generation: 0
  signal completed(int status, string body, double fetchedAt)
  property Timer deadline: Timer {
    interval: 8000
    onTriggered: { root.cancel(); root.completed(0, "", Date.now()) }
  }
  function cancel() {
    generation++
    deadline.stop()
    Http.cancel(ticket)
    ticket = null; running = false
  }
  function get(url, ttl, priority) {
    cancel()
    var serial = generation
    running = true; deadline.start()
    ticket = Http.request(url, ttl, priority, function(response) {
      if (serial !== root.generation) return
      root.deadline.stop(); root.running = false
      root.completed(response.status, response.body, response.at)
    })
  }
  Component.onDestruction: cancel()
}
