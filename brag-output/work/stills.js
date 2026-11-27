const {chromium}=require('playwright');
(async()=>{
 const b=await chromium.launch(); const pg=await b.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:1});
 pg.on('pageerror',e=>console.log('ERR',e.message));
 await pg.goto('file://'+__dirname+'/video.html'); await pg.evaluate(()=>window.ready);
 const ts=process.argv.slice(2).map(Number);
 require('fs').mkdirSync(__dirname+'/stills',{recursive:true});
 for(const t of ts){ await pg.evaluate(t=>render(t),t); await pg.screenshot({path:`${__dirname}/stills/t${t.toFixed(3)}.png`}); }
 await b.close();
})();
