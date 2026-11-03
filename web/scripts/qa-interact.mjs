// Interaction checks: map toggles, tooltips, sorting, selectors, live controls, state and national pages.
// Usage: node scripts/qa-interact.mjs [baseUrl] [outDir]
import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'
import { chromium } from 'playwright'

const base = process.argv[2] ?? 'http://localhost:5320/'
const out = process.argv[3] ?? path.join(os.tmpdir(), 'utah-votes-qa')
fs.mkdirSync(out, { recursive: true })
const browser = await chromium.launch()
const results = []
const check = (name, ok, extra = '') => results.push(`${ok ? 'PASS' : 'FAIL'} ${name} ${extra}`)

async function fresh(w = 1280, h = 900) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h } })
  const page = await ctx.newPage()
  const reqs = []
  page.on('request', (r) => reqs.push(r.url()))
  page.on('pageerror', (e) => results.push(`pageerror ${e}`))
  return { ctx, page, reqs }
}
const fills = (page) => page.evaluate(() => {
  const ps = [...document.querySelectorAll('.map-units path')]
  const f = ps.map((p) => p.getAttribute('fill'))
  const counts = {}
  f.forEach((x) => { counts[x] = (counts[x] ?? 0) + 1 })
  return { n: ps.length, counts }
})

for (const [label, q, route] of [['sim-2026', '?sim=1', '/results/2026-general/us-house-2'], ['2024', '', '/results/2024-general/president']]) {
  const { ctx, page, reqs } = await fresh()
  await page.goto(`${base}${q}#${route}`, { waitUntil: 'networkidle' })
  await page.waitForTimeout(500)
  check(`${label}: no precinct topo before toggle`, !reqs.some((u) => u.includes('precincts_')))
  const c = await fills(page)
  check(`${label}: county map drawn`, c.n > 0, JSON.stringify(c))
  await page.getByRole('button', { name: 'Precinct' }).first().click()
  await page.waitForTimeout(2500)
  const p = await fills(page)
  const top = Object.entries(p.counts).sort((a, b) => b[1] - a[1])[0]
  check(`${label}: precinct shapes`, p.n > 100, `n=${p.n} top fill=${top?.[0]}x${top?.[1]} distinct=${Object.keys(p.counts).length}`)
  check(`${label}: precinct mostly coloured`, top && top[1] / p.n < 0.6, JSON.stringify(Object.entries(p.counts).sort((a, b) => b[1] - a[1]).slice(0, 4)))
  await page.screenshot({ path: path.join(out, `interact-${label}-precinct.png`), fullPage: true })
  const box = await page.locator('.map-units path').nth(Math.floor(p.n / 2)).boundingBox()
  if (box) await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2)
  await page.waitForTimeout(300)
  check(`${label}: tooltip on hover`, (await page.locator('.tooltip').count()) > 0)
  await page.screenshot({ path: path.join(out, `interact-${label}-tooltip.png`) })
  await page.getByRole('button', { name: 'County' }).first().click()
  await page.waitForTimeout(500)
  check(`${label}: back to county`, (await fills(page)).n < p.n)
  await ctx.close()
}

{
  const { ctx, page } = await fresh()
  await page.goto(`${base}?sim=1#/results/2026-general/us-house-2`, { waitUntil: 'networkidle' })
  const sel = await page.locator('select').evaluateAll((s) => s.map((x) => x.options[x.selectedIndex]?.text))
  check('selectors reflect route', sel[0]?.includes('2026') && /District 2/.test(sel[1] ?? ''), JSON.stringify(sel))
  await page.locator('select').nth(1).selectOption('us-house-3')
  await page.waitForTimeout(800)
  check('contest select navigates', page.url().endsWith('us-house-3'), page.url())
  await page.locator('select').nth(0).selectOption('2022-general')
  await page.waitForTimeout(1200)
  check('election select navigates', page.url().includes('2022-general'), page.url())
  // sortable table
  await page.goto(`${base}?sim=1#/results/2026-general/us-house-2`, { waitUntil: 'networkidle' })
  const th = page.locator('.data-table th .th-btn').first()
  const firstCells = () => page.locator('.data-table tbody tr td:first-child').allInnerTexts()
  const a = await firstCells()
  await th.click(); const b = await firstCells(); await th.click(); const c = await firstCells()
  check('table sorts', JSON.stringify(a) !== JSON.stringify(b) || JSON.stringify(b) !== JSON.stringify(c), `${a[0]}|${b[0]}|${c[0]}`)
  const upd = await page.getByText(/next update in/).first().innerText().catch(() => '')
  check('refresh indicator', /next update/.test(upd), upd)
  const pause = page.getByRole('button', { name: /Pause/ }).first()
  await pause.click()
  check('pause toggles', (await page.getByRole('button', { name: /Resume|Play/ }).count()) > 0 || (await page.getByText(/paused/i).count()) > 0)
  const jit = page.getByRole('button', { name: /jitter/i }).first()
  if (await jit.count()) { const t0 = await jit.innerText(); await jit.click(); check('jitter toggles', (await jit.innerText()) !== t0, `${t0}->${await jit.innerText()}`) } else check('jitter button exists', false)
  await ctx.close()
}

for (const [name, route, q] of [['state', '/state', ''], ['state-sim', '/state', '?sim=1'], ['national', '/national', ''], ['history', '/history', ''], ['polls', '/polls', ''], ['demographics', '/demographics', '']]) {
  const { ctx, page } = await fresh()
  await page.goto(`${base}${q}#${route}`, { waitUntil: 'networkidle' })
  await page.waitForTimeout(600)
  const buttons = await page.locator('main button, .page button').evaluateAll((bs) => bs.map((b) => (b.innerText || b.getAttribute('aria-label') || '').trim()).filter(Boolean).slice(0, 40))
  results.push(`INFO ${name} buttons: ${[...new Set(buttons)].join(' | ')}`)
  const maps = await page.locator('svg[role=img]').evaluateAll((s) => s.map((x) => x.getAttribute('aria-label')))
  results.push(`INFO ${name} map aria: ${JSON.stringify(maps)}`)
  const unlabeled = await page.locator('svg:not([aria-hidden])').evaluateAll((s) => s.filter((x) => !x.getAttribute('aria-label') && !x.getAttribute('role') && x.getBoundingClientRect().width > 150).length)
  results.push(`INFO ${name} unlabeled big svgs: ${unlabeled}`)
  await ctx.close()
}
await browser.close()
console.log(results.join('\n'))
