const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
function load(name) { const ctx=vm.createContext(name==='Model'?{I18n:load('I18n')}:{}); vm.runInContext(fs.readFileSync(`${__dirname}/../neural.crypto/${name}.js`,'utf8').replace('.pragma library','').replace('.import "I18n.js" as I18n',''),ctx);return ctx; }
const m=load('Model');
const list=a=>JSON.stringify(Array.from(a));

// Coins Binance does not trade stay out of the batch, the chart and the picker.
assert.equal(list(m.binancePairs(['bitcoin','kaspa','monero','near'],['usd','brl'])),list(['BTCUSDT','BTCBRL','NEARUSDT','NEARBRL','USDTBRL']));
assert.equal(m.chartPair('kaspa','usd'),null);
assert.equal(m.searchCatalog('kas',[],'binance').length,0);
assert.equal(m.searchCatalog('kas',[],'coingecko').length,1);

// A pair Binance answered as unknown is left out of later batches.
assert.equal(list(m.binancePairs(['bitcoin','foo'],['usd'],['FOOUSDT'])),list(['BTCUSDT']));
assert.ok(m.apiUrl('binance',['bitcoin','foo'],['usd'],['FOOUSDT']).indexOf('FOO')<0);
assert.ok(m.isUnknownSymbol(400,'{"code":-1121,"msg":"Invalid symbol."}'));
assert.ok(!m.isUnknownSymbol(200,'-1121'));
assert.ok(!m.isUnknownSymbol(429,'{"code":-1003}'));
assert.match(m.binanceTickerUrl('BTCUSDT'),/\?symbol=BTCUSDT$/);

// Delisted pairs (empty book) are dropped; a last trade outside the book
// becomes the book midpoint; a ticker without book fields keeps its last price.
const parsed=m.parseBinance(JSON.stringify([
  {symbol:'XMRUSDT',lastPrice:'118.7',bidPrice:'0',askPrice:'0',priceChangePercent:'4.7'},
  {symbol:'NEARBRL',lastPrice:'24.98',bidPrice:'25.11',askPrice:'25.19',priceChangePercent:'-5.5'},
  {symbol:'BTCUSDT',lastPrice:'84052.28',bidPrice:'84052.28',askPrice:'84052.29',priceChangePercent:'0.04'},
  {symbol:'ETHUSDT',lastPrice:'2683.1',priceChangePercent:'-0.3'}
]));
assert.equal(parsed.XMRUSDT,undefined);
assert.equal(parsed.NEARBRL.price,25.15);
assert.equal(parsed.BTCUSDT.price,84052.28);
assert.equal(parsed.ETHUSDT.price,2683.1);
assert.equal(parsed.NEARBRL.change,-5.5);

// The alerts backend imports older alerts once, notifies once per crossing and
// starts empty on a fresh install.
const {execFileSync}=require('node:child_process');
const os=require('node:os'), path=require('node:path');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'crypto-alerts-'));
const data=path.join(tmp,'data'), cfg=path.join(tmp,'cfg'), bin=path.join(tmp,'bin');
[path.join(data,'rafa-crypto'),path.join(cfg,'omarchy'),bin].forEach(d=>fs.mkdirSync(d,{recursive:true}));
fs.writeFileSync(path.join(bin,'omarchy-notification-send'),`#!/bin/sh\necho "$@" >> ${path.join(tmp,'notified')}\n`,{mode:0o755});
const alert={id:'bitcoin|usd|above|90000',coin:'bitcoin',vs:'usd',dir:'above',price:90000,armed:true,paused:false,firedAt:0,firedPrice:0};
fs.writeFileSync(path.join(data,'rafa-crypto','alerts.json'),JSON.stringify({version:1,alerts:[alert]}));
const env={...process.env,XDG_DATA_HOME:data,XDG_CONFIG_HOME:cfg,PATH:bin+':'+process.env.PATH};
const run=(...args)=>JSON.parse(execFileSync(path.join(__dirname,'../neural.crypto/alerts'),args,{env}).toString());
assert.equal(run('init').alerts[0].id,alert.id,'legacy file must be imported');
const event={id:alert.id,expected:alert,price:91000,message:{title:'Bitcoin ▲',body:'test'}};
assert.equal(run('fire',JSON.stringify({events:[event]})).alerts[0].armed,false);
assert.equal(run('fire',JSON.stringify({events:[event]})).alerts[0].firedPrice,91000);
assert.equal(fs.readFileSync(path.join(tmp,'notified'),'utf8').trim().split('\n').length,1,'one notification per crossing');
assert.equal(run('remove',JSON.stringify({id:alert.id})).alerts.length,0);
fs.rmSync(path.join(data,'omarchy'),{recursive:true}); fs.rmSync(path.join(data,'rafa-crypto'),{recursive:true});
assert.equal(run('init').alerts.length,0,'fresh install starts empty');
fs.rmSync(tmp,{recursive:true});

console.log('crypto binance: unknown and delisted pairs, book midpoint and alerts backend passed');
