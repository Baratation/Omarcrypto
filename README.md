# Omarcrypto

Omarcrypto is a cryptocurrency widget for the [Omarchy](https://omarchy.org/)
Quickshell bar. It keeps the bar compact while opening a full panel for coins,
charts, alerts, and settings.

![Widget in the bar](docs/bar.png)

## Features

- Shows the ticker, a compact price, and an up/down trend arrow in the bar. The
  pill measures its current text and grows only when the value needs more room.
- Opens a watchlist with the primary price, a secondary quote, 24-hour change,
  and a sparkline for each coin.
- Displays candlesticks, volume, 1-day/1-week/1-month periods, zoom, and
  historical data.
- Creates, edits, pauses, rearms, and removes price alerts with system
  notifications.
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

CoinGecko can also be used directly for simple quotes:

```bash
omarchy bar set rafa.crypto provider coingecko
```

## Installation

Requirements: Omarchy with Quickshell, `omarchy` on `PATH`, and internet access
for price queries.

```bash
git clone https://github.com/Baratation/Omarcrypto.git
cd Omarcrypto
mkdir -p ~/.config/omarchy/plugins
cp -a rafa.crypto ~/.config/omarchy/plugins/
omarchy plugin validate ~/.config/omarchy/plugins/rafa.crypto
omarchy restart shell
```

The technical plugin ID remains `rafa.crypto` so existing Omarchy settings keep
working.

To change settings without opening the panel:

```bash
omarchy bar set rafa.crypto coins '["bitcoin","ethereum","solana"]' --json
omarchy bar set rafa.crypto vs brl
omarchy bar set rafa.crypto vs2 usd
omarchy bar set rafa.crypto rotate 8
omarchy bar set rafa.crypto pin bitcoin
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
```

## Project layout

| Path | Responsibility |
| --- | --- |
| `rafa.crypto/BarWidget.qml` | Bar pill and widget IPC |
| `rafa.crypto/Panel.qml` | State, polling, list, search, and alerts |
| `rafa.crypto/Chart.qml` | Candles, volume, zoom, and history |
| `rafa.crypto/Model.js` | Providers, conversion, catalog, and formatting |
| `rafa.crypto/I18n.js` | Locale detection, translations, and numeric input |
| `rafa.crypto/Cache.js` / `PersistentCache.qml` | Validated persistent cache |
