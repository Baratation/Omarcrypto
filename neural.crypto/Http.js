.pragma library

// Shared per QML engine: bounded, asynchronous HTTP with connection reuse.
var cache = {}
var jobs = {}
var queue = []
var active = 0
var stats = { requests: 0, hits: 0, joined: 0, failovers: 0 }
var MAX_ACTIVE = 8
var MAX_CACHE = 32

// Binance serves the same public market data from several hosts. Qt keeps one
// HTTP/2 connection per host and aborting a request only resets its stream, so
// a connection that died in a network blip swallows every later request until
// the kernel gives up on it (~15 min). A stalled request moves the engine to
// the next host, which forces a fresh connection. Jobs keep the canonical URL
// as their key, so caching and de-duplication do not see the switch.
var BINANCE_HOSTS = ["api.binance.com", "api-gcp.binance.com", "data-api.binance.vision"]
var BINANCE_PREFIX = "https://" + BINANCE_HOSTS[0] + "/"
var binanceHost = 0

function wireUrl(url) {
  if (binanceHost === 0 || url.indexOf(BINANCE_PREFIX) !== 0) return url
  return "https://" + BINANCE_HOSTS[binanceHost] + "/" + url.slice(BINANCE_PREFIX.length)
}
function failover(job) {
  // Several requests stall on the same dead connection; only the first moves on.
  if (job.url.indexOf(BINANCE_PREFIX) !== 0 || job.host !== binanceHost) return
  binanceHost = (binanceHost + 1) % BINANCE_HOSTS.length
  stats.failovers++
  console.warn("crypto HTTP: no answer from " + BINANCE_HOSTS[job.host] + ", switching to " + BINANCE_HOSTS[binanceHost])
}
// A consumer's deadline expired. Only a request that actually went out says
// anything about the host; one still queued behind others does not.
function stalled(token) {
  var job = token && token.job
  if (job && job.xhr && !job.done) failover(job)
}

function trimCache() {
  var keys = Object.keys(cache).sort(function(a,b) { return cache[a].used - cache[b].used })
  while (keys.length > MAX_CACHE) delete cache[keys.shift()]
}
function deliver(token, response) {
  if (!token.active) return
  token.active = false
  token.callback(response)
}
function request(url, ttl, priority, callback) {
  var token = { active: true, callback: callback, job: null }
  var hit = cache[url]
  if (hit && Date.now() - hit.at < ttl) {
    hit.used = Date.now(); stats.hits++
    deliver(token, { status: 200, body: hit.body, at: hit.at })
    return token
  }
  var job = jobs[url]
  if (job) {
    stats.joined++
    job.priority = Math.max(job.priority, priority)
  } else {
    job = { url: url, priority: priority, subscribers: [], xhr: null, done: false }
    jobs[url] = job; queue.push(job)
  }
  job.subscribers.push(token); token.job = job
  pump()
  return token
}
function cancel(token) {
  if (!token || !token.active) return
  token.active = false
  var job = token.job
  if (!job || job.done || job.subscribers.some(function(t) { return t.active })) return
  job.done = true; delete jobs[job.url]
  if (job.xhr) { job.xhr.onreadystatechange = function() {}; job.xhr.abort(); active-- }
  else queue = queue.filter(function(j) { return j !== job })
  pump()
}
function pump() {
  queue.sort(function(a,b) { return b.priority - a.priority })
  while (active < MAX_ACTIVE && queue.length) {
    var job = queue.shift()
    if (!job.done) start(job)
  }
}
function start(job) {
  active++; stats.requests++
  var xhr = new XMLHttpRequest()
  job.xhr = xhr
  job.host = binanceHost
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== XMLHttpRequest.DONE || job.done) return
    var status = Number(xhr.status)
    if (status === 0) failover(job)
    finish(job, status, String(xhr.responseText || ""))
  }
  try { xhr.open("GET", wireUrl(job.url), true); xhr.send() }
  catch(e) { finish(job, 0, "") }
}
function finish(job, status, body) {
  if (job.done) return
  job.done = true; active--; delete jobs[job.url]
  var at = Date.now()
  if (status === 200) { cache[job.url] = {body: body, at: at, used: at}; trimCache() }
  job.subscribers.forEach(function(t) {
    try { deliver(t, {status: status, body: body, at: at}) }
    catch(e) { console.warn("crypto HTTP callback:", e) }
  })
  pump()
}
