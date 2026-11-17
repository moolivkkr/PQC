const tls=require('node:tls');
const one=(port,label)=>new Promise(r=>{const s=tls.connect({host:'srv',port,rejectUnauthorized:false},()=>{r(label+': ok '+JSON.stringify(s.getEphemeralKeyInfo())+' '+s.getProtocol());s.end()});s.on('error',e=>r(label+': FAIL '+e.code));});
(async()=>{console.log('OPENSSL_CONF='+(process.env.OPENSSL_CONF||'')+' NODE_OPTIONS='+(process.env.NODE_OPTIONS||''));console.log(await one(4431,'pq-only'));console.log(await one(4432,'classical'));})();
