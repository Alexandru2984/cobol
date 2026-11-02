const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || path.join(__dirname, 'browser/node_modules/playwright'));
(async () => {
  const browser = await chromium.launch({headless:true, executablePath:process.env.LEDGER_CHROMIUM || undefined,args:['--no-sandbox']});
  try {
    const page = await browser.newPage({viewport:{width:1200,height:630},deviceScaleFactor:1});
    await page.route('**/*',route=>route.abort());
    await page.setContent(fs.readFileSync(path.join(__dirname,'social-card.html'),'utf8'));
    await page.screenshot({path:path.join(__dirname,'../static/public-card.png')});
  } finally { await browser.close(); }
})();
