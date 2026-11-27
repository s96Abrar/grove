const {chromium}=require('playwright');const fs=require('fs');
(async()=>{
 const b=await chromium.launch(); const pg=await b.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:1});
 await pg.goto('file://'+__dirname+'/video.html'); await pg.evaluate(()=>window.ready);
 fs.mkdirSync(__dirname+'/frames',{recursive:true});
 for(let f=0;f<630;f++){ await pg.evaluate(t=>render(t),f/30); await pg.screenshot({path:`${__dirname}/frames/f${String(f).padStart(4,'0')}.png`}); }
 await b.close(); console.log('done');
})();
