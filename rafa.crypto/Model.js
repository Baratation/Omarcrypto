.pragma library
.import "I18n.js" as I18n

// Pure helpers for rafa.crypto: provider URLs (Binance by default, CoinGecko
// optional), response parsing, the searchable coin catalogue, pt-BR number
// formatting and display metadata. The panel owns all state.

var BINANCE_API = "https://api.binance.com/api/v3/ticker/24hr"
var CURRENCIES = ["usd", "brl", "eur", "gbp", "jpy", "chf", "cad", "aud", "cny", "inr", "krw", "mxn", "ars"]
var COINGECKO_API = "https://api.coingecko.com/api/v3/simple/price"

// Curated catalogue for the picker and for symbol/id resolution. `brl` marks
// coins with a direct Binance BRL pair; the rest are converted through
// USDTBRL. Ids follow CoinGecko so the coingecko provider works from the same
// config. Coins outside it are found by the live picker search below.
var CATALOG = [
  { id: "bitcoin", symbol: "BTC", name: "Bitcoin", glyph: "₿", brl: true },
  { id: "ethereum", symbol: "ETH", name: "Ethereum", glyph: "Ξ", brl: true },
  { id: "tether", symbol: "USDT", name: "Tether", glyph: "₮", brl: true },
  { id: "usd-coin", symbol: "USDC", name: "USDC", glyph: "$", brl: true },
  { id: "binancecoin", symbol: "BNB", name: "BNB", glyph: "⬡", brl: true },
  { id: "ripple", symbol: "XRP", name: "XRP", glyph: "✕", brl: true },
  { id: "solana", symbol: "SOL", name: "Solana", glyph: "◎", brl: true },
  { id: "dogecoin", symbol: "DOGE", name: "Dogecoin", glyph: "Ð", brl: true },
  { id: "cardano", symbol: "ADA", name: "Cardano", glyph: "₳", brl: true },
  { id: "avalanche-2", symbol: "AVAX", name: "Avalanche", glyph: "▲", brl: true },
  { id: "chainlink", symbol: "LINK", name: "Chainlink", glyph: "⬡", brl: true },
  { id: "litecoin", symbol: "LTC", name: "Litecoin", glyph: "Ł", brl: true },
  { id: "near", symbol: "NEAR", name: "NEAR", glyph: "", brl: true },
  { id: "pepe", symbol: "PEPE", name: "Pepe", glyph: "", brl: true },
  { id: "polygon-ecosystem-token", symbol: "POL", name: "POL", glyph: "", brl: true },
  { id: "render-token", symbol: "RENDER", name: "Render", glyph: "", brl: true },
  { id: "shiba-inu", symbol: "SHIB", name: "Shiba Inu", glyph: "Ð", brl: true },
  { id: "sui", symbol: "SUI", name: "Sui", glyph: "", brl: true },
  { id: "toncoin", symbol: "TON", name: "Toncoin", glyph: "", brl: false },
  { id: "tron", symbol: "TRX", name: "TRON", glyph: "", brl: false },
  { id: "polkadot", symbol: "DOT", name: "Polkadot", glyph: "●", brl: false },
  { id: "stellar", symbol: "XLM", name: "Stellar", glyph: "", brl: false },
  { id: "ethereum-classic", symbol: "ETC", name: "Ethereum Classic", glyph: "", brl: false },
  { id: "monero", symbol: "XMR", name: "Monero", glyph: "", brl: false },
  { id: "bitcoin-cash", symbol: "BCH", name: "Bitcoin Cash", glyph: "", brl: false },
  { id: "hedera-hashgraph", symbol: "HBAR", name: "Hedera", glyph: "", brl: false },
  { id: "algorand", symbol: "ALGO", name: "Algorand", glyph: "", brl: false },
  { id: "vechain", symbol: "VET", name: "VeChain", glyph: "", brl: false },
  { id: "filecoin", symbol: "FIL", name: "Filecoin", glyph: "", brl: false },
  { id: "cosmos", symbol: "ATOM", name: "Cosmos", glyph: "", brl: false },
  { id: "aptos", symbol: "APT", name: "Aptos", glyph: "", brl: false },
  { id: "arbitrum", symbol: "ARB", name: "Arbitrum", glyph: "", brl: false },
  { id: "optimism", symbol: "OP", name: "Optimism", glyph: "", brl: false },
  { id: "uniswap", symbol: "UNI", name: "Uniswap", glyph: "", brl: false },
  { id: "aave", symbol: "AAVE", name: "Aave", glyph: "", brl: false },
  { id: "injective-protocol", symbol: "INJ", name: "Injective", glyph: "", brl: false },
  { id: "sei-network", symbol: "SEI", name: "Sei", glyph: "", brl: false },
  { id: "celestia", symbol: "TIA", name: "Celestia", glyph: "", brl: false },
  { id: "kaspa", symbol: "KAS", name: "Kaspa", glyph: "", brl: false },
  { id: "stacks", symbol: "STX", name: "Stacks", glyph: "", brl: false },
  { id: "immutable-x", symbol: "IMX", name: "Immutable", glyph: "", brl: false },
  { id: "the-graph", symbol: "GRT", name: "The Graph", glyph: "", brl: false },
  { id: "maker", symbol: "MKR", name: "Maker", glyph: "", brl: false },
  { id: "ethena", symbol: "ENA", name: "Ethena", glyph: "", brl: false },
  { id: "worldcoin-wld", symbol: "WLD", name: "Worldcoin", glyph: "", brl: false },
  { id: "fetch-ai", symbol: "FET", name: "Fetch.ai", glyph: "", brl: false },
  { id: "dogwifcoin", symbol: "WIF", name: "dogwifhat", glyph: "", brl: false },
  { id: "bonk", symbol: "BONK", name: "Bonk", glyph: "", brl: false },
  { id: "jupiter-exchange-solana", symbol: "JUP", name: "Jupiter", glyph: "", brl: false },
  { id: "lido-dao", symbol: "LDO", name: "Lido DAO", glyph: "", brl: false },
  { id: "curve-dao-token", symbol: "CRV", name: "Curve DAO", glyph: "", brl: false },
  { id: "gala", symbol: "GALA", name: "Gala", glyph: "", brl: false },
  { id: "sandbox", symbol: "SAND", name: "The Sandbox", glyph: "", brl: false },
  { id: "decentraland", symbol: "MANA", name: "Decentraland", glyph: "", brl: false },
  { id: "axie-infinity", symbol: "AXS", name: "Axie Infinity", glyph: "", brl: false },
  { id: "chiliz", symbol: "CHZ", name: "Chiliz", glyph: "", brl: false },
  { id: "basic-attention-token", symbol: "BAT", name: "Basic Attention", glyph: "", brl: false }
]

function catalogById(id) {
  var key = String(id || "").trim().toLowerCase()
  for (var i = 0; i < CATALOG.length; i++) if (CATALOG[i].id === key) return CATALOG[i]
  return null
}

function catalogBySymbol(symbol) {
  var key = String(symbol || "").trim().toUpperCase()
  for (var i = 0; i < CATALOG.length; i++) if (CATALOG[i].symbol === key) return CATALOG[i]
  return null
}

function coinFor(key) {
  var raw = String(key || "").trim()
  if (raw === "") return null
  var entry = catalogById(raw) || catalogBySymbol(raw)
  if (entry) return entry
  var id = raw.toLowerCase()
  return {
    id: id,
    symbol: /^[a-z0-9]{2,15}$/.test(id) ? id.toUpperCase() : "",
    name: fallbackName(raw),
    glyph: "",
    brl: false
  }
}

function fallbackName(id) {
  return String(id || "")
    .split("-")
    .map(function(part) { return part.charAt(0).toUpperCase() + part.slice(1) })
    .join(" ")
}

function symbolFor(id) {
  var entry = coinFor(id)
  if (!entry) return "?"
  if (entry.glyph) return entry.glyph
  if (entry.symbol) return entry.symbol
  return entry.id.slice(0, 3).toUpperCase()
}

function coinName(id) {
  var entry = coinFor(id)
  return entry ? entry.name : String(id || "")
}

// Accepts an array or a comma-separated string, lowercases and de-dupes, and
// falls back to Bitcoin when nothing usable is configured.
function normalizedCoins(value) {
  var list = value
  if (typeof list === "string") list = list.split(",")
  if (!list || typeof list.length !== "number") list = []

  var out = []
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i] === undefined || list[i] === null ? "" : list[i]).trim().toLowerCase()
    if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) continue
    if (out.indexOf(id) === -1) out.push(id)
  }
  return out.length > 0 ? out : ["bitcoin"]
}

// Canonical ids (catalogue ids when known) so pills, rows and quotes agree
// whether the user configured "btc", "BTC" or "bitcoin".
function canonicalCoins(list) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var entry = coinFor(list[i])
    if (!entry) continue
    if (out.indexOf(entry.id) === -1) out.push(entry.id)
  }
  return out
}

function searchCatalog(query, addedIds) {
  var q = String(query || "").trim().toLowerCase()
  if (q.length === 0) return []
  var out = []
  for (var i = 0; i < CATALOG.length; i++) {
    var entry = CATALOG[i]
    var haystack = (entry.id + " " + entry.symbol + " " + entry.name).toLowerCase()
    if (haystack.indexOf(q) === -1) continue
    out.push({
      id: entry.id,
      symbol: entry.symbol,
      name: entry.name,
      glyph: entry.glyph,
      added: !!(addedIds && addedIds.indexOf(entry.id) !== -1)
    })
    if (out.length >= 8) break
  }
  return out
}

// ---- live picker search (anything outside the catalogue) -------------------
//
// Binance has no symbol-search endpoint, so the panel fetches the exchange
// list once (through jq — the raw response is several MB and would be parsed
// anyway) and matches locally; CoinGecko has a per-query search endpoint.
// Only pairs that are actually TRADING are candidates: the ticker list still
// carries delisted symbols (XMR, MATIC…) whose frozen prices would look real.
// Ids stored by the picker follow the provider in use, so a coin added from
// the live search prices correctly right away.
var BINANCE_SYMBOLS_API = "https://api.binance.com/api/v3/exchangeInfo?permissions=SPOT&symbolStatus=TRADING"
var COINGECKO_SEARCH_API = "https://api.coingecko.com/api/v3/search"

function binanceSymbolsCommand() {
  return "curl -sS --compressed --max-time 25 '" + BINANCE_SYMBOLS_API + "'"
    + " | jq -er '.symbols[] | select(.status == \"TRADING\" and .quoteAsset == \"USDT\") | .baseAsset'"
}

function coingeckoSearchUrl(query) {
  return COINGECKO_SEARCH_API + "?query=" + encodeURIComponent(String(query || "").trim()) + "&per_page=20"
}

// One trading base asset per line (USDT pairs only, the provider reference).
function binanceBaseSymbols(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  var seen = {}
  for (var i = 0; i < lines.length; i++) {
    var base = lines[i].trim()
    if (!/^[A-Z0-9]{2,15}$/.test(base) || seen[base]) continue
    seen[base] = true
    out.push(base)
  }
  return out
}

function pickerEntryForBase(base, addedIds) {
  var id = String(base).toLowerCase()
  return {
    id: id,
    symbol: base,
    name: fallbackName(id),
    glyph: "",
    added: !!(addedIds && addedIds.indexOf(id) !== -1)
  }
}

function binancePickerResults(bases, query, addedIds) {
  var q = String(query || "").trim().toUpperCase()
  var out = []
  if (q.length === 0 || !bases || typeof bases.length !== "number") return out
  var starts = []
  var others = []
  for (var i = 0; i < bases.length; i++) {
    var idx = bases[i].indexOf(q)
    if (idx === 0) starts.push(bases[i])
    else if (idx > 0) others.push(bases[i])
  }
  for (var j = 0; j < starts.length && out.length < 8; j++) out.push(pickerEntryForBase(starts[j], addedIds))
  for (var k = 0; k < others.length && out.length < 8; k++) out.push(pickerEntryForBase(others[k], addedIds))
  return out
}

function coingeckoPickerResults(raw, addedIds) {
  var data = JSON.parse(raw)
  var out = []
  var coins = data && Array.isArray(data.coins) ? data.coins : []
  for (var i = 0; i < coins.length && out.length < 8; i++) {
    var coin = coins[i]
    if (!coin || !coin.id) continue
    var id = String(coin.id).toLowerCase()
    if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) continue
    out.push({
      id: id,
      symbol: String(coin.symbol || "").toUpperCase(),
      name: String(coin.name || coin.id),
      glyph: "",
      added: !!(addedIds && addedIds.indexOf(id) !== -1)
    })
  }
  return out
}

// Catalogue hits first, live results after, deduped by id and symbol so the
// curated "bitcoin" wins over the live "BTC" for the same coin.
function mergePickerResults(localResults, remoteResults, addedIds) {
  var out = []
  var ids = {}
  var symbols = {}
  function push(entry) {
    if (!entry || !entry.id || ids[entry.id]) return
    if (entry.symbol && symbols[entry.symbol]) return
    ids[entry.id] = true
    if (entry.symbol) symbols[entry.symbol] = true
    out.push({
      id: entry.id,
      symbol: entry.symbol,
      name: entry.name,
      glyph: entry.glyph,
      added: !!(addedIds && addedIds.indexOf(entry.id) !== -1)
    })
  }
  var local = Array.isArray(localResults) ? localResults : []
  var remote = Array.isArray(remoteResults) ? remoteResults : []
  for (var i = 0; i < local.length && out.length < 8; i++) push(local[i])
  for (var j = 0; j < remote.length && out.length < 8; j++) push(remote[j])
  return out
}

function normalizedVs(value) {
  var vs = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return /^[a-z]{3}$/.test(vs) ? vs : "brl"
}

function normalizedProvider(value) {
  return String(value || "").trim().toLowerCase() === "coingecko" ? "coingecko" : "binance"
}

// Pinned coin for the pill: only accepted when it names one of the configured
// coins, so a stale pin after a removal just falls back to automatic mode.
function normalizedPin(value, coins) {
  var id = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (id === "") return ""
  var list = coins && typeof coins.length === "number" ? coins : []
  return list.indexOf(id) !== -1 ? id : ""
}

// ---- provider: Binance (default) ------------------------------------------

function binancePairFor(coin, currency) {
  if (currency === "usd") return coin.symbol === "USDT" ? "" : coin.symbol + "USDT"
  return coin.symbol + String(currency).toUpperCase()
}

function binancePairs(coins, currencies) {
  var pairs = []
  var wantsBrl = currencies.indexOf("brl") !== -1
  function push(pair) {
    if (pair && pairs.indexOf(pair) === -1) pairs.push(pair)
  }
  for (var i = 0; i < coins.length; i++) {
    var coin = coinFor(coins[i])
    if (!coin || !coin.symbol) continue
    push(binancePairFor(coin, "usd"))
    if (wantsBrl && coin.brl) push(coin.symbol + "BRL")
  }
  if (wantsBrl) push("USDTBRL")
  return pairs
}

function binanceUrl(coins, currencies) {
  var pairs = binancePairs(coins, currencies)
  return BINANCE_API + "?symbols=" + encodeURIComponent(JSON.stringify(pairs))
}

function parseBinance(raw) {
  var data = JSON.parse(raw)
  var out = {}
  if (!Array.isArray(data)) return out
  for (var i = 0; i < data.length; i++) {
    var item = data[i]
    if (!item || typeof item !== "object" || !item.symbol) continue
    var price = Number(item.lastPrice)
    if (!isFinite(price)) continue
    var change = Number(item.priceChangePercent)
    out[item.symbol] = { price: price, change: isFinite(change) ? change : null }
  }
  return out
}

function binanceQuotes(pairs, coins, currencies) {
  var usdtBrl = pairs["USDTBRL"] ? pairs["USDTBRL"].price : 0
  var out = {}
  for (var i = 0; i < coins.length; i++) {
    var coin = coinFor(coins[i])
    if (!coin || !coin.symbol) continue
    var usdt = coin.symbol === "USDT" ? { price: 1, change: 0 } : pairs[coin.symbol + "USDT"] || null
    var directBrl = pairs[coin.symbol + "BRL"] || null
    var quotes = {}
    for (var c = 0; c < currencies.length; c++) {
      var vs = currencies[c]
      if (vs === "usd" && usdt) quotes.usd = { price: usdt.price, change: usdt.change }
      else if (vs === "brl") {
        if (directBrl) quotes.brl = { price: directBrl.price, change: directBrl.change }
        else if (usdt && usdtBrl > 0) quotes.brl = { price: usdt.price * usdtBrl, change: usdt.change }
      }
    }
    if (Object.keys(quotes).length > 0) out[coin.id] = quotes
  }
  return out
}

// ---- provider: CoinGecko (optional) ---------------------------------------

function coingeckoUrl(coins, currencies) {
  return COINGECKO_API
    + "?ids=" + encodeURIComponent(coins.join(","))
    + "&vs_currencies=" + encodeURIComponent(currencies.join(","))
    + "&include_24hr_change=true&include_last_updated_at=true"
}

function parseCoingecko(raw, currencies) {
  var data = JSON.parse(raw)
  var out = {}
  for (var id in data) {
    if (!Object.prototype.hasOwnProperty.call(data, id)) continue
    var entry = data[id]
    if (!entry || typeof entry !== "object") continue
    var quotes = {}
    for (var i = 0; i < currencies.length; i++) {
      var vs = currencies[i]
      var price = Number(entry[vs])
      if (!isFinite(price) || price <= 0) continue
      var change = entry[vs + "_24h_change"] === null ? NaN : Number(entry[vs + "_24h_change"])
      quotes[vs] = { price: price, change: isFinite(change) ? change : null }
    }
    if (Object.keys(quotes).length > 0) out[id] = quotes
  }
  return out
}

// ---- provider facade ------------------------------------------------------

function apiUrl(provider, coins, currencies) {
  return normalizedProvider(provider) === "coingecko"
    ? coingeckoUrl(coins, currencies)
    : binanceUrl(coins, currencies)
}

function parseQuotes(provider, raw, coins, currencies) {
  return normalizedProvider(provider) === "coingecko"
    ? parseCoingecko(raw, currencies)
    : binanceQuotes(parseBinance(raw), coins, currencies)
}

function apiError(provider, status, body) {
  if (status === "429" || status === "418") return I18n.tr("limite")
  var detail = ""
  try {
    var parsed = JSON.parse(body)
    if (parsed && parsed.msg) detail = String(parsed.msg)
  } catch (e) {}
  if (detail) return detail.charAt(0).toLowerCase() + detail.slice(1)
  return "HTTP " + status
}

// ---- chart: Binance klines -------------------------------------------------

var BINANCE_KLINES_API = "https://api.binance.com/api/v3/klines"

// Compact chip labels: seven of them have to fit the panel width.
var CHART_INTERVALS = [
  { id: "5m", label: "5m" },
  { id: "15m", label: "15m" },
  { id: "1h", label: "1h" },
  { id: "4h", label: "4h" },
  { id: "1d", label: "1d" },
  { id: "1w", label: I18n.tr("1sem") },
  { id: "1M", label: I18n.tr("1mês") }
]

function normalizedChartInterval(value) {
  var id = String(value || "").trim()
  for (var i = 0; i < CHART_INTERVALS.length; i++) if (CHART_INTERVALS[i].id === id) return id
  return "1h"
}

function chartIntervalOptions() {
  var out = []
  for (var i = 0; i < CHART_INTERVALS.length; i++) {
    out.push({ value: CHART_INTERVALS[i].id, label: CHART_INTERVALS[i].label })
  }
  return out
}

// Pair and display currency for the candle chart. BRL uses the direct pair
// when the coin has one; anything else falls back to the USDT pair (labelled
// USDT) instead of pretending the values are in the main currency.
function chartPair(coinId, vs) {
  var coin = coinFor(coinId)
  if (!coin || !coin.symbol) return null
  var currency = normalizedVs(vs)
  if (currency === "brl" && coin.brl) return { pair: coin.symbol + "BRL", currency: "brl", label: "BRL" }
  if (coin.symbol === "USDT") return null
  return { pair: coin.symbol + "USDT", currency: "usd", label: "USDT" }
}

function klinesUrl(pair, interval, limit, endTime) {
  return BINANCE_KLINES_API
    + "?symbol=" + encodeURIComponent(pair)
    + "&interval=" + encodeURIComponent(normalizedChartInterval(interval))
    + "&limit=" + (Number(limit) > 0 ? Math.min(1000, Math.floor(limit)) : 180)
    + (endTime > 0 ? "&endTime=" + Math.floor(endTime) : "")
}

// Binance returns [[openTime, open, high, low, close, volume, ...], ...].
function parseKlines(raw) {
  var data = JSON.parse(raw)
  var out = []
  if (!Array.isArray(data)) return out
  for (var i = 0; i < data.length; i++) {
    var k = data[i]
    if (!Array.isArray(k) || k.length < 6) continue
    var o = Number(k[1]), h = Number(k[2]), l = Number(k[3]), c = Number(k[4]), v = Number(k[5])
    if (!isFinite(o) || !isFinite(h) || !isFinite(l) || !isFinite(c)) continue
    out.push({ t: Number(k[0]), o: o, h: h, l: l, c: c, v: isFinite(v) ? v : 0 })
  }
  return out
}

function twoDigits(value) {
  return (value < 10 ? "0" : "") + value
}

var MONTHS_SHORT = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

// Axis label for a candle timestamp; granularity follows the timeframe.
// Intraday windows fit a clock; longer ones switch to a date so repeated
// hours from different days are not mistaken for one session.
function formatChartTime(ms, interval) {
  var d = new Date(Number(ms) || 0)
  var id = normalizedChartInterval(interval)
  if (id === "1M") return I18n.chartDate(ms, true)
  if (id === "5m" || id === "15m") return twoDigits(d.getHours()) + ":" + twoDigits(d.getMinutes())
  return I18n.chartDate(ms, false)
}

// ---- formatting -----------------------------------------------------------

function groupThousands(intText) {
  var out = ""
  var count = 0
  for (var i = intText.length - 1; i >= 0; i--) {
    out = intText.charAt(i) + out
    count++
    if (count % 3 === 0 && i > 0) out = "." + out
  }
  return out
}

function formatNumber(value, decimals) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  return I18n.number(value, decimals)
}

function formatCompact(value) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  var abs = Math.abs(value)
  if (abs >= 1e9) return formatNumber(value / 1e9, 2) + "B"
  if (abs >= 1e6) return formatNumber(value / 1e6, 2) + "M"
  if (abs >= 1e3) return formatNumber(value / 1e3, 1) + "k"
  if (abs >= 1) return formatNumber(value, 2)
  if (abs >= 0.01) return formatNumber(value, 4)
  return formatNumber(value, 6)
}

function currencySymbol(vs) {
  if (vs === "brl") return "R$"
  if (vs === "usd") return "$"
  if (vs === "eur") return "€"
  if (vs === "gbp") return "£"
  if (vs === "jpy") return "JPY"
  if (vs === "cad") return "CA$"
  if (vs === "aud") return "A$"
  if (vs === "mxn") return "MX$"
  if (vs === "ars") return "AR$"
  if (vs === "inr") return "₹"
  if (vs === "krw") return "₩"
  return String(vs || "").toUpperCase()
}

function formatPrice(value, vs) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  var abs = Math.abs(value)
  var decimals = abs >= 0.01 ? 2 : (abs >= 0.0001 ? 4 : 6)
  return currencySymbol(vs) + " " + formatNumber(value, decimals)
}

function formatChange(value) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  return (value >= 0 ? "+" : "") + formatNumber(value, 2) + "%"
}

function arrow(value) {
  if (typeof value !== "number" || !isFinite(value) || Math.abs(value) < 0.005) return ""
  return value > 0 ? "▲" : "▼"
}

function formatAge(seconds) {
  if (typeof seconds !== "number" || !isFinite(seconds) || seconds < 0) return "—"
  if (seconds < 60) return Math.floor(seconds) + "s"
  if (seconds < 3600) return Math.floor(seconds / 60) + "min"
  return Math.floor(seconds / 3600) + "h"
}

// ---- price alerts ----------------------------------------------------------

// Alerts are one-shot: an armed alert fires once when the quoted price is at
// or beyond the target, then stays listed as fired until the user re-arms it.
// `dir` is the direction the price has to move: "above" fires on >= target,
// "below" fires on <= target.

function alertId(coin, dir, price, vs) {
  return String(coin) + "|" + normalizedVs(vs) + "|" + (dir === "below" ? "below" : "above") + "|" + String(Number(price))
}

function normalizedAlerts(value) {
  var list = value
  if (typeof list === "string") {
    try { list = JSON.parse(list) } catch (e) { list = [] }
  }
  // Inline settings come back from the shell as a plain JS array or as an
  // indexed sequence (QVariantList); copy the latter into a real array so
  // Array.isArray and the parsers below work either way.
  if (!Array.isArray(list) && list && typeof list === "object" && typeof list.length === "number") {
    var copy = []
    for (var c = 0; c < list.length; c++) copy.push(list[c])
    list = copy
  }
  if (!Array.isArray(list)) list = []
  var out = []
  var ids = {}
  for (var i = 0; i < list.length; i++) {
    var raw = list[i]
    if (!raw || typeof raw !== "object") continue
    var coin = String(raw.coin || "").trim().toLowerCase()
    var price = Number(raw.price)
    if (!/^[a-z0-9][a-z0-9-]*$/.test(coin) || !isFinite(price) || price <= 0) continue
    var dir = raw.dir === "below" ? "below" : "above"
    // Canonicalize legacy IDs without losing their state or currency.
    var id = alertId(coin, dir, price, raw.vs)
    if (ids[id]) continue
    ids[id] = true
    var firedAt = Number(raw.firedAt)
    var firedPrice = Number(raw.firedPrice)
    out.push({
      id: id,
      coin: coin,
      dir: dir,
      price: price,
      vs: normalizedVs(raw.vs),
      armed: raw.paused !== true && (raw.armed === undefined ? true : raw.armed === true),
      paused: raw.paused === true || (raw.armed === false && !(firedAt > 0)),
      firedAt: isFinite(firedAt) ? firedAt : 0,
      firedPrice: isFinite(firedPrice) ? firedPrice : 0
    })
  }
  return out
}

function alertCrossed(alert, price) {
  var p = Number(price)
  if (!alert || !isFinite(p)) return false
  return alert.dir === "below" ? p <= alert.price : p >= alert.price
}

function alertArrow(alert) {
  return alert && alert.dir === "below" ? "▼" : "▲"
}

function alertGoalText(alert) {
  return alertArrow(alert) + " " + formatPrice(alert.price, alert.vs)
}

function alertMessage(alert, price) {
  var verb = alert.dir === "below" ? I18n.tr("caiu para") : I18n.tr("subiu para")
  return {
    title: coinName(alert.coin) + " " + alertArrow(alert),
    body: I18n.tr("Preço ") + verb + " " + formatPrice(price, alert.vs) + I18n.tr(" · alerta ") + formatPrice(alert.price, alert.vs)
  }
}

// pt-BR friendly number parsing for the alert target field: "350.000,50" and
// "350000" both become 350000.5; a lone dot with three decimals is treated as
// a thousands separator ("350.000"), otherwise as a decimal point ("0.001").
function parseLocalNumber(text) { return I18n.parseNumber(text) }

// Keep the original usd setting for compatibility; Binance quotes are USDT.
function quoteCurrency(provider, vs) {
  return vs === "usd" ? (provider === "binance" ? "USDT" : "US$") : currencySymbol(vs)
}
function quotePrice(value, provider, vs) {
  return formatPrice(value, vs).replace(currencySymbol(vs), quoteCurrency(provider, vs))
}
function quoteSource(provider, id, vs) {
  if (provider !== "binance") return "CoinGecko · " + vs.toUpperCase()
  var coin = coinFor(id)
  if (!coin) return "Binance"
  if (vs === "brl" && coin.brl) return "Binance · " + coin.symbol + "/BRL" + I18n.tr(" · direto")
  if (vs === "brl") return "Binance · " + coin.symbol + "/USDT × USDT/BRL" + I18n.tr(" · convertido")
  if (vs !== "usd") return "Binance · " + coin.symbol + "/USDT × USDT/" + vs.toUpperCase() + " · CoinGecko" + I18n.tr(" · convertido")
  return "Binance · " + coin.symbol + "/USDT"
}
function alertDistance(alert, price) {
  if (!(price > 0) || !(alert.price > 0)) return I18n.tr("sem cotação")
  var crossed = alert.dir === "below" ? price <= alert.price : price >= alert.price
  return crossed ? I18n.tr("alvo atingido") : I18n.tr("faltam ") + formatNumber(Math.abs(alert.price / price - 1) * 100, 2) + "%" + I18n.tr(" para o alvo")
}
// Merge by opening timestamp: polling replaces the live candle without
// throwing away older pages or duplicating candles at page boundaries.
function mergeCandles(older, newer) {
  var out = [], i = 0, j = 0
  while (i < older.length && j < newer.length) {
    if (older[i].t < newer[j].t) out.push(older[i++])
    else if (older[i].t > newer[j].t) out.push(newer[j++])
    else { out.push(newer[j++]); i++ }
  }
  while (i < older.length) out.push(older[i++])
  while (j < newer.length) out.push(newer[j++])
  return out
}
function periodInterval(days) { return days === 1 ? "15m" : days === 7 ? "1h" : "4h" }
function periodStart(candles, days) {
  if (!candles.length) return 0
  var cutoff = candles[candles.length - 1].t - days * 86400000
  for (var i = 0; i < candles.length; i++) if (candles[i].t > cutoff) return i
  return 0
}

function tickerFor(id) {
  var coin = coinFor(id)
  return coin && coin.symbol ? coin.symbol : String(id).toUpperCase()
}

// Editing replaces the old condition; pausing never changes its target.
function replaceAlert(list, draft, editingId) {
  var clean = normalizedAlerts([draft])
  if (!clean.length) return normalizedAlerts(list)
  var alert = clean[0]
  var next = normalizedAlerts(list).filter(function(a) { return a.id !== editingId && a.id !== alert.id })
  next.push(alert)
  return next
}
function toggleAlert(list, id) {
  return normalizedAlerts(list).map(function(a) {
    if (a.id !== id) return a
    a.armed = !a.armed
    a.paused = !a.armed
    if (a.armed) { a.firedAt = 0; a.firedPrice = 0 }
    return a
  })

}

// Binance remains the source for each asset. CoinGecko supplies the actual
// USDT/fiat cross rate, so no 1 USDT = 1 USD assumption is made.
function convertQuotes(prices, rates, currencies, fxAt) {
  var out = {}
  Object.keys(prices).forEach(function(id) {
    var quotes = Object.assign({}, prices[id]), base = quotes.usd
    currencies.forEach(function(vs) {
      if (vs === "usd" || vs === "brl" || !base || !rates[vs] || !(rates[vs].price > 0)) return
      var rate = rates[vs]
      quotes[vs] = { price: base.price * rate.price,
        change: base.change !== null && rate.change !== null ? ((1 + base.change / 100) * (1 + rate.change / 100) - 1) * 100 : null,
        fxAt: fxAt }
    })
    out[id] = quotes
  })
  return out
}
