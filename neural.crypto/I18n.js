.pragma library
// UI language follows the process/system locale. Unsupported languages use English.
var localeOverride = ""
function localeName() { return localeOverride || (typeof Qt !== "undefined" ? Qt.locale().name : "en_US") }
function language() { var code = localeName().toLowerCase().split(/[_-]/)[0]; return ["pt","en","es","fr","de"].indexOf(code) >= 0 ? code : "en" }
function tr(source) { var lang=language(); return lang === "pt" ? source : (strings[source] ? strings[source][lang] || strings[source].en : source) }
function decimalPoint() { return typeof Qt !== "undefined" && !localeOverride ? Qt.locale().decimalPoint : (["pt","es","fr","de"].indexOf(language()) >= 0 ? "," : ".") }
function groupSeparator() { return typeof Qt !== "undefined" && !localeOverride ? Qt.locale().groupSeparator : (language() === "fr" ? "\u202f" : decimalPoint() === "," ? "." : ",") }
function inputNumber(value) { return String(value).replace(".",decimalPoint()) }
function number(value, decimals) {
  if (typeof Qt !== "undefined" && !localeOverride) return Number(value).toLocaleString(Qt.locale(), "f", decimals)
  var locale=localeName().replace("_","-"); if (locale === "C") locale="en-US"
  return Number(value).toLocaleString(locale,{minimumFractionDigits:decimals,maximumFractionDigits:decimals})
}
function parseNumber(text) {
  var s=String(text === undefined || text === null ? "" : text).trim()
  if (!s) return NaN
  var scientific=s.replace(decimalPoint(),".")
  if (/^\d+(?:\.\d+)?e[+-]?\d+$/i.test(scientific)) { var n=Number(scientific); return isFinite(n) && n>0 ? n : NaN }
  if (typeof Qt !== "undefined" && !localeOverride) {
    try { var parsed=Number.fromLocaleString(Qt.locale(),s); return isFinite(parsed) && parsed>0 ? parsed : NaN } catch(e) { return NaN }
  }
  var decimal=decimalPoint(), group=groupSeparator()
  if (language()==="fr") s=s.replace(/[ \u00a0\u202f]/g,group)
  var parts=s.split(decimal)
  if (parts.length>2) return NaN
  var groups=parts[0].split(group)
  if (groups.length>1 && (!/^\d{1,3}$/.test(groups[0]) || !groups.slice(1).every(function(g){return /^\d{3}$/.test(g)}))) return NaN
  var normalized=groups.join("")+(parts.length===2 ? "."+parts[1] : "")
  if (!/^\d+(?:\.\d+)?$/.test(normalized)) return NaN
  var result=Number(normalized);return isFinite(result)&&result>0 ? result : NaN
}
function chartDate(ms, monthly) {
  var d=new Date(ms)
  if (typeof Qt !== "undefined") return d.toLocaleDateString(Qt.locale(), monthly ? "MMM yy" : (localeName()==="en_US" || localeName()==="C" ? "MMM dd" : "dd MMM"))
  return d.toLocaleDateString(localeName().replace("_","-"),monthly ? {month:"short",year:"2-digit"} : {day:"2-digit",month:"short"})
}

var strings = {
  "consultando…": {
    "en": "loading…",
    "es": "consultando…",
    "fr": "chargement…",
    "de": "lädt…"
  },
  "cache · há ": {
    "en": "cached · age ",
    "es": "caché · hace ",
    "fr": "cache · âge ",
    "de": "Cache · Alter "
  },
  "limite da API": {
    "en": "API rate limit",
    "es": "límite de la API",
    "fr": "limite API",
    "de": "API-Limit"
  },
  "erro na API": {
    "en": "API error",
    "es": "error de API",
    "fr": "erreur API",
    "de": "API-Fehler"
  },
  "sem conexão": {
    "en": "offline",
    "es": "sin conexión",
    "fr": "hors ligne",
    "de": "offline"
  },
  "atualizado há ": {
    "en": "updated: ",
    "es": "actualizado hace ",
    "fr": "mise à jour : ",
    "de": "aktualisiert: "
  },
  "aguardando": {
    "en": "waiting",
    "es": "esperando",
    "fr": "en attente",
    "de": "wartet"
  },
  "limite do provedor · nova tentativa em ": {
    "en": "provider limit · retry in ",
    "es": "límite del proveedor · reintento en ",
    "fr": "limite fournisseur · nouvel essai dans ",
    "de": "Anbieterlimit · neuer Versuch in "
  },
  "sem conexão · último preço há ": {
    "en": "offline · last price age ",
    "es": "sin conexión · último precio hace ",
    "fr": "hors ligne · dernier prix : ",
    "de": "offline · letzter Preis vor "
  },
  "sem resposta do provedor · r tenta de novo": {
    "en": "provider unavailable · R to retry",
    "es": "proveedor sin respuesta · R reintenta",
    "fr": "fournisseur indisponible · R pour réessayer",
    "de": "Anbieter nicht erreichbar · R wiederholen"
  },
  "fonte: ": {
    "en": "source: ",
    "es": "fuente: ",
    "fr": "source : ",
    "de": "Quelle: "
  },
  " · cotação antiga · há ": {
    "en": " · stale quote · age ",
    "es": " · cotización antigua · hace ",
    "fr": " · ancien prix · âge ",
    "de": " · alter Kurs · Alter "
  },
  "Cotação indisponível": {
    "en": "Price unavailable",
    "es": "Cotización no disponible",
    "fr": "Prix indisponible",
    "de": "Kurs nicht verfügbar"
  },
  "Consultando ": {
    "en": "Loading ",
    "es": "Consultando ",
    "fr": "Chargement de ",
    "de": "Lade "
  },
  "voltar para a lista (esc)": {
    "en": "back to list (Esc)",
    "es": "volver a la lista (Esc)",
    "fr": "retour à la liste (Échap)",
    "de": "zur Liste (Esc)"
  },
  "Moedas": {
    "en": "Coins",
    "es": "Monedas",
    "fr": "Cryptos",
    "de": "Coins"
  },
  "Alertas · ": {
    "en": "Alerts · ",
    "es": "Alertas · ",
    "fr": "Alertes · ",
    "de": "Alarme · "
  },
  "Minha ordem": {
    "en": "My order",
    "es": "Mi orden",
    "fr": "Mon ordre",
    "de": "Meine Reihenfolge"
  },
  "Variação 24h": {
    "en": "24h change",
    "es": "Cambio 24h",
    "fr": "Variation 24h",
    "de": "24h-Änderung"
  },
  "Nome": {
    "en": "Name",
    "es": "Nombre",
    "fr": "Nom",
    "de": "Name"
  },
  "Nenhum alerta. Use o sino de uma moeda para criar.": {
    "en": "No alerts. Use a coin’s bell to create one.",
    "es": "Sin alertas. Usa la campana de una moneda.",
    "fr": "Aucune alerte. Utilisez la cloche d’une crypto.",
    "de": "Keine Alarme. Zum Erstellen die Glocke eines Coins nutzen."
  },
  "Sem resposta do provedor.": {
    "en": "Provider unavailable.",
    "es": "Proveedor sin respuesta.",
    "fr": "Fournisseur indisponible.",
    "de": "Anbieter nicht erreichbar."
  },
  "Consultando cotações…": {
    "en": "Loading prices…",
    "es": "Consultando precios…",
    "fr": "Chargement des prix…",
    "de": "Kurse werden geladen…"
  },
  "deixar de fixar na barra": {
    "en": "unpin from bar",
    "es": "quitar de la barra",
    "fr": "détacher de la barre",
    "de": "von der Leiste lösen"
  },
  "fixar na barra": {
    "en": "pin to bar",
    "es": "fijar en la barra",
    "fr": "épingler à la barre",
    "de": "an Leiste anheften"
  },
  "faltam ": {
    "en": "remaining ",
    "es": "faltan ",
    "fr": "reste ",
    "de": "noch "
  },
  "Alvo a ": {
    "en": "Target: ",
    "es": "Objetivo: ",
    "fr": "Objectif : ",
    "de": "Ziel: "
  },
  " para o alvo": {
    "en": " to target",
    "es": " para el objetivo",
    "fr": " avant l’objectif",
    "de": " bis zum Ziel"
  },
  "criar alerta de preço": {
    "en": "create price alert",
    "es": "crear alerta de precio",
    "fr": "créer une alerte de prix",
    "de": "Preisalarm erstellen"
  },
  "Editar — ": {
    "en": "Edit — ",
    "es": "Editar — ",
    "fr": "Modifier — ",
    "de": "Bearbeiten — "
  },
  "Alerta — ": {
    "en": "Alert — ",
    "es": "Alerta — ",
    "fr": "Alerte — ",
    "de": "Alarm — "
  },
  "agora ": {
    "en": "now ",
    "es": "ahora ",
    "fr": "actuellement ",
    "de": "jetzt "
  },
  "sem cotação": {
    "en": "no quote",
    "es": "sin cotización",
    "fr": "aucun prix",
    "de": "kein Kurs"
  },
  "▲ Acima": {
    "en": "▲ Above",
    "es": "▲ Por encima",
    "fr": "▲ Au-dessus",
    "de": "▲ Oberhalb"
  },
  "▼ Abaixo": {
    "en": "▼ Below",
    "es": "▼ Por debajo",
    "fr": "▼ En dessous",
    "de": "▼ Unterhalb"
  },
  "Moeda: ": {
    "en": "Currency: ",
    "es": "Divisa: ",
    "fr": "Devise : ",
    "de": "Währung: "
  },
  " · ativo após salvar": {
    "en": " · active after saving",
    "es": " · activo al guardar",
    "fr": " · actif après enregistrement",
    "de": " · nach Speichern aktiv"
  },
  " · permanece pausado": {
    "en": " · remains paused",
    "es": " · sigue en pausa",
    "fr": " · reste en pause",
    "de": " · bleibt pausiert"
  },
  "preço alvo (ex: 350.000,00)": {
    "en": "target price (e.g. 350,000.00)",
    "es": "precio objetivo (ej.: 350.000,00)",
    "fr": "prix cible (ex. : 350 000,00)",
    "de": "Zielpreis (z. B. 350.000,00)"
  },
  "cotação indisponível no momento": {
    "en": "price currently unavailable",
    "es": "cotización no disponible ahora",
    "fr": "prix actuellement indisponible",
    "de": "Kurs derzeit nicht verfügbar"
  },
  "digite o preço alvo": {
    "en": "enter target price",
    "es": "introduce el precio objetivo",
    "fr": "saisissez le prix cible",
    "de": "Zielpreis eingeben"
  },
  "▲ avisa quando o preço subir para ": {
    "en": "▲ alert when price rises to ",
    "es": "▲ avisa al subir el precio a ",
    "fr": "▲ alerte si le prix atteint ",
    "de": "▲ Alarm bei Anstieg auf "
  },
  "▼ avisa quando o preço cair para ": {
    "en": "▼ alert when price falls to ",
    "es": "▼ avisa al bajar el precio a ",
    "fr": "▼ alerte si le prix descend à ",
    "de": "▼ Alarm bei Rückgang auf "
  },
  "Cancelar": {
    "en": "Cancel",
    "es": "Cancelar",
    "fr": "Annuler",
    "de": "Abbrechen"
  },
  "Salvar alterações": {
    "en": "Save changes",
    "es": "Guardar cambios",
    "fr": "Enregistrer",
    "de": "Änderungen speichern"
  },
  "Criar alerta": {
    "en": "Create alert",
    "es": "Crear alerta",
    "fr": "Créer l’alerte",
    "de": "Alarm erstellen"
  },
  "ALERTAS": {
    "en": "ALERTS",
    "es": "ALERTAS",
    "fr": "ALERTES",
    "de": "ALARME"
  },
  " ativo": {
    "en": " active",
    "es": " activo",
    "fr": " actif",
    "de": " aktiv"
  },
  "pausado": {
    "en": "paused",
    "es": "en pausa",
    "fr": "en pause",
    "de": "pausiert"
  },
  "há ": {
    "en": "age ",
    "es": "hace ",
    "fr": "âge : ",
    "de": "vor "
  },
  " em ": {
    "en": " at ",
    "es": " a ",
    "fr": " à ",
    "de": " bei "
  },
  "disparou ": {
    "en": "triggered ",
    "es": "activada ",
    "fr": "déclenchée ",
    "de": "ausgelöst "
  },
  "pausar alerta": {
    "en": "pause alert",
    "es": "pausar alerta",
    "fr": "mettre en pause",
    "de": "Alarm pausieren"
  },
  "armar de novo": {
    "en": "rearm alert",
    "es": "reactivar alerta",
    "fr": "réactiver l’alerte",
    "de": "Alarm erneut aktivieren"
  },
  "retomar alerta": {
    "en": "resume alert",
    "es": "reanudar alerta",
    "fr": "reprendre l’alerte",
    "de": "Alarm fortsetzen"
  },
  "editar alerta": {
    "en": "edit alert",
    "es": "editar alerta",
    "fr": "modifier l’alerte",
    "de": "Alarm bearbeiten"
  },
  "remover alerta": {
    "en": "remove alert",
    "es": "eliminar alerta",
    "fr": "supprimer l’alerte",
    "de": "Alarm entfernen"
  },
  "Fechar ajustes e busca ▴": {
    "en": "Close settings and search ▴",
    "es": "Cerrar ajustes y búsqueda ▴",
    "fr": "Fermer réglages et recherche ▴",
    "de": "Einstellungen und Suche schließen ▴"
  },
  "+ Moedas e ajustes ▾": {
    "en": "+ Coins and settings ▾",
    "es": "+ Monedas y ajustes ▾",
    "fr": "+ Cryptos et réglages ▾",
    "de": "+ Coins und Einstellungen ▾"
  },
  "adicionar moeda (ex: dash, aero, solana)": {
    "en": "add coin (e.g. dash, aero, solana)",
    "es": "añadir moneda (ej.: dash, aero, solana)",
    "fr": "ajouter une crypto (ex. : dash, aero, solana)",
    "de": "Coin hinzufügen (z. B. dash, aero, solana)"
  },
  "buscando…": {
    "en": "searching…",
    "es": "buscando…",
    "fr": "recherche…",
    "de": "Suche…"
  },
  "nenhuma moeda encontrada · busca online indisponível": {
    "en": "no coins found · online search unavailable",
    "es": "sin resultados · búsqueda en línea no disponible",
    "fr": "aucun résultat · recherche en ligne indisponible",
    "de": "keine Coins gefunden · Onlinesuche nicht verfügbar"
  },
  "nenhuma moeda encontrada": {
    "en": "no coins found",
    "es": "sin resultados",
    "fr": "aucun résultat",
    "de": "keine Coins gefunden"
  },
  "Cotação principal": {
    "en": "Primary currency",
    "es": "Divisa principal",
    "fr": "Devise principale",
    "de": "Hauptwährung"
  },
  "Cotação secundária": {
    "en": "Secondary currency",
    "es": "Divisa secundaria",
    "fr": "Devise secondaire",
    "de": "Zweitwährung"
  },
  "Nenhuma": {
    "en": "None",
    "es": "Ninguna",
    "fr": "Aucune",
    "de": "Keine"
  },
  "Conversão via USDT/CoinGecko. O gráfico mantém o par original e a moeda indicada.": {
    "en": "Converted via USDT/CoinGecko. The chart keeps its original pair and labelled currency.",
    "es": "Conversión vía USDT/CoinGecko. El gráfico conserva el par original y la divisa indicada.",
    "fr": "Conversion via USDT/CoinGecko. Le graphique conserve sa paire et sa devise d’origine.",
    "de": "Umrechnung über USDT/CoinGecko. Der Chart behält das ursprüngliche Paar und die angegebene Währung."
  },
  "Alternar moedas na barra": {
    "en": "Cycle coins in the bar",
    "es": "Alternar monedas en la barra",
    "fr": "Alterner les cryptos dans la barre",
    "de": "Coins in der Leiste wechseln"
  },
  "Barra: preço + variação 24h": {
    "en": "Bar: price + 24h change",
    "es": "Barra: precio + cambio 24h",
    "fr": "Barre : prix + variation 24h",
    "de": "Leiste: Preis + 24h-Änderung"
  },
  "Barra: preço compacto": {
    "en": "Bar: compact price",
    "es": "Barra: precio compacto",
    "fr": "Barre : prix compact",
    "de": "Leiste: kompakter Preis"
  },
  "↑↓ escolher · Enter gráfico · N alerta · P fixar · Tab alertas": {
    "en": "↑↓ select · Enter chart · N alert · P pin · Tab alerts",
    "es": "↑↓ elegir · Enter gráfico · N alerta · P fijar · Tab alertas",
    "fr": "↑↓ choisir · Entrée graphique · N alerte · P épingler · Tab alertes",
    "de": "↑↓ wählen · Enter Chart · N Alarm · P anheften · Tab Alarme"
  },
  "↑↓ escolher · Enter editar · P pausar/retomar · Tab moedas": {
    "en": "↑↓ select · Enter edit · P pause/resume · Tab coins",
    "es": "↑↓ elegir · Enter editar · P pausar/reanudar · Tab monedas",
    "fr": "↑↓ choisir · Entrée modifier · P pause/reprise · Tab cryptos",
    "de": "↑↓ wählen · Enter bearbeiten · P Pause/Fortsetzen · Tab Coins"
  },
  "câmbio indisponível": {
    "en": "conversion unavailable",
    "es": "conversión no disponible",
    "fr": "conversion indisponible",
    "de": "Umrechnung nicht verfügbar"
  },
  "câmbio desatualizado": {
    "en": "outdated conversion rate",
    "es": "tipo de cambio desactualizado",
    "fr": "taux de conversion ancien",
    "de": "veralteter Wechselkurs"
  },
  "Binance × CoinGecko · convertido": {
    "en": "Binance × CoinGecko · converted",
    "es": "Binance × CoinGecko · convertido",
    "fr": "Binance × CoinGecko · converti",
    "de": "Binance × CoinGecko · umgerechnet"
  },
  "limite da API · nova tentativa em 2 min": {
    "en": "API limit · retry in 2 min",
    "es": "límite API · reintento en 2 min",
    "fr": "limite API · nouvel essai dans 2 min",
    "de": "API-Limit · neuer Versuch in 2 Min."
  },
  "erro na API (HTTP ": {
    "en": "API error (HTTP ",
    "es": "error de API (HTTP ",
    "fr": "erreur API (HTTP ",
    "de": "API-Fehler (HTTP "
  },
  "sem dados para ": {
    "en": "no data for ",
    "es": "sin datos para ",
    "fr": "aucune donnée pour ",
    "de": "keine Daten für "
  },
  "falha ao ler os dados": {
    "en": "could not read data",
    "es": "no se pudieron leer los datos",
    "fr": "lecture des données impossible",
    "de": "Daten konnten nicht gelesen werden"
  },
  "PERÍODO": {
    "en": "PERIOD",
    "es": "PERÍODO",
    "fr": "PÉRIODE",
    "de": "ZEITRAUM"
  },
  "1 dia": {
    "en": "1 day",
    "es": "1 día",
    "fr": "1 jour",
    "de": "1 Tag"
  },
  "1 semana": {
    "en": "1 week",
    "es": "1 semana",
    "fr": "1 semaine",
    "de": "1 Woche"
  },
  "1 mês": {
    "en": "1 month",
    "es": "1 mes",
    "fr": "1 mois",
    "de": "1 Monat"
  },
  "Restaurar zoom": {
    "en": "Reset zoom",
    "es": "Restablecer zoom",
    "fr": "Réinitialiser le zoom",
    "de": "Zoom zurücksetzen"
  },
  "INTERVALO DE CADA CANDLE": {
    "en": "CANDLE INTERVAL",
    "es": "INTERVALO DE VELAS",
    "fr": "INTERVALLE DES BOUGIES",
    "de": "KERZENINTERVALL"
  },
  " no período": {
    "en": " over period",
    "es": " en el período",
    "fr": " sur la période",
    "de": " im Zeitraum"
  },
  "ab ": {
    "en": "O ",
    "es": "A ",
    "fr": "O ",
    "de": "O "
  },
  " · máx ": {
    "en": " · H ",
    "es": " · Máx ",
    "fr": " · H ",
    "de": " · H "
  },
  " · mín ": {
    "en": " · L ",
    "es": " · Mín ",
    "fr": " · B ",
    "de": " · T "
  },
  " · fec ": {
    "en": " · C ",
    "es": " · C ",
    "fr": " · F ",
    "de": " · S "
  },
  " · vol ": {
    "en": " · Vol ",
    "es": " · Vol ",
    "fr": " · Vol ",
    "de": " · Vol "
  },
  "carregando ": {
    "en": "loading ",
    "es": "cargando ",
    "fr": "chargement de ",
    "de": "lade "
  },
  "sem dados": {
    "en": "no data",
    "es": "sin datos",
    "fr": "aucune donnée",
    "de": "keine Daten"
  },
  "par indisponível": {
    "en": "pair unavailable",
    "es": "par no disponible",
    "fr": "paire indisponible",
    "de": "Paar nicht verfügbar"
  },
  " · há ": {
    "en": " · age ",
    "es": " · hace ",
    "fr": " · âge ",
    "de": " · Alter "
  },
  " velas": {
    "en": " candles",
    "es": " velas",
    "fr": " bougies",
    "de": " Kerzen"
  },
  " · carregando histórico…": {
    "en": " · loading history…",
    "es": " · cargando historial…",
    "fr": " · chargement de l’historique…",
    "de": " · Verlauf wird geladen…"
  },
  " · alvos em outra moeda não são sobrepostos": {
    "en": " · targets in other currencies are not overlaid",
    "es": " · no se superponen objetivos en otra divisa",
    "fr": " · les objectifs dans une autre devise ne sont pas superposés",
    "de": " · Ziele in anderen Währungen werden nicht eingeblendet"
  },
  " · scroll amplia · arraste para ver o histórico": {
    "en": " · scroll to zoom · drag for history",
    "es": " · rueda para ampliar · arrastra para ver historial",
    "fr": " · molette pour zoomer · glisser pour l’historique",
    "de": " · scrollen zum Zoomen · ziehen für Verlauf"
  },
  "indisponível": {
    "en": "unavailable",
    "es": "no disponible",
    "fr": "indisponible",
    "de": "nicht verfügbar"
  },
  " · dados de ": {
    "en": " · data at ",
    "es": " · datos de ",
    "fr": " · données à ",
    "de": " · Daten von "
  },
  "histórico indisponível": {
    "en": "history unavailable",
    "es": "historial no disponible",
    "fr": "historique indisponible",
    "de": "Verlauf nicht verfügbar"
  },
  "limite": {
    "en": "rate limit",
    "es": "límite",
    "fr": "limite",
    "de": "Limit"
  },
  "subiu para": {
    "en": "rose to",
    "es": "subió a",
    "fr": "est monté à",
    "de": "stieg auf"
  },
  "caiu para": {
    "en": "fell to",
    "es": "bajó a",
    "fr": "est descendu à",
    "de": "fiel auf"
  },
  "Preço ": {
    "en": "Price ",
    "es": "Precio ",
    "fr": "Prix ",
    "de": "Preis "
  },
  " · alerta ": {
    "en": " · alert ",
    "es": " · alerta ",
    "fr": " · alerte ",
    "de": " · Alarm "
  },
  " · direto": {
    "en": " · direct",
    "es": " · directo",
    "fr": " · direct",
    "de": " · direkt"
  },
  " · convertido": {
    "en": " · converted",
    "es": " · convertido",
    "fr": " · converti",
    "de": " · umgerechnet"
  },
  "alvo atingido": {
    "en": "target reached",
    "es": "objetivo alcanzado",
    "fr": "objectif atteint",
    "de": "Ziel erreicht"
  },
  "1sem": {
    "en": "1w",
    "es": "1sem",
    "fr": "1sem",
    "de": "1W"
  },
  "1mês": {
    "en": "1mo",
    "es": "1mes",
    "fr": "1mois",
    "de": "1Mo"
  },
  " · r atualiza · u moeda · c cicla": {
    "en": " · R refresh · U currency · C cycle",
    "es": " · R actualizar · U divisa · C alternar",
    "fr": " · R actualiser · U devise · C alterner",
    "de": " · R aktualisieren · U Währung · C wechseln"
  },
  "Moedas de cotação": {
    "en": "Quote currencies",
    "es": "Divisas de cotización",
    "fr": "Devises de cotation",
    "de": "Kurswährungen"
  },
  " · agora ": {
    "en": " · now ",
    "es": " · ahora ",
    "fr": " · actuellement ",
    "de": " · jetzt "
  },
  "alvo ": {
    "en": "target ",
    "es": "objetivo ",
    "fr": "objectif ",
    "de": "Ziel "
  },
  " · candle ": {
    "en": " · candle ",
    "es": " · vela ",
    "fr": " · bougie ",
    "de": " · Kerze "
  },
  "Não foi possível ler os alertas; arquivo preservado": {
    "en": "Could not read the alerts; the file was left untouched",
    "es": "No se pudieron leer las alertas; el archivo se conservó",
    "fr": "Impossible de lire les alertes ; le fichier est conservé",
    "de": "Alarme konnten nicht gelesen werden; Datei unverändert"
  },
  "Não foi possível salvar os alertas": {
    "en": "Could not save the alerts",
    "es": "No se pudieron guardar las alertas",
    "fr": "Impossible d’enregistrer les alertes",
    "de": "Alarme konnten nicht gespeichert werden"
  },
  "Alertas conferidos a cada 30 s; um pico entre duas consultas pode passar despercebido.": {
    "en": "Alerts are checked every 30 s; a spike between two checks can be missed.",
    "es": "Las alertas se revisan cada 30 s; un pico entre dos consultas puede pasar inadvertido.",
    "fr": "Alertes vérifiées toutes les 30 s ; un pic entre deux vérifications peut passer inaperçu.",
    "de": "Alarme werden alle 30 s geprüft; eine Spitze zwischen zwei Abfragen kann unbemerkt bleiben."
  }
}
