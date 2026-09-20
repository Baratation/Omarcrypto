const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const i=vm.createContext({});vm.runInContext(fs.readFileSync(`${__dirname}/../neural.crypto/I18n.js`,'utf8').replace('.pragma library',''),i);
const m=vm.createContext({I18n:i});vm.runInContext(fs.readFileSync(`${__dirname}/../neural.crypto/Model.js`,'utf8').replace('.pragma library','').replace('.import "I18n.js" as I18n',''),m);
for(const [locale,formatted,label] of [['en_US','1,234.56','Create alert'],['pt_BR','1.234,56','Criar alerta'],['es_ES','1234,56','Crear alerta'],['fr_FR','1\u202f234,56','Créer l’alerte'],['de_DE','1.234,56','Alarm erstellen']]) {
 i.localeOverride=locale;
 assert.equal(m.formatNumber(1234.56,2),formatted,locale);
 assert.equal(m.parseLocalNumber(formatted),1234.56,locale);
 assert.equal(m.parseLocalNumber(i.inputNumber(0.123456)),0.123456,locale);
 assert.equal(m.parseLocalNumber(i.inputNumber(1e-8)),1e-8,locale);
 assert.equal(i.tr('Criar alerta'),label,locale);
 if(locale!=='pt_BR') assert.ok(!m.alertDistance({price:110,dir:'above'},100).includes('para o alvo'));
 for(const key of Object.keys(i.strings)) for(const lang of ['en','es','fr','de'])assert.ok(i.strings[key][lang],key+' '+lang);
 assert.ok(Number.isNaN(m.parseLocalNumber('nonsense')));
 assert.ok(Number.isNaN(m.parseLocalNumber('-1')));
}
i.localeOverride='ja_JP';assert.equal(i.language(),'en');assert.equal(i.tr('Criar alerta'),'Create alert');
i.localeOverride='en_US';assert.equal(m.parseLocalNumber('1,234.56'),1234.56);assert.ok(Number.isNaN(m.parseLocalNumber('1,23')));
const base={bitcoin:{usd:{price:100,change:10},brl:{price:500,change:5}}};
const out=m.convertQuotes(base,{eur:{price:0.9,change:2},jpy:{price:150,change:null}},['eur','jpy','brl','gbp'],123456);
assert.equal(out.bitcoin.eur.price,90);assert.ok(Math.abs(out.bitcoin.eur.change-12.2)<1e-9);
assert.equal(out.bitcoin.jpy.price,15000);assert.equal(out.bitcoin.jpy.change,null);
assert.equal(out.bitcoin.brl.price,500);assert.equal(out.bitcoin.gbp,undefined);assert.equal(base.bitcoin.eur,undefined);
assert.equal(out.bitcoin.eur.fxAt,123456);
assert.equal(m.chartPair('bitcoin','eur').currency,'usd','never relabel USDT candles as EUR');
assert.match(m.quoteSource('binance','bitcoin','eur'),/USDT\/EUR.*CoinGecko/);
assert.equal(m.normalizedAlerts([{coin:'bitcoin',price:100,vs:'jpy',dir:'above'}])[0].vs,'jpy');
assert.equal(m.CURRENCIES.length,13);
console.log('Locale/currency: 5 languages, fallback, localized numbers/input, translation coverage, 13 currencies, FX arithmetic and truthful chart currency passed');
