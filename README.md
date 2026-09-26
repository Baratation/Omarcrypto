# Omarcrypto

Omarcrypto is a cryptocurrency widget for the [Omarchy](https://omarchy.org/)
Quickshell bar. It keeps the bar compact while opening a full panel for coins,
charts, alerts, and settings.

![Widget in the bar](docs/bar.png)

## Features

- Shows the ticker, a compact price, and an up/down trend arrow in the bar,
  over a faint 24-hour sparkline that follows the live price. The pill only
  animates when something happens (a new price, hover, a click), so it costs
  nothing while idle.
- Opens a watchlist with the primary price, a secondary quote, 24-hour change,
  and a sparkline for each coin.
- Displays candlesticks, volume, 1-day/1-week/1-month periods, zoom, and
  historical data.
- Creates, edits, pauses, rearms, and removes price alerts with system
  notifications. Alerts are stored in
  `~/.local/share/omarchy/crypto/alerts.json` and changed only by the bundled
  `alerts` script, so several monitors never fire the same alert twice.
- Supports keyboard navigation for selection, search, charts, alerts, pinning,
  refresh, and quote-currency switching.
- Detects the system locale (Portuguese, English, Spanish, French, and German)
  and formats numbers and values accordingly.
- Supports USD/USDT, BRL, EUR, GBP, JPY, CHF, CAD, AUD, CNY, INR, KRW, MXN,
  and ARS. The currency menu stays collapsed until opened.
- Persists prices, sparklines, and candle series at
  `~/.cache/omarchy/crypto/market-v1.json` so the widget can open quickly after
  a restart.

![Coin panel](docs/panel.png)

![Chart](docs/chart.png)

![Alert editor](docs/alerts.png)

![Collapsed currency menu](docs/currency-menu.png)

## Providers and conversion

Binance is the default provider. Candles use the native pair that is available;
when a selected currency has no direct pair, the price is converted from USDT
using the corresponding CoinGecko rate. The widget never assumes that USDT is
USD and does not recalculate historical candles using today's exchange rate.

A few details keep Binance prices honest:

- Delisted pairs still answer with their last trade; the widget recognizes
  them by their empty order book and shows "no quote" instead of a frozen price.
- A coin Binance does not list would make the whole price request fail. The
  widget then checks each pair alone and leaves the unknown ones out.
- On thin pairs (some BRL ones) the last trade can sit outside the current
  order book; the book midpoint is shown instead.
- If a request hangs (a connection that died in a network drop), the widget
  moves to another Binance host (`api-gcp.binance.com`,
  `data-api.binance.vision`) instead of waiting minutes for the system to give
  up on it.

CoinGecko can also be used directly for simple quotes:

```bash
omarchy bar set neural.crypto provider coingecko
```

## Installation

Requirements: Omarchy with Quickshell, `omarchy` on `PATH`, `python3` (for
the alerts script), and internet access for price queries.

```bash
git clone https://github.com/neuralcheckpoint/Omarcrypto.git
cd Omarcrypto
mkdir -p ~/.config/omarchy/plugins
cp -a neural.crypto ~/.config/omarchy/plugins/
omarchy plugin validate ~/.config/omarchy/plugins/neural.crypto
omarchy restart shell
```

The technical plugin ID is `neural.crypto`.

To change settings without opening the panel:

```bash
omarchy bar set neural.crypto coins '["bitcoin","ethereum","solana"]' --json
omarchy bar set neural.crypto vs brl
omarchy bar set neural.crypto vs2 usd
omarchy bar set neural.crypto rotate 8
omarchy bar set neural.crypto pin bitcoin
```

`pin` keeps one coin in the bar; leave it empty to resume cycling. Set `vs2` to
an empty value to hide the secondary quote.

## Keyboard and mouse

- `↑`/`↓` or `j`/`k`: select a coin.
- `Enter`/`G`: open its chart.
- `N`: create an alert; `P`: pin the coin.
- `Tab`: switch between coins and alerts; `Enter`/`E`: edit an alert.
- `R`: refresh; `A` or `/`: search; `C`: toggle cycling; `U`: switch the
  primary/secondary quote.
- Left click: open the panel; right click: send a summary; middle click:
  refresh.

## Tests

These pure Node.js tests do not require Quickshell:

```bash
node tests/crypto-model.cjs
node tests/crypto-state.cjs
node tests/crypto-locale-currency.cjs
node tests/crypto-binance.cjs
```

`crypto-binance.cjs` also runs the `alerts` script (it needs `python3`) against
a temporary data folder.

## Project layout

| Path | Responsibility |
| --- | --- |
| `neural.crypto/BarWidget.qml` | Bar pill and widget IPC |
| `neural.crypto/Panel.qml` | State, polling, list, search, and alerts |
| `neural.crypto/Chart.qml` | Candles, volume, zoom, and history |
| `neural.crypto/Model.js` | Providers, conversion, catalog, and formatting |
| `neural.crypto/I18n.js` | Locale detection, translations, and numeric input |
| `neural.crypto/Cache.js` / `PersistentCache.qml` | Validated persistent cache |
| `neural.crypto/Http.js` / `Request.qml` | Shared requests, timeouts, and Binance host failover |
| `neural.crypto/Sparkline.qml` | Per-coin 24-hour sparkline in the panel |
| `neural.crypto/alerts` | Alert storage: lock, atomic writes, one notification per crossing |
| `neural.crypto/fx/` | Shared motion and color components for the pill and panel |
