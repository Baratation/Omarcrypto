.pragma library

// Shared by all monitor instances. Only market data goes to disk, never alerts.
var buckets = { quotes: {}, sparks: {}, charts: {} }
var limits = { quotes: 6, sparks: 24, charts: 8 }
var revision = 0
var savedRevision = 0
var writer = null
var MAX_AGE = 7 * 86400000
function number(value) { return typeof value === "number" && isFinite(value) }
function validTime(at) { return number(at) && at > 0 && Date.now() - at < MAX_AGE && at <= Date.now() + 60000 }
function clean(kind, value) {
  if (!value || !validTime(value.at)) return null
  var result = { at: value.at, restored: value.restored === true }
  if (kind === "quotes") {
    if (!value.prices || typeof value.prices !== "object") return null
    result.prices = {}
    Object.keys(value.prices).slice(0, 100).forEach(function(coin) {
      if (!/^[a-z0-9][a-z0-9-]*$/.test(coin)) return
      var raw = value.prices[coin], quotes = {}
      if (!raw || typeof raw !== "object") return
      Object.keys(raw).forEach(function(vs) {
        var q = raw[vs]
        if (!/^[a-z]{3}$/.test(vs) || !q || !number(q.price) || q.price <= 0) return
        quotes[vs] = { price: q.price, change: number(q.change) ? q.change : null }
      })
      if (Object.keys(quotes).length) result.prices[coin] = quotes
    })
    if (!Object.keys(result.prices).length) return null
  } else if (kind === "sparks") {
    if (!Array.isArray(value.values) || value.values.length < 2 || value.values.length > 1000) return null
    if (!value.values.every(function(v) { return number(v) && v > 0 })) return null
    result.values = value.values.slice(-200)
  } else if (kind === "charts") {
    if (!Array.isArray(value.candles) || !value.candles.length) return null
    var tail = value.candles.slice(-720), previous = -1
    if (!tail.every(function(c) {
      if (!c || !number(c.t) || c.t <= previous || ![c.o,c.h,c.l,c.c,c.v].every(number)
          || Math.min(c.o,c.h,c.l,c.c) <= 0 || c.v < 0 || c.h < Math.max(c.o,c.c,c.l) || c.l > Math.min(c.o,c.c)) return false
      previous = c.t; return true
    })) return null
    result.candles = tail.map(function(c) { return {t:c.t,o:c.o,h:c.h,l:c.l,c:c.c,v:c.v} })
    var trimmed = value.candles.length - tail.length
    result.start = number(value.start) ? Math.max(0, Math.min(tail.length - 1, Math.floor(value.start) - trimmed)) : 0
    result.end = number(value.end) ? Math.max(result.start + 1, Math.min(tail.length, Math.floor(value.end) - trimmed)) : tail.length
    result.ended = !trimmed && value.ended === true
  } else return null
  return result
}
function prune(kind) {
  var bucket = buckets[kind]
  Object.keys(bucket).forEach(function(key) { if (!validTime(bucket[key].at)) delete bucket[key] })
  var keys = Object.keys(bucket).sort(function(a,b) { return bucket[b].at - bucket[a].at })
  keys.slice(limits[kind]).forEach(function(key) { delete bucket[key] })
}
function put(kind, key, value) {
  if (!Object.prototype.hasOwnProperty.call(limits, kind) || typeof key !== "string" || !key || key.length > 4096 || key === "__proto__" || key === "constructor" || key === "prototype") return false
  var entry = clean(kind, value)
  if (!entry) return false
  var old = buckets[kind][key]
  if (old && old.at > entry.at) return false
  buckets[kind][key] = entry
  prune(kind); revision++
  return true
}
function get(kind, key) {
  var value = buckets[kind] && Object.prototype.hasOwnProperty.call(buckets[kind], key) ? buckets[kind][key] : null
  return value && validTime(value.at) ? value : null
}
function entries(kind) { prune(kind); return Object.assign({}, buckets[kind]) }
function restore(text) {
  if (!text || text.length > 4000000) return false
  try {
    var data = JSON.parse(text)
    if (data.version !== 1 || !data.buckets) return false
    Object.keys(limits).forEach(function(kind) {
      var raw = data.buckets[kind]
      if (!raw || typeof raw !== "object") return
      Object.keys(raw).slice(0, 100).forEach(function(key) {
        // A late disk read must never overwrite data already fetched live.
        if (get(kind,key) && get(kind,key).at >= Number(raw[key] && raw[key].at)) return
        if (put(kind,key,raw[key]) && get(kind,key)) buckets[kind][key].restored = true
      })
    })
    return true
  } catch(e) { return false }
}
function snapshot() {
  Object.keys(limits).forEach(prune)
  return JSON.stringify({version:1,buckets:buckets}) + "\n"
}
function claim(owner) { if (!writer) writer = owner; return writer === owner }
function release(owner) { if (writer === owner) writer = null }
function dirty() { return revision !== savedRevision }
function saved(atRevision) { savedRevision = atRevision }
