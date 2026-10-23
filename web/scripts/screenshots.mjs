// Screenshots every route at desktop and phone widths against a running dev/preview server.
// Usage: node scripts/screenshots.mjs [baseUrl] [outDir]
import fs from 'node:fs'
import path from 'node:path'
import { chromium } from 'playwright'

const base = process.argv[2] ?? 'http://localhost:5199/'
const out = process.argv[3] ?? '/private/tmp/claude-502/-Users-adamhubbs-local-dev-election-project/4092dd49-779b-443b-b9a0-a018e0a1357b/scratchpad/shots'
fs.mkdirSync(out, { recursive: true })

const routes = [
  ['overview', '/'],
  ['results-house1', '/results/2026-general/us-house-1'],
  ['results-house2-precinct', '/results/2026-general/us-house-2'],
  ['results-amend-a', '/results/2026-general/amendment-a'],
  ['results-legis', '/results/2026-general/state-house-1'],
  ['results-2024-president', '/results/2024-general/president'],
  ['polls', '/polls'],
  ['race-house1', '/race/us-house-1'],
  ['race-house2', '/race/us-house-2'],
  ['race-amend-b', '/race/amendment-b'],
  ['forecasts', '/forecasts'],
  ['history', '/history'],
  ['demographics', '/demographics'],
  ['methodology', '/methodology'],
]
const variants = [['pre', 'mock=1'], ['sim', 'mock=1&sim=1']]
const only = process.env.ONLY?.split(',')

const browser = await chromium.launch()
for (const [vw, w, h] of [['desktop', 1280, 900], ['phone', 390, 844]]) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: vw === 'phone' ? 2 : 1 })
  const page = await ctx.newPage()
  const errors = []
  page.on('pageerror', (e) => errors.push(String(e)))
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()) })
  for (const [vname, q] of variants) {
    for (const [name, route] of routes) {
      if (only && !only.some((o) => name.includes(o))) continue
      if (vname === 'pre' && !['overview', 'polls', 'race-house1', 'race-amend-b', 'forecasts', 'history', 'demographics', 'methodology', 'results-house1'].includes(name)) continue
      if (vname === 'sim' && ['polls', 'forecasts', 'methodology', 'demographics', 'history', 'results-2024-president'].includes(name)) continue
      await page.evaluate(() => sessionStorage.clear()).catch(() => {})
      await page.goto(`${base}?${q}#${route}`, { waitUntil: 'networkidle' })
      await page.waitForTimeout(700)
      if (route.includes('house-2') && vname === 'sim') {
        const btn = page.getByRole('button', { name: 'Precinct' })
        if (await btn.count()) { await btn.first().click(); await page.waitForTimeout(900) }
      }
      const file = path.join(out, `${vw}-${vname}-${name}.png`)
      await page.screenshot({ path: file, fullPage: true })
    }
  }
  if (errors.length) console.log(vw, 'console errors:\n' + [...new Set(errors)].slice(0, 10).join('\n'))
  await ctx.close()
}
await browser.close()
console.log('done ->', out)
