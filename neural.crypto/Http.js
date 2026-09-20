.pragma library

// Shared per QML engine: bounded, asynchronous HTTP with connection reuse.
var cache = {}
var jobs = {}
var queue = []
var active = 0
var stats = { requests: 0, hits: 0, joined: 0 }
var MAX_ACTIVE = 8
var MAX_CACHE = 32

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
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== XMLHttpRequest.DONE || job.done) return
    finish(job, Number(xhr.status), String(xhr.responseText || ""))
  }
  try { xhr.open("GET", job.url, true); xhr.send() }
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
