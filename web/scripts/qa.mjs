// Visits every route x mode at desktop and phone widths; logs console/network problems and phone overflow.
// Usage: node scripts/qa.mjs [baseUrl] [outDir]
import fs from 'node:fs'
import path from 'node:path'
import { chromium } from 'playwright'

const base = process.argv[2] ?? 'http://localhost:5320/'
const out = process.argv[3] ?? '/private/tmp/claude-502/-Users-adamhubbs-local-dev-election-project/4092dd49-779b-443b-b9a0-a018e0a1357b/scratchpad/qa'
fs.mkdirSync(out, { recursive: true })

const contests = ['us-house-1', 'us-house-2', 'us-house-3', 'us-house-4', 'amendment-a', 'amendment-b']
const routes = [
  ['overview', '/'],
  ['results', '/results'],
  ...contests.map((c) => [`results-2026-${c}`, `/results/2026-general/${c}`]),
  ['results-2024-president', '/results/2024-general/president'],
  ['results-2022-us-senate', '/results/2022-general/us-senate'],
  ['results-2020-president', '/results/2020-general/president'],
  ['results-2018-us-senate', '/results/2018-general/us-senate'],
  ['results-2016-president', '/results/2016-general/president'],
  ['polls', '/polls'],
  ...contests.map((c) => [`race-${c}`, `/race/${c}`]),
  ['state', '/state'], ['forecasts', '/forecasts'], ['history', '/history'],
  ['demographics', '/demographics'], ['national', '/national'], ['methodology', '/methodology'],
]
const modes = [['pre', ''], ['sim', '?sim=1']]
const only = process.env.ONLY?.split(',')

const browser = await chromium.launch()
const problems = []
for (const [vw, w, h] of [['desktop', 1280, 900], ['phone', 390, 844]]) {
  for (const [mname, q] of modes) {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: vw === 'phone' ? 2 : 1 })
    const page = await ctx.newPage()
    let tag = ''
    const log = (kind, msg) => problems.push(`${vw}/${mname}/${tag} ${kind}: ${msg}`)
    page.on('pageerror', (e) => log('pageerror', String(e)))
    page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') log('console.' + m.type(), m.text().slice(0, 200)) })
    page.on('requestfailed', (r) => log('requestfailed', r.url()))
    page.on('response', (r) => { if (r.status() >= 400) log('http' + r.status(), r.url()) })
    for (const [name, route] of routes) {
      if (only && !only.some((o) => name.includes(o))) continue
      tag = name
      await page.evaluate(() => sessionStorage.clear()).catch(() => {})
      await page.goto(`${base}${q}#${route}`, { waitUntil: 'networkidle' })
      await page.waitForTimeout(800)
      if (vw === 'phone') {
        const ov = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
        if (ov > 0) log('overflow', `+${ov}px`)
        // body has overflow-x: hidden, so look for elements poking past the viewport that are not inside a scroll container
        const wide = await page.evaluate(() => [...document.querySelectorAll('body *')].filter((el) => {
          const r = el.getBoundingClientRect()
          if (r.width === 0 || r.right <= innerWidth + 1) return false
          for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
            const o = getComputedStyle(p).overflowX
            if (o === 'auto' || o === 'scroll' || o === 'hidden') return false
          }
          return getComputedStyle(el).position !== 'fixed'
        }).slice(0, 3).map((el) => `${el.tagName}.${String(el.className).slice(0, 40)} right=${Math.round(el.getBoundingClientRect().right)}`))
        if (wide.length) log('wide', wide.join(' | '))
      }
      const errText = await page.evaluate(() => /NaN|undefined|\[object|Infinity/.test(document.body.innerText) ? (document.body.innerText.match(/.{0,30}(NaN|undefined|\[object|Infinity).{0,30}/)?.[0]) : null)
      if (errText) log('badtext', errText.replace(/\n/g, ' '))
      await page.screenshot({ path: path.join(out, `${vw}-${mname}-${name}.png`), fullPage: true })
    }
    await ctx.close()
  }
}
await browser.close()
const uniq = [...new Set(problems)]
console.log(uniq.length ? uniq.join('\n') : 'no problems')
