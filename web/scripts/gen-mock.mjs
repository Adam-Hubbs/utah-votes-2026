// Generates realistic MOCK data following ARCHITECTURE.md into public/mock/data.
// Real boundaries for counties; precincts are Voronoi cells clipped to counties (fake).
// Run: node scripts/gen-mock.mjs
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import * as topojson from 'topojson-client'
import { topology } from 'topojson-server'
import { presimplify, simplify, quantile } from 'topojson-simplify'
import { Delaunay } from 'd3-delaunay'
import { geoContains, geoBounds } from 'd3-geo'
import polygonClipping from 'polygon-clipping'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const OUT = path.resolve(__dirname, '../public/mock/data')
const CACHE = path.join(os.tmpdir(), 'us-atlas-counties-10m.json')

const write = (rel, obj, pretty = false) => {
  const f = path.join(OUT, rel)
  fs.mkdirSync(path.dirname(f), { recursive: true })
  fs.writeFileSync(f, pretty ? JSON.stringify(obj, null, 1) : JSON.stringify(obj))
}

function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
let rnd = mulberry32(2026)
const seed = (s) => { rnd = mulberry32(s) }
const normal = () => Math.sqrt(-2 * Math.log(rnd() + 1e-12)) * Math.cos(2 * Math.PI * rnd())
const logit = (p) => Math.log(p / (1 - p))
const sig = (x) => 1 / (1 + Math.exp(-x))
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

// ---------- counties ----------
const COUNTIES = [
  ['Beaver', 7072, 82, 'BVR'], ['Box Elder', 57666, 82, 'BXE'], ['Cache', 133154, 64, 'CCH'], ['Carbon', 20412, 72, 'CRB'],
  ['Daggett', 935, 71, 'DGT'], ['Davis', 362679, 64, 'DVS'], ['Duchesne', 20429, 85, 'DCH'], ['Emery', 9825, 87, 'EMR'],
  ['Garfield', 5083, 79, 'GRF'], ['Grand', 9669, 39, 'GRD'], ['Iron', 57289, 74, 'IRN'], ['Juab', 11786, 83, 'JUB'],
  ['Kane', 7667, 70, 'KNE'], ['Millard', 12975, 86, 'MLD'], ['Morgan', 12295, 82, 'MRG'], ['Piute', 1438, 87, 'PTE'],
  ['Rich', 2510, 83, 'RCH'], ['Salt Lake', 1185238, 44, 'SLC'], ['San Juan', 14518, 46, 'SNJ'], ['Sanpete', 28437, 79, 'SPT'],
  ['Sevier', 21522, 85, 'SVR'], ['Summit', 42357, 36, 'SMT'], ['Tooele', 72698, 72, 'TOO'], ['Uintah', 35620, 83, 'UNT'],
  ['Utah', 659399, 66, 'UTH'], ['Wasatch', 34788, 56, 'WSC'], ['Washington', 180279, 72, 'WSH'], ['Wayne', 2486, 74, 'WYN'],
  ['Weber', 262223, 62, 'WEB'],
].map(([name, pop, r24, code], i) => ({ name, pop, r24: r24 / 100, code, fips: String(49001 + 2 * i), nbr: String(i + 1).padStart(2, '0') }))
const byFips = Object.fromEntries(COUNTIES.map((c) => [c.fips, c]))

async function loadAtlas() {
  if (!fs.existsSync(CACHE)) {
    const r = await fetch('https://cdn.jsdelivr.net/npm/us-atlas@3/counties-10m.json')
    if (!r.ok) throw new Error('atlas download failed')
    fs.writeFileSync(CACHE, Buffer.from(await r.arrayBuffer()))
  }
  return JSON.parse(fs.readFileSync(CACHE, 'utf8'))
}

// ---------- district assignment (fake) ----------
function cd2026Of(c, lon, lat) {
  const n = c.name
  if (n === 'Salt Lake') return lat > 40.64 ? 1 : 4
  if (['Box Elder', 'Cache', 'Rich', 'Weber', 'Morgan', 'Davis', 'Summit', 'Daggett'].includes(n)) return 2
  if (n === 'Utah') return lat >= 40.12 ? 4 : 3
  if (['Juab', 'Millard', 'Tooele'].includes(n)) return 4
  return 3
}
function cd2022Of(c, lon, lat) {
  const n = c.name
  if (['Box Elder', 'Cache', 'Rich', 'Weber', 'Morgan', 'Summit', 'Daggett', 'Uintah', 'Duchesne'].includes(n)) return 1
  if (n === 'Davis') return lat >= 40.9 ? 1 : 2
  if (n === 'Salt Lake') return lon < -111.93 ? 2 : lat > 40.7 ? 4 : 4
  if (['Tooele', 'Washington', 'Iron', 'Beaver', 'Millard', 'Juab', 'Garfield', 'Kane', 'Piute'].includes(n)) return 2
  if (n === 'Utah') return lon < -111.85 ? 4 : 3
  return 3
}

// ---------- geometry ----------
const ringArea = (r) => {
  let a = 0
  for (let i = 0; i < r.length - 1; i++) a += r[i][0] * r[i + 1][1] - r[i + 1][0] * r[i][1]
  return a / 2
}
const polyArea = (mp) => mp.reduce((s, poly) => s + poly.reduce((t, ring, i) => t + (i === 0 ? 1 : -1) * Math.abs(ringArea(ring)), 0), 0)
function centroid(mp) {
  let sx = 0, sy = 0, sa = 0
  for (const poly of mp) {
    const ring = poly[0]
    for (let i = 0; i < ring.length - 1; i++) {
      const cr = ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1]
      sa += cr; sx += (ring[i][0] + ring[i + 1][0]) * cr; sy += (ring[i][1] + ring[i + 1][1]) * cr
    }
  }
  return sa === 0 ? mp[0][0][0] : [sx / (3 * sa), sy / (3 * sa)]
}
const round5 = (mp) => mp.map((p) => p.map((r) => r.map(([x, y]) => [Math.round(x * 1e4) / 1e4, Math.round(y * 1e4) / 1e4])))

function makePrecinctCells(feat, nTarget, rng) {
  const geom = feat.geometry
  const coords = geom.type === 'Polygon' ? [geom.coordinates] : geom.coordinates
  const [[x0, y0], [x1, y1]] = geoBounds(feat)
  let pts = []
  let guard = 0
  while (pts.length < nTarget && guard++ < nTarget * 400) {
    const p = [x0 + (x1 - x0) * rng(), y0 + (y1 - y0) * rng()]
    if (geoContains(feat, p)) pts.push(p)
  }
  if (nTarget <= 1 || pts.length < 2) return [{ poly: coords, centroid: centroid(coords) }]
  // one Lloyd step for friendlier shapes
  const pad = 0.05
  const v = Delaunay.from(pts).voronoi([x0 - pad, y0 - pad, x1 + pad, y1 + pad])
  pts = pts.map((p, i) => {
    const cell = v.cellPolygon(i)
    if (!cell) return p
    const c = centroid([[cell]])
    return geoContains(feat, c) ? c : p
  })
  const vor = Delaunay.from(pts).voronoi([x0 - pad, y0 - pad, x1 + pad, y1 + pad])
  const cells = []
  for (let i = 0; i < pts.length; i++) {
    const cell = vor.cellPolygon(i)
    if (!cell) continue
    let clipped
    try { clipped = polygonClipping.intersection([cell], coords) } catch { continue }
    if (!clipped.length) continue
    clipped = round5(clipped)
    if (Math.abs(polyArea(clipped)) < 1e-7) continue
    cells.push({ poly: clipped, centroid: centroid(clipped) })
  }
  return cells
}

function buildPrecincts(countyFeats, vintage, cdOf, perPrecinct, seedNo) {
  seed(seedNo)
  const out = []
  for (const f of countyFeats) {
    const c = byFips[f.properties.fips]
    const n = Math.max(c.pop > 3000 ? 6 : 3, Math.round(c.pop / perPrecinct))
    const cells = makePrecinctCells(f, n, rnd)
    const areas = cells.map((x) => Math.abs(polyArea(x.poly)) ** 0.5 * Math.exp(0.35 * normal()))
    const tot = areas.reduce((a, b) => a + b, 0)
    cells.forEach((cell, i) => {
      const [lon, lat] = cell.centroid
      const num = String(i + 1).padStart(3, '0')
      const name = `${c.code}${num}`
      out.push({
        id: `${c.fips}-${name}`, name, county: c, lon, lat, poly: cell.poly, share: areas[i] / tot,
        cd: cdOf(c, lon, lat),
        // smooth spatial field plus noise so maps show realistic partisan texture
        z: 0.45 * Math.sin(lon * 31 + lat * 17) + 0.35 * Math.cos(lon * 13 - lat * 29) + 0.45 * normal(),
      })
    })
  }
  return { vintage, precincts: out }
}

function unionBy(precs, key) {
  const groups = new Map()
  for (const p of precs) {
    if (!groups.has(p.cd)) groups.set(p.cd, [])
    groups.get(p.cd).push(p.poly)
  }
  return [...groups.entries()].sort((a, b) => a[0] - b[0]).map(([d, polys]) => {
    let u
    try {
      u = polygonClipping.union(...polys.map((p) => p))
    } catch {
      u = polys.flat()
    }
    return { type: 'Feature', properties: { [key]: d }, geometry: { type: 'MultiPolygon', coordinates: u } }
  })
}

// d3-geo uses spherical winding: exterior rings must be clockwise.
const rewind = (mp) => mp.map((poly) => poly.map((ring, i) => {
  const cw = ringArea(ring) < 0
  return (i === 0 ? cw : !cw) ? ring : [...ring].reverse()
}))
const topo = (name, feats, q = 1e5) => {
  feats = feats.map((f) => ({ ...f, geometry: { type: 'MultiPolygon', coordinates: rewind(f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates) } }))
  let t = topology({ [name]: { type: 'FeatureCollection', features: feats } }, q)
  t = presimplify(t)
  t = simplify(t, quantile(t, 0.35))
  return t
}

// ---------- result simulation ----------
function pickCands(list) {
  return list.map(([name, party, inc = false, target]) => ({ candidate_id: slug(name), name, party, incumbent: inc, target }))
}

// Allocates candidate shares across precincts so the district totals hit the targets.
function makeAllocator(precs, cands, k, zOf) {
  const R = cands.find((c) => c.party === 'REP' || c.role === 'a')
  const D = cands.find((c) => c.party === 'DEM' || c.role === 'b')
  const others = cands.filter((c) => c !== R && c !== D)
  const oTot = others.reduce((s, c) => s + c.target, 0)
  const twoR = R.target / (R.target + D.target)
  const w = precs.map((p) => p.weight)
  const wsum = w.reduce((a, b) => a + b, 0)
  const zbar = precs.reduce((s, p, i) => s + w[i] * zOf(p), 0) / wsum
  const oj = precs.map(() => others.map(() => Math.exp(0.25 * normal())))
  const rShare = (c0, p) => sig(c0 + k * (zOf(p) - zbar))
  let lo = -6, hi = 6
  for (let i = 0; i < 50; i++) {
    const mid = (lo + hi) / 2
    const t = precs.reduce((s, p, j) => s + w[j] * rShare(mid, p), 0) / wsum
    if (t > twoR) hi = mid; else lo = mid
  }
  const c0 = (lo + hi) / 2
  return (p, idx, shift = 0) => {
    const oRaw = others.map((c, j) => c.target * oj[idx][j])
    const oSum = oRaw.reduce((a, b) => a + b, 0) || 1
    const oFrac = oTot * (oSum / (oTot || 1)) / 1
    const rest = 1 - Math.min(oFrac, 0.5)
    const r = rShare(c0 + shift, p)
    const shares = {}
    shares[R.candidate_id] = rest * r
    shares[D.candidate_id] = rest * (1 - r)
    others.forEach((c, j) => { shares[c.candidate_id] = (oRaw[j] / oSum) * Math.min(oFrac, 0.5) })
    return shares
  }
}

const sumVotes = (rows, ids) => {
  const v = Object.fromEntries(ids.map((i) => [i, 0]))
  for (const r of rows) for (const i of ids) v[i] += r.votes[i] ?? 0
  return v
}

function buildContest({ id, name, office, district, type, cands, precs, k, zOf, measureLean }) {
  const ids = cands.map((c) => c.candidate_id)
  const alloc = makeAllocator(precs, cands, k, zOf)
  return { id, name, office, district, type, cands, ids, precs, alloc, measureLean }
}

function simulate(contest, { ballotsOf, countedFrac, shiftEarly = 0 }) {
  const { precs, ids, alloc } = contest
  const rows = precs.map((p, idx) => {
    const exp = ballotsOf(p)
    const f = countedFrac(p)
    const counted = Math.round(exp * f)
    const sh = alloc(p, idx, shiftEarly * (1 - f))
    const sum = Object.values(sh).reduce((a, b) => a + b, 0)
    const votes = {}
    let tot = 0
    for (const i of ids) { votes[i] = Math.round(counted * 0.96 * (sh[i] / sum)); tot += votes[i] }
    return { p, votes, total: tot, counted, exp }
  })
  return rows
}

function aggregateCounties(rows, ids, countyBallots) {
  const m = new Map()
  for (const r of rows) {
    const f = r.p.county.fips
    if (!m.has(f)) m.set(f, { fips: f, name: r.p.county.name, votes: Object.fromEntries(ids.map((i) => [i, 0])), total: 0, counted: 0, exp: 0 })
    const e = m.get(f)
    for (const i of ids) e.votes[i] += r.votes[i]
    e.total += r.total; e.counted += r.counted; e.exp += r.exp
  }
  return [...m.values()].sort((a, b) => a.fips.localeCompare(b.fips)).map((e) => {
    const pct = e.exp ? e.counted / e.exp : 0
    const w = e.counted === 0 ? 0 : Math.min(0.18, 0.012 + 0.16 * (1 - pct) * (1 - pct))
    return {
      fips: e.fips, name: e.name, votes: e.votes, total: e.total, ballots_counted: e.counted, expected_ballots: e.exp,
      pct_expected: +pct.toFixed(4), pct_expected_lo: +Math.max(0, pct - w).toFixed(4), pct_expected_hi: +Math.min(1, pct + w).toFixed(4),
    }
  })
}

function summarize(contest, countyRows, call) {
  const ids = contest.ids
  const votes = Object.fromEntries(ids.map((i) => [i, 0]))
  let counted = 0, exp = 0, lo = 0, hi = 0
  for (const c of countyRows) {
    for (const i of ids) votes[i] += c.votes[i]
    counted += c.ballots_counted; exp += c.expected_ballots
    lo += c.pct_expected_lo * c.expected_ballots; hi += c.pct_expected_hi * c.expected_ballots
  }
  const total = ids.reduce((s, i) => s + votes[i], 0)
  const cands = contest.cands.map((c) => ({
    candidate_id: c.candidate_id, name: c.name, party: c.party, incumbent: !!c.incumbent, votes: votes[c.candidate_id],
    pct: total ? +(votes[c.candidate_id] / total).toFixed(4) : 0,
    winner: !!call && call.candidate_id === c.candidate_id,
  })).sort((a, b) => b.votes - a.votes || a.name.localeCompare(b.name))
  return {
    contest_id: contest.id, name: contest.name, office: contest.office, district: contest.district ?? null, type: contest.type,
    featured: true, total_votes: total, candidates: cands,
    reporting: {
      counties_reporting: countyRows.filter((c) => c.ballots_counted > 0).length, counties_total: countyRows.length,
      pct_expected: exp ? +(counted / exp).toFixed(4) : 0, pct_expected_lo: exp ? +(lo / exp).toFixed(4) : 0, pct_expected_hi: exp ? +(hi / exp).toFixed(4) : 0,
    },
    call: call ?? null,
  }
}

// ---------- main ----------
const atlas = await loadAtlas()
const all = topojson.feature(atlas, atlas.objects.counties)
const countyFeats = all.features
  .filter((f) => String(f.id).startsWith('49'))
  .map((f) => ({ type: 'Feature', properties: { fips: String(f.id), name: byFips[String(f.id)].name, county_nbr: byFips[String(f.id)].nbr }, geometry: f.geometry }))
  .sort((a, b) => a.properties.fips.localeCompare(b.properties.fips))
if (countyFeats.length !== 29) throw new Error('expected 29 counties')

write('geo/counties.topo.json', topology({ counties: { type: 'FeatureCollection', features: countyFeats } }, 1e5))

console.log('building precinct vintages…')
const P26 = buildPrecincts(countyFeats, 2026, cd2026Of, 1700, 11)
const P24 = buildPrecincts(countyFeats, 2024, cd2022Of, 1800, 24)
const precFeat = (P, cdKey) => P.precincts.map((p) => ({
  type: 'Feature', properties: { precinct_id: p.id, county_fips: p.county.fips, name: p.name, [cdKey]: p.cd },
  geometry: { type: 'MultiPolygon', coordinates: p.poly },
}))
write('geo/precincts_2026.topo.json', topo('precincts', precFeat(P26, 'cd2026'), 6e4))
write('geo/precincts_2024.topo.json', topo('precincts', precFeat(P24, 'cd2022'), 6e4))
write('geo/cd2026.topo.json', topo('districts', unionBy(P26.precincts, 'district'), 1e5))
write('geo/cd2022.topo.json', topo('districts', unionBy(P24.precincts, 'district'), 1e5))
write('geo/places.json', [
  ['Salt Lake City', -111.891, 40.761, 1], ['Provo', -111.658, 40.234, 2], ['Ogden', -111.973, 41.223, 2], ['St. George', -113.584, 37.096, 2],
  ['Logan', -111.834, 41.737, 3], ['Park City', -111.498, 40.646, 3], ['Moab', -109.55, 38.573, 3], ['Cedar City', -113.061, 37.677, 3],
  ['Vernal', -109.528, 40.455, 3], ['Price', -110.81, 39.6, 4], ['Richfield', -112.084, 38.772, 4], ['Orem', -111.694, 40.297, 3],
  ['Tooele', -112.298, 40.531, 4], ['Blanding', -109.479, 37.624, 5], ['Delta', -112.577, 39.352, 5], ['Heber City', -111.413, 40.507, 5],
].map(([name, lon, lat, rank]) => ({ name, lon, lat, rank })), true)
write('geo/meta.json', { note: 'MOCK geometry. Counties from us-atlas (Census). Precincts and districts are synthetic Voronoi cells.', vintages: ['precincts_2024', 'precincts_2026', 'cd2022', 'cd2026'] }, true)

// expected ballots per precinct
const turnoutRate = { 2026: 0.355, 2024: 0.47, 2022: 0.34 }
const finishWeights = (P, yr) => {
  for (const p of P.precincts) {
    p.weight = Math.max(8, Math.round(p.county.pop * turnoutRate[yr] * p.share * (1 + 0.05 * normal())))
    p.zBase = logit(Math.min(0.97, Math.max(0.03, p.county.r24))) + p.z
  }
}
finishWeights(P26, 2026)
finishWeights(P24, 2024)
const zOf = (p) => p.zBase

// ---------- election definitions ----------
const C26 = {
  1: pickCands([['Ben McAdams', 'DEM', false, 0.62], ['Riley Owen', 'REP', false, 0.328], ['Jesse West', 'LIB', false, 0.032], ['Elias Montgomery', 'NPA', false, 0.02]]),
  2: pickCands([['Blake Moore', 'REP', true, 0.475], ['Peter Crosby', 'DEM', false, 0.42], ['Daniel Cottam', 'LIB', false, 0.036], ['Carlton Bowen', 'IAP', false, 0.029], ['Robert Moesinger', 'NPA', false, 0.04]]),
  3: pickCands([['Celeste Maloy', 'REP', true, 0.545], ['Kent Udell', 'DEM', false, 0.332], ['Michael Stoddard', 'LIB', false, 0.051], ['Cassie Easley', 'CON', false, 0.025], ['Ayden Scott', 'NPA', false, 0.024], ['Adonis Hooslyn', 'NPA', false, 0.023]]),
  4: pickCands([['Mike Kennedy', 'REP', true, 0.498], ['Jonny Larsen', 'DEM', false, 0.4], ['Steven Burt', 'NPA', false, 0.052], ['Taylor Wright', 'LIB', false, 0.05]]),
}
const norm = (c) => { const s = c.reduce((a, x) => a + x.target, 0); c.forEach((x) => (x.target /= s)); return c }
Object.values(C26).forEach(norm)

const cdRows = (P, d) => P.precincts.filter((p) => p.cd === d)

function buildSet(P, specs) {
  return specs.map((s) => {
    const precs = s.district ? cdRows(P, s.district) : P.precincts
    return buildContest({ ...s, precs, zOf })
  })
}

const specs2026 = [
  ...[1, 2, 3, 4].map((d) => ({ id: `us-house-${d}`, name: `U.S. House District ${d}`, office: 'us-house', district: d, type: 'candidate', cands: C26[d], k: 0.55 })),
  { id: 'amendment-a', name: 'Constitutional Amendment A', office: 'amendment', type: 'measure', k: 0.5,
    cands: [{ candidate_id: 'for', name: 'For', party: null, target: 0.545, role: 'a' }, { candidate_id: 'against', name: 'Against', party: null, target: 0.455, role: 'b' }] },
  { id: 'amendment-b', name: 'Constitutional Amendment B', office: 'amendment', type: 'measure', k: -0.45,
    cands: [{ candidate_id: 'for', name: 'For', party: null, target: 0.44, role: 'a' }, { candidate_id: 'against', name: 'Against', party: null, target: 0.56, role: 'b' }] },
]
const set26 = buildSet(P26, specs2026)

const specs2024 = [
  { id: 'president', name: 'President', office: 'president', type: 'candidate', k: 0.95, cands: pickCands([['Donald J. Trump', 'REP', false, 0.594], ['Kamala D. Harris', 'DEM', false, 0.378], ['Robert F. Kennedy Jr.', 'UNA', false, 0.012], ['Chase Oliver', 'LIB', false, 0.008], ['Jill Stein', 'GRN', false, 0.004], ['Other / write-in', 'OTH', false, 0.004]]) },
  { id: 'us-senate', name: 'U.S. Senate', office: 'us-senate', type: 'candidate', k: 0.95, cands: pickCands([['John Curtis', 'REP', false, 0.625], ['Caroline Gleich', 'DEM', false, 0.31], ['Carlton Bowen', 'IAP', false, 0.035], ['Daniel Cottam', 'LIB', false, 0.03]]) },
  { id: 'governor', name: 'Governor', office: 'governor', type: 'candidate', k: 0.9, cands: pickCands([['Spencer Cox', 'REP', true, 0.642], ['Brian King', 'DEM', false, 0.286], ['Robert Latham', 'LIB', false, 0.045], ['Tom Tomorrow', 'IAP', false, 0.027]]) },
  { id: 'amendment-d', name: 'Constitutional Amendment D', office: 'amendment', type: 'measure', k: 0.3, cands: [{ candidate_id: 'for', name: 'For', party: null, target: 0.39, role: 'a' }, { candidate_id: 'against', name: 'Against', party: null, target: 0.61, role: 'b' }] },
  { id: 'us-house-1', district: 1, name: 'U.S. House District 1', office: 'us-house', type: 'candidate', k: 0.8, cands: pickCands([['Blake Moore', 'REP', true, 0.66], ['Bill Campbell', 'DEM', false, 0.29], ['Daniel Cottam', 'LIB', false, 0.05]]) },
  { id: 'us-house-2', district: 2, name: 'U.S. House District 2', office: 'us-house', type: 'candidate', k: 0.8, cands: pickCands([['Celeste Maloy', 'REP', true, 0.61], ['Nathaniel Woodward', 'DEM', false, 0.33], ['Daniel Cottam', 'LIB', false, 0.06]]) },
  { id: 'us-house-3', district: 3, name: 'U.S. House District 3', office: 'us-house', type: 'candidate', k: 0.8, cands: pickCands([['Mike Kennedy', 'REP', false, 0.64], ['Glenn Wright', 'DEM', false, 0.3], ['Michael Stoddard', 'LIB', false, 0.06]]) },
  { id: 'us-house-4', district: 4, name: 'U.S. House District 4', office: 'us-house', type: 'candidate', k: 0.8, cands: pickCands([['Burgess Owens', 'REP', true, 0.6], ['Katrina Fallick', 'DEM', false, 0.36], ['Jeremy Peterson', 'UUP', false, 0.04]]) },
]
specs2024.forEach((s) => norm(s.cands))
const set24 = buildSet(P24, specs2024)

const MST = (iso) => iso
const NOW = new Date()

// ----- 2026 pre -----
const dummyPrecinctFrac = () => 0
const turnoutOf = (P, expected, regPct) => {
  const exp = P.precincts.reduce((s, p) => s + p.weight, 0)
  const reg = COUNTIES.reduce((s, c) => s + Math.round(c.pop * regPct), 0)
  return { exp, reg }
}
const { exp: exp26, reg: reg26 } = turnoutOf(P26, 0, 0.64)

function legislativeContests(election, count) {
  seed(election === 'sim' ? 77 : 78)
  const list = []
  const mk = (id, name, office, district, cands) => ({ id, name, office, district, cands, type: 'candidate' })
  const names = [['Sarah', 'Jenkins'], ['Tom', 'Alvarez'], ['Priya', 'Nair'], ['Mark', 'Eliason'], ['Jen', 'Okafor'], ['Dale', 'Hansen'], ['Rosa', 'Mendez'], ['Cal', 'Whitaker'], ['Ann', 'Pratt'], ['Luis', 'Barrera'], ['Hollis', 'Ward'], ['Mina', 'Sato']]
  for (let i = 0; i < count; i++) {
    const d = [1, 4, 9, 14, 20, 23, 31, 38, 44, 52, 60, 68][i % 12]
    const a = names[(i * 2) % names.length], b = names[(i * 2 + 5) % names.length]
    const rWins = rnd() < 0.62
    const share = rWins ? 0.52 + rnd() * 0.22 : 0.4 + rnd() * 0.08
    list.push(mk(`state-house-${d}`, `Utah House District ${d}`, 'state-house', d, [
      { candidate_id: slug(a.join(' ')), name: a.join(' '), party: 'REP', incumbent: rWins, share },
      { candidate_id: slug(b.join(' ')), name: b.join(' '), party: 'DEM', incumbent: !rWins, share: 1 - share - 0.02 },
      { candidate_id: `lib-${d}`, name: `Morgan Lee ${d}`, party: 'LIB', incumbent: false, share: 0.02 },
    ]))
  }
  for (const d of [3, 11, 17, 25]) {
    const share = 0.4 + rnd() * 0.3
    list.push(mk(`state-senate-${d}`, `Utah Senate District ${d}`, 'state-senate', d, [
      { candidate_id: `rep-ss-${d}`, name: names[d % 12].join(' '), party: 'REP', incumbent: true, share },
      { candidate_id: `dem-ss-${d}`, name: names[(d + 4) % 12].join(' '), party: 'DEM', incumbent: false, share: 1 - share },
    ]))
  }
  for (const d of [2, 6, 9]) {
    list.push(mk(`school-board-${d}`, `State Board of Education District ${d}`, 'school-board', d, [
      { candidate_id: `sb-${d}-a`, name: names[(d + 1) % 12].join(' '), party: null, incumbent: true, share: 0.56 },
      { candidate_id: `sb-${d}-b`, name: names[(d + 7) % 12].join(' '), party: null, incumbent: false, share: 0.44 },
    ]))
  }
  for (const j of ['Justice Diane Park', 'Judge Robert Hale', 'Judge Elena Ruiz', 'Judge Marcus Trent']) {
    const retain = 0.82 + rnd() * 0.1
    list.push({ id: `retention-${slug(j)}`, name: `Retention: ${j}`, office: 'retention', district: null, type: 'measure', cands: [
      { candidate_id: 'retain', name: 'Retain', party: null, incumbent: false, share: retain }, { candidate_id: 'not-retain', name: 'Do not retain', party: null, incumbent: false, share: 1 - retain }] })
  }
  return list
}

function listContestSummary(l, frac, total) {
  const votes = l.cands.map((c) => Math.round(total * c.share))
  const t = votes.reduce((a, b) => a + b, 0)
  const cands = l.cands.map((c, i) => ({ candidate_id: c.candidate_id, name: c.name, party: c.party, incumbent: !!c.incumbent, votes: votes[i], pct: t ? +(votes[i] / t).toFixed(4) : 0, winner: false }))
    .sort((a, b) => b.votes - a.votes)
  return { contest_id: l.id, name: l.name, office: l.office, district: l.district, type: l.type, featured: false, total_votes: t, candidates: cands,
    reporting: { counties_reporting: frac > 0 ? 3 : 0, counties_total: 3, pct_expected: +frac.toFixed(4), pct_expected_lo: +Math.max(0, frac - 0.08).toFixed(4), pct_expected_hi: +Math.min(1, frac + 0.08).toFixed(4) }, call: null }
}

const countedFracSim = (() => {
  const base = { 'Salt Lake': 0.74, Utah: 0.58, Davis: 0.67, Weber: 0.71, Washington: 0.49, Cache: 0.82, Tooele: 0.6, Summit: 0.77, Iron: 0.43, Wasatch: 0.66, Sanpete: 0.52, 'Box Elder': 0.55, Uintah: 0.38 }
  seed(5)
  const m = {}
  for (const c of COUNTIES) m[c.fips] = base[c.name] ?? Math.min(1, 0.3 + rnd() * 0.7)
  m['49009'] = 1; m['49031'] = 1; m['49055'] = 0.97
  return m
})()

const elections = []
const contestList = (set, extras = []) => [...set.map((c) => ({ contest_id: c.id, name: c.name, office: c.office })), ...extras.map((l) => ({ contest_id: l.id, name: l.name, office: l.office }))]
const legis = legislativeContests('sim', 12)

function writeElection({ id, name, date, status, precinctGeo, cdPlan, set, P, ctx, updated, withPrecincts, extras, turnoutExp, regd, call }) {
  const dir = `results/${id}`
  const summaries = []
  const countyAll = []
  for (const c of set) {
    const rows = simulate(c, ctx)
    const counties = aggregateCounties(rows, c.ids)
    const cl = call?.[c.id] ?? null
    summaries.push(summarize(c, counties, cl))
    if (c.office === 'president' || c.office === 'us-house' || c.office === 'amendment') countyAll.push(...counties)
    write(`${dir}/contests/${c.id}.json`, {
      contest_id: c.id, election_id: id, updated_at: updated,
      candidates: c.cands.map((x) => ({ candidate_id: x.candidate_id, name: x.name, party: x.party })),
      counties,
      precincts: withPrecincts ? rows.map((r) => ({ precinct_id: r.p.id, votes: r.votes, total: r.total })) : [],
    })
  }
  const totalCounted = Object.values(ctx.countedFrac ? {} : {}).length
  // turnout from a statewide proxy (president for 2024, else sum of house contests)
  const houses = set.filter((c) => c.office === 'us-house')
  let counted = 0
  for (const h of houses) {
    const rows = simulate(h, ctx)
    counted += rows.reduce((s, r) => s + r.counted, 0)
  }
  void totalCounted
  const pctE = turnoutExp ? counted / turnoutExp : 0
  const turnout = { ballots_counted: counted, registered: regd, expected_ballots: turnoutExp, expected_lo: Math.round(turnoutExp * 0.93), expected_hi: Math.round(turnoutExp * 1.07), pct_expected: +pctE.toFixed(4) }
  const extraSums = extras.map((l) => listContestSummary(l, status === 'pre' ? 0 : status === 'final' ? 1 : 0.62, status === 'pre' ? 0 : Math.round(turnoutExp * (status === 'final' ? 0.96 : 0.62) * 0.9)))
  const summary = {
    election_id: id, name, date, status, updated_at: updated, source: 'electionresults.utah.gov (MOCK)', precinct_geo: precinctGeo, cd_plan: cdPlan,
    turnout, contests: [...summaries, ...extraSums],
  }
  write(`${dir}/summary.json`, summary, true)
  elections.push({ election_id: id, name, date, status, precinct_geo: precinctGeo, cd_plan: cdPlan, contests: contestList(set, extras) })
  return { summaries, summary }
}

const pre = writeElection({
  id: '2026-general', name: '2026 General Election', date: '2026-11-03', status: 'pre', precinctGeo: 'precincts_2026', cdPlan: 'cd2026',
  set: set26, P: P26, ctx: { ballotsOf: (p) => p.weight, countedFrac: () => 0 }, updated: NOW.toISOString(), withPrecincts: false,
  extras: legis, turnoutExp: exp26, regd: reg26,
})
void pre

// ----- 2026 sim (live) -----
const simUpdated = NOW.toISOString()
const simCtx = { ballotsOf: (p) => p.weight, countedFrac: (p) => Math.min(1, countedFracSim[p.county.fips] * (0.75 + 0.5 * ((p.z * 1000) % 1 + 1) % 1 * 1)), shiftEarly: -0.14 }
// deterministic per-precinct jitter
seed(99)
const jit = new Map(P26.precincts.map((p) => [p.id, 0.8 + rnd() * 0.4]))
simCtx.countedFrac = (p) => Math.min(1, countedFracSim[p.county.fips] * jit.get(p.id))
const sim = writeElection({
  id: '2026-sim', name: '2026 General Election (simulated)', date: '2026-11-03', status: 'live', precinctGeo: 'precincts_2026', cdPlan: 'cd2026',
  set: set26, P: P26, ctx: simCtx, updated: simUpdated, withPrecincts: true, extras: legis, turnoutExp: exp26, regd: reg26,
  call: { 'us-house-1': { candidate_id: 'ben-mcadams', called_at: new Date(NOW.getTime() - 15 * 60000).toISOString(), by: 'manual' } },
})
elections.pop() // sim is not part of index.json

// the call also needs to flag the winner in the contest summary (done by summarize)

// ----- 2026 sim: model + timeline -----
const startT = new Date('2026-11-04T03:00:00Z').getTime()
const nSnap = 16
const times = Array.from({ length: nSnap }, (_, i) => new Date(startT + i * 9 * 60000).toISOString())
const g = (i) => 0.06 + 0.94 * (1 - Math.exp(-3.1 * (i / (nSnap - 1)))) / (1 - Math.exp(-3.1))
const timeline = { contests: {} }
for (const s of sim.summaries) {
  const ids = s.candidates.map((c) => c.candidate_id)
  timeline.contests[s.contest_id] = times.map((t, i) => {
    const gg = g(i)
    const total = Math.round(s.total_votes * gg)
    const w = s.candidates.map((c) => {
      const tilt = c.party === 'REP' || c.candidate_id === 'for' ? -0.1 : c.party === 'DEM' || c.candidate_id === 'against' ? 0.1 : 0
      return Math.max(0.0001, c.pct) * Math.exp(tilt * (1 - gg) * 1.4)
    })
    const ws = w.reduce((a, b) => a + b, 0)
    return { t, votes: Object.fromEntries(ids.map((id, j) => [id, Math.round((total * w[j]) / ws)])), total }
  })
}
write('results/2026-sim/timeline.json', timeline)

const countedSim = sim.summary.turnout.ballots_counted
const mcounties = COUNTIES.map((c) => {
  const ps = P26.precincts.filter((p) => p.county === c)
  const expc = ps.reduce((s, p) => s + p.weight, 0)
  const f = countedFracSim[c.fips]
  const counted = ps.reduce((s, p) => s + Math.round(p.weight * Math.min(1, f * jit.get(p.id))), 0)
  const pct = counted / expc
  const w = Math.min(0.18, 0.012 + 0.16 * (1 - pct) ** 2)
  return {
    fips: c.fips, registered: Math.round(c.pop * 0.64), counted, expected_median: expc, expected_lo: Math.round(expc * (1 - 0.06 - w / 3)), expected_hi: Math.round(expc * (1 + 0.06 + w / 3)),
    pct_expected: +pct.toFixed(4), pct_expected_lo: +Math.max(0, pct - w).toFixed(4), pct_expected_hi: +Math.min(1, pct + w).toFixed(4),
    source: pct > 0.995 ? 'final' : f > 0.9 ? 'reported_remaining' : 'model',
  }
})
write('results/2026-sim/model.json', {
  updated_at: simUpdated, draws: 4000,
  method: 'MOCK. Hierarchical Bayesian model of final turnout by county, using 2022/2024 turnout curves, registration, and the share of ballots already counted.',
  statewide: { counted: countedSim, expected_median: exp26, expected_lo: Math.round(exp26 * 0.94), expected_hi: Math.round(exp26 * 1.06), pct_expected: +(countedSim / exp26).toFixed(4) },
  counties: mcounties,
  history: times.map((t, i) => ({ t, counted: Math.round(countedSim * g(i)), expected_median: Math.round(exp26 * (0.9 + 0.1 * g(i))) })),
}, false)

// ----- 2024 final -----
seed(3)
const call24 = {}
for (const c of set24) {
  const rows = simulate(c, { ballotsOf: (p) => Math.round(p.weight), countedFrac: () => 1 })
  const county = aggregateCounties(rows, c.ids)
  const s = summarize(c, county, null)
  call24[c.id] = { candidate_id: s.candidates[0].candidate_id, called_at: '2024-11-06T03:00:00Z', by: 'AP' }
}
const exp24 = P24.precincts.reduce((s, p) => s + p.weight, 0)
const reg24 = COUNTIES.reduce((s, c) => s + Math.round(c.pop * 0.66), 0)
const fin24 = writeElection({
  id: '2024-general', name: '2024 General Election', date: '2024-11-05', status: 'final', precinctGeo: 'precincts_2024', cdPlan: 'cd2022',
  set: set24, P: P24, ctx: { ballotsOf: (p) => p.weight, countedFrac: () => 1 }, updated: '2024-11-20T18:00:00Z', withPrecincts: true,
  extras: [], turnoutExp: exp24, regd: reg24, call: call24,
})
// the 2024 turnout is "final": ballots == expected
const s24 = fin24.summary
s24.turnout.pct_expected = 1
write('results/2024-general/summary.json', s24, true)

// ----- 2022 (county-level only) -----
seed(222)
const C22 = [
  { id: 'us-senate', name: 'U.S. Senate', office: 'us-senate', type: 'candidate', k: 0.8, cands: pickCands([['Mike Lee', 'REP', true, 0.534], ['Evan McMullin', 'IAP', false, 0.433], ['Tommy Williams', 'LIB', false, 0.021], ['Ben McAdams Jr.', 'OTH', false, 0.012]]) },
  ...[1, 2, 3, 4].map((d) => ({ id: `us-house-${d}`, district: d, name: `U.S. House District ${d}`, office: 'us-house', type: 'candidate', k: 0.7,
    cands: pickCands([[['Blake Moore', 'Chris Stewart', 'Celeste Maloy', 'Burgess Owens'][d - 1].replace('Chris Stewart', 'Celeste Maloy'), 'REP', true, 0.64 - (d === 4 ? 0.07 : 0)], [['Rick Jones', 'Audrey Perry', 'Nathaniel Woodward', 'Darlene McDonald'][d - 1], 'DEM', false, 0.29 + (d === 4 ? 0.06 : 0)], [`Third Party ${d}`, 'LIB', false, 0.07]]) })),
]
C22.forEach((s) => norm(s.cands))
for (const s of C22) { if (s.office === 'us-senate') s.cands.find((c) => c.party === 'IAP').role = 'b' }
const P22 = { precincts: P24.precincts.map((p) => ({ ...p, weight: Math.round(p.weight * 0.72), zBase: p.zBase + 0.15 * normal() })) }
const set22 = C22.map((s) => buildContest({ ...s, precs: s.district ? P22.precincts.filter((p) => p.cd === s.district) : P22.precincts, zOf }))
writeElection({
  id: '2022-general', name: '2022 General Election', date: '2022-11-08', status: 'final', precinctGeo: null, cdPlan: 'cd2022',
  set: set22, P: P22, ctx: { ballotsOf: (p) => p.weight, countedFrac: () => 1 }, updated: '2022-11-30T18:00:00Z', withPrecincts: false, extras: [],
  turnoutExp: P22.precincts.reduce((s, p) => s + p.weight, 0), regd: COUNTIES.reduce((s, c) => s + Math.round(c.pop * 0.62), 0),
})

// ---------- results index ----------
const order = ['2026-general', '2024-general', '2022-general']
write('results/index.json', { elections: order.map((id) => elections.find((e) => e.election_id === id)) }, true)

// ---------- config ----------
write('config.json', {
  current_election: '2026-general', election_date: '2026-11-03', polls_close_utc: '2026-11-04T03:00:00Z', live_mode: 'pre',
  live_data_base: 'data/results', featured_contests: ['us-house-1', 'us-house-2', 'us-house-3', 'us-house-4', 'amendment-a', 'amendment-b'],
}, true)

// ---------- polls ----------
seed(404)
const addDays = (d, n) => new Date(new Date(d).getTime() + n * 86400000).toISOString().slice(0, 10)
const REAL = {
  1: { 'ben-mcadams': 62.7, 'riley-owen': 21.2, 'jesse-west': 4.7, 'elias-montgomery': 3.3 },
  2: { 'blake-moore': 39, 'peter-crosby': 34, 'robert-moesinger': 4.9, 'daniel-cottam': 4.9, 'carlton-bowen': 4.1 },
  3: { 'celeste-maloy': 44.5, 'kent-udell': 26.4, 'michael-stoddard': 6.5, 'cassie-easley': 2.6, 'ayden-scott': 2.8 },
  4: { 'mike-kennedy': 41.7, 'jonny-larsen': 32.9, 'steven-burt': 5.7, 'taylor-wright': 5.3 },
}
const pollsters = [
  ['Deseret News / Hinckley Institute', 'Deseret News', 'rv', 600], ['Noble Predictive Insights', null, 'lv', 480], ['Y2 Analytics', 'Salt Lake Tribune', 'lv', 700],
  ['Emerson College', 'KUTV', 'lv', 450], ['Lighthouse Research', 'Utah Debate Commission', 'rv', 515], ['Dan Jones & Associates', null, 'rv', 420],
]
const polls = []
let pid = 1
for (const d of [1, 2, 3, 4]) {
  const cands = C26[d]
  const real = REAL[d]
  const realPoll = {
    poll_id: `ut-lighthouse-${d}`, question_id: `q-ut-lighthouse-${d}`, contest_id: `us-house-${d}`, stage: 'general', pollster: 'Lighthouse Research',
    sponsor: 'Utah Debate Commission', start_date: '2026-09-08', end_date: '2026-09-10', sample_size: 515, population: 'rv', partisan: null, internal: false,
    url: null, numeric_grade: null,
    results: cands.filter((c) => real[c.candidate_id] != null).map((c) => ({ candidate_id: c.candidate_id, name: c.name, party: c.party, pct: real[c.candidate_id] })),
  }
  polls.push(realPoll)
  const n = d === 1 ? 4 : d === 2 ? 6 : 5
  for (let i = 0; i < n; i++) {
    const ps = pollsters[(i + d) % pollsters.length]
    if (ps[0] === 'Lighthouse Research' && i > 0 && false) continue
    const end = addDays('2026-10-19', -Math.round(i * (45 / n) + rnd() * 8))
    const drift = (c) => (c.party === 'DEM' ? 0.15 : c.party === 'REP' ? -0.1 : 0) * (i - n / 2)
    polls.push({
      poll_id: `mock-${pid++}`, question_id: `q-mock-${pid}`, contest_id: `us-house-${d}`, stage: 'general', pollster: ps[0], sponsor: ps[1],
      start_date: addDays(end, -2), end_date: end, sample_size: Math.round(ps[3] * (0.85 + rnd() * 0.3)), population: ps[2], partisan: null, internal: false, url: null, numeric_grade: null,
      results: cands.filter((c) => real[c.candidate_id] != null).map((c) => ({ candidate_id: c.candidate_id, name: c.name, party: c.party, pct: +Math.max(1, real[c.candidate_id] * (c.party === 'DEM' || c.party === 'REP' ? 1.08 : 1) + drift(c) + 2.2 * normal()).toFixed(1) })),
    })
  }
}
polls.push(
  { poll_id: 'mock-prim-1', question_id: 'q-prim-1', contest_id: 'us-house-1', stage: 'primary', pollster: 'Y2 Analytics', sponsor: 'Salt Lake Tribune', start_date: '2026-05-20', end_date: '2026-05-27', sample_size: 410, population: 'lv', partisan: null, internal: false, url: null, numeric_grade: null,
    results: [{ candidate_id: 'ben-mcadams', name: 'Ben McAdams', party: 'DEM', pct: 51 }, { candidate_id: 'nate-blouin', name: 'Nate Blouin', party: 'DEM', pct: 29 }] },
  { poll_id: 'mock-prim-2', question_id: 'q-prim-2', contest_id: 'us-house-3', stage: 'primary', pollster: 'Deseret News / Hinckley Institute', sponsor: 'Deseret News', start_date: '2026-05-28', end_date: '2026-06-03', sample_size: 380, population: 'lv', partisan: null, internal: false, url: null, numeric_grade: null,
    results: [{ candidate_id: 'celeste-maloy', name: 'Celeste Maloy', party: 'REP', pct: 57 }, { candidate_id: 'alex-example', name: 'Alex Example', party: 'REP', pct: 25 }] },
)
write('polls/polls.json', polls, true)

const mean = (a) => a.reduce((s, x) => s + x, 0) / a.length
const avgContests = {}
const TODAY = '2026-10-22'
for (const d of [1, 2, 3, 4]) {
  const cid = `us-house-${d}`
  const ps = polls.filter((p) => p.contest_id === cid && p.stage === 'general')
  const first = ps.map((p) => p.end_date).sort()[0]
  const candIds = ps[0].results.map((r) => r.candidate_id)
  const series = []
  for (let day = first; day <= TODAY; day = addDays(day, 3)) {
    const active = ps.filter((p) => p.end_date <= day)
    if (!active.length) continue
    const w = active.map((p) => Math.sqrt(p.sample_size) * Math.exp(-(new Date(day) - new Date(p.end_date)) / 86400000 / 21))
    const ws = w.reduce((a, b) => a + b, 0)
    const neff = active.reduce((s, p) => s + p.sample_size, 0) * 0.8
    for (const id of candIds) {
      const avg = active.reduce((s, p, i) => s + w[i] * (p.results.find((r) => r.candidate_id === id)?.pct ?? 0), 0) / ws
      const se = Math.sqrt((avg / 100) * (1 - avg / 100) / neff) * 100 * 1.96 + (active.length < 3 ? 2.5 : 1.2)
      series.push({ date: day, candidate_id: id, avg: +avg.toFixed(1), lo: +Math.max(0, avg - se).toFixed(1), hi: +(avg + se).toFixed(1) })
    }
  }
  const last = series.filter((s) => s.date === series[series.length - 1].date)
  avgContests[cid] = {
    n_polls: ps.length,
    latest: last.map((s) => ({ candidate_id: s.candidate_id, name: C26[d].find((c) => c.candidate_id === s.candidate_id).name, party: C26[d].find((c) => c.candidate_id === s.candidate_id).party, avg: s.avg, lo: s.lo, hi: s.hi })),
    series,
  }
}
// the real single-poll Lighthouse numbers are the "latest" if only one poll exists; here mocks add more polls
write('polls/averages.json', { updated_at: NOW.toISOString(), method: 'MOCK. Recency- and sample-size-weighted average with a normal-approximation band.', contests: avgContests }, true)

const gb = [], ap = []
seed(8)
let gv = 2.2, av = -12.5
for (let i = 120; i >= 0; i -= 2) {
  const date = addDays(TODAY, -i)
  gv += 0.05 * normal() + 0.012; av += 0.18 * normal()
  const D = 44.5 + gv / 2, R = 44.5 - gv / 2
  gb.push({ date, DEM: +D.toFixed(1), REP: +R.toFixed(1) })
  ap.push({ date, approve: +(42.5 + av / 6).toFixed(1), disapprove: +(54.5 - av / 6).toFixed(1) })
}
write('polls/national.json', { generic_ballot: { series: gb, latest: gb[gb.length - 1] }, approval: { series: ap, latest: ap[ap.length - 1] } }, true)

// ---------- ratings / candidates ----------
write('ratings.json', {
  updated_at: NOW.toISOString(),
  sources: [{ id: 'cook', name: 'Cook Political Report', url: 'https://www.cookpolitical.com' }, { id: 'sabato', name: "Sabato's Crystal Ball", url: 'https://centerforpolitics.org/crystalball' },
    { id: 'inside', name: 'Inside Elections', url: 'https://insideelections.com' }, { id: 'splitticket', name: 'Split Ticket', url: 'https://split-ticket.org' }],
  ratings: {
    'us-house-1': { cook: 'Solid D', sabato: 'Safe D', inside: 'Solid D', splitticket: 'Safe D' },
    'us-house-2': { cook: 'Likely R', sabato: 'Likely R', inside: 'Likely R', splitticket: 'Lean R' },
    'us-house-3': { cook: 'Solid R', sabato: 'Safe R', inside: 'Solid R', splitticket: 'Likely R' },
    'us-house-4': { cook: 'Lean R', sabato: 'Likely R', inside: 'Likely R', splitticket: 'Lean R' },
  },
  scale: ['Solid D', 'Likely D', 'Lean D', 'Toss-up', 'Lean R', 'Likely R', 'Solid R'],
}, true)
const bios = {
  'ben-mcadams': 'Former U.S. Representative and Salt Lake County mayor.',
  'blake-moore': 'Incumbent Republican representative.', 'celeste-maloy': 'Incumbent Republican representative.', 'mike-kennedy': 'Incumbent Republican representative.',
}
write('candidates.json', Object.fromEntries([1, 2, 3, 4].map((d) => [`us-house-${d}`, C26[d].map((c) => ({ candidate_id: c.candidate_id, name: c.name, party: c.party, incumbent: !!c.incumbent, bio: bios[c.candidate_id] ?? null, website: null }))])), true)

// ---------- demographics ----------
seed(61)
const ruralness = (c) => 1 - Math.min(1, Math.log10(c.pop) / 6.1)
const unitFor = (c) => {
  const r = ruralness(c)
  const hisp = Math.max(0.02, 0.09 + 0.1 * (c.name === 'Salt Lake') + 0.05 * (c.name === 'Weber') + 0.06 * normal() * 0.4 + (c.name === 'San Juan' ? 0.02 : 0))
  const white = Math.min(0.95, 1 - hisp - 0.05 - (c.name === 'San Juan' ? 0.4 : 0) - (c.name === 'Salt Lake' ? 0.03 : 0))
  const bach = Math.max(0.12, 0.38 - 0.18 * r + 0.04 * normal() + (c.name === 'Summit' ? 0.2 : 0) + (c.name === 'Utah' ? 0.03 : 0))
  const income = Math.round((78000 + 20000 * (1 - r) * 0 + (bach - 0.25) * 90000 + 6000 * normal()) / 100) * 100
  const under18 = 0.3 - 0.06 * r * 0 + (c.name === 'Utah' ? 0.04 : 0) + 0.02 * normal() - (c.name === 'Grand' ? 0.06 : 0)
  const reg = Math.round(c.pop * 0.64)
  const rep = 0.2 + 0.55 * c.r24 + 0.05 * normal() * 0.3, dem = Math.max(0.04, 0.5 * (1 - c.r24) - 0.02)
  const una = Math.max(0.1, 1 - rep - dem - 0.03)
  return {
    id: c.fips, name: c.name, population: c.pop, median_age: +(26.5 + 11 * r + (c.name === 'Utah' ? -1 : 0) + normal()).toFixed(1),
    pct_white_nh: +white.toFixed(3), pct_hispanic: +hisp.toFixed(3), pct_asian: +Math.max(0.004, 0.03 * (1 - r) + 0.004).toFixed(3), pct_black: +Math.max(0.002, 0.012 * (1 - r)).toFixed(3),
    pct_bachelors_plus: +bach.toFixed(3), median_hh_income: income, pct_under_18: +under18.toFixed(3), pct_65_plus: +(0.1 + 0.08 * r + 0.01 * normal()).toFixed(3),
    pct_urban: +Math.min(1, Math.max(0, 1 - 1.15 * r * r)).toFixed(3),
    registration: { REP: Math.round(reg * rep), DEM: Math.round(reg * dem), UNA: Math.round(reg * una), OTH: Math.round(reg * 0.03), total: reg, as_of: '2026-10-01' },
  }
}
const cUnits = COUNTIES.map(unitFor)
const wavg = (units, weights, key) => {
  const ws = weights.reduce((a, b) => a + b, 0)
  return units.reduce((s, u, i) => s + weights[i] * (u[key] ?? 0), 0) / ws
}
const agg = (id, name, shares) => {
  const units = COUNTIES.map((c) => cUnits.find((u) => u.id === c.fips))
  const w = COUNTIES.map((c) => shares[c.fips] ?? 0)
  const idx = units.map((_, i) => i).filter((i) => w[i] > 0)
  const us = idx.map((i) => units[i]), ww = idx.map((i) => w[i])
  const pop = Math.round(ww.reduce((a, b) => a + b, 0))
  const o = { id, name, population: pop }
  for (const k of ['median_age', 'pct_white_nh', 'pct_hispanic', 'pct_asian', 'pct_black', 'pct_bachelors_plus', 'median_hh_income', 'pct_under_18', 'pct_65_plus', 'pct_urban'])
    o[k] = k === 'median_hh_income' ? Math.round(wavg(us, ww, k) / 100) * 100 : +wavg(us, ww, k).toFixed(3)
  o.median_age = +wavg(us, ww, 'median_age').toFixed(1)
  const reg = (key) => Math.round(idx.reduce((s, i) => s + units[i].registration[key] * (w[i] / units[i].population), 0))
  o.registration = { REP: reg('REP'), DEM: reg('DEM'), UNA: reg('UNA'), OTH: reg('OTH'), total: reg('total'), as_of: '2026-10-01' }
  return o
}
const distShares = { 1: {}, 2: {}, 3: {}, 4: {} }
for (const p of P26.precincts) distShares[p.cd][p.county.fips] = (distShares[p.cd][p.county.fips] ?? 0) + p.share * p.county.pop
const allShares = Object.fromEntries(COUNTIES.map((c) => [c.fips, c.pop]))
write('demographics/counties.json', { source: 'MOCK (approximate ACS 2020–2024 5-year)', units: cUnits }, true)
write('demographics/cd2026.json', { source: 'MOCK (approximate ACS 2020–2024 5-year)', units: [1, 2, 3, 4].map((d) => agg(String(d), `District ${d}`, distShares[d])) }, true)
write('demographics/state.json', { source: 'MOCK (approximate ACS 2020–2024 5-year)', units: [agg('49', 'Utah', allShares)] }, true)

// ---------- history ----------
const baseline = (planKey, dists) => {
  const out = {}
  for (const d of dists) {
    out[String(d)] = []
    for (const c of set24.filter((x) => !x.district && x.office !== 'amendment')) {
      const rows = simulate(c, { ballotsOf: (p) => p.weight, countedFrac: () => 1 }).filter((r) => planKey(r.p) === d)
      const votes = sumVotes(rows, c.ids)
      const grp = { REP: 0, DEM: 0, OTH: 0 }
      for (const cd of c.cands) grp[cd.party === 'REP' ? 'REP' : cd.party === 'DEM' ? 'DEM' : 'OTH'] += votes[cd.candidate_id]
      const total = grp.REP + grp.DEM + grp.OTH
      out[String(d)].push({ election_id: '2024-general', contest_id: c.id, name: `2024 ${c.name}`, votes: grp, total, margin: +((grp.REP - grp.DEM) / total).toFixed(4) })
    }
  }
  return out
}
write('history/cd2026_baselines.json', { method: 'MOCK. 2020-block VAP-weighted precinct to district crosswalk (approximated here by centroid assignment)', districts: baseline((p) => cd2026Of(p.county, p.lon, p.lat), [1, 2, 3, 4]) }, true)
write('history/cd2022_baselines.json', { method: 'Actual 2022-2024 district lines (mock results).', districts: baseline((p) => p.cd, [1, 2, 3, 4]) }, true)

// county trends (synthetic history 2016–2024)
seed(1616)
const trendDefs = [
  [2016, 'president', 'President', 0.02, 0.58], [2018, 'us-senate', 'U.S. Senate', 0.03, 0.40], [2020, 'president', 'President', -0.01, 0.62],
  [2020, 'governor', 'Governor', 0.01, 0.62], [2022, 'us-senate', 'U.S. Senate', 0.04, 0.34], [2024, 'president', 'President', 0, 0.47],
]
const trends = {}
for (const c of COUNTIES) {
  const base = c.r24
  trends[c.fips] = trendDefs.map(([yr, cid, nm, shift]) => {
    const urban = Math.log10(c.pop) / 6
    const drift = (yr === 2016 ? -0.07 : yr === 2020 ? -0.015 : 0) * (1 - urban)
    const r = Math.min(0.95, Math.max(0.1, base + shift + drift + (c.pop > 100000 ? (2024 - yr) * -0.002 : 0) + 0.015 * normal()))
    return { election_id: `${yr}-general`, contest_id: cid, name: `${yr} ${nm}`, year: yr, margin: +(2 * r - 1).toFixed(3), turnout: +(0.5 + 0.2 * (yr % 4 === 0 ? 1 : 0) + 0.04 * normal()).toFixed(3) }
  })
}
write('history/county_trends.json', { counties: trends }, true)

const sz = (f) => (fs.statSync(path.join(OUT, f)).size / 1024).toFixed(0) + ' KB'
console.log('precincts 2026:', P26.precincts.length, 'precincts 2024:', P24.precincts.length)
for (const f of ['geo/precincts_2026.topo.json', 'geo/precincts_2024.topo.json', 'geo/cd2026.topo.json', 'geo/counties.topo.json', 'results/2026-sim/contests/us-house-1.json', 'results/2024-general/contests/president.json'])
  console.log(f, sz(f))
void MST
void dummyPrecinctFrac
void geoContains

// ---------- measures (MOCK text; not in ARCHITECTURE.md) ----------
write('measures.json', {
  'amendment-a': { title: 'Mock title: a proposed change to a state constitutional provision', summary: 'MOCK TEXT. Placeholder description of Constitutional Amendment A, standing in for the official ballot title and impartial analysis.', for_means: 'would adopt the proposed change.', against_means: 'would keep the constitution as it is.' },
  'amendment-b': { title: 'Mock title: a second proposed constitutional change', summary: 'MOCK TEXT. Placeholder description of Constitutional Amendment B, standing in for the official ballot title and impartial analysis.', for_means: 'would adopt the proposed change.', against_means: 'would keep the constitution as it is.' },
}, true)
