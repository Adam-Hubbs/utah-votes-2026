import type { NeedleContest, SummaryCandidate } from '../types/data'
import { GROUP_HEX, partyGroup, type PartyGroup } from './parties'
import { lastName } from './results'

/** Dial positions: a leader's win probability maps to t in [0,1] (0 = toss-up at the top, 1 = the end of the arc). */
const KNOTS: [number, number][] = [[0.5, 0], [0.6, 0.14], [0.75, 0.36], [0.9, 0.66], [0.99, 0.96], [1, 1]]
export const TICKS = [0.75, 0.9, 0.99]
export const BAND_EDGES = [0, 0.14, 0.36, 0.66, 1]
export const BAND_NAMES = ['Toss-up', 'Leans', 'Likely', 'Very likely']

export function probToT(p: number): number {
  const q = Math.min(1, Math.max(0.5, p))
  for (let i = 1; i < KNOTS.length; i++) {
    const [p1, t1] = KNOTS[i]
    const [p0, t0] = KNOTS[i - 1]
    if (q <= p1) return t0 + ((q - p0) / (p1 - p0)) * (t1 - t0)
  }
  return 1
}

/** Signed needle angle in degrees from straight up: negative leans to candidate a (left), positive to b (right). */
export function probAToAngle(pa: number): number {
  return pa >= 0.5 ? -90 * probToT(pa) : 90 * probToT(1 - pa)
}

const erf = (x: number): number => {
  const s = Math.sign(x)
  const a = Math.abs(x)
  const t = 1 / (1 + 0.3275911 * a)
  const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-a * a)
  return s * y
}
export const normCdf = (z: number): number => 0.5 * (1 + erf(z / Math.SQRT2))
export function normInv(p: number): number {
  let lo = -8
  let hi = 8
  for (let i = 0; i < 50; i++) {
    const mid = (lo + hi) / 2
    if (normCdf(mid) < p) lo = mid
    else hi = mid
  }
  return (lo + hi) / 2
}

/** Range of the leading-candidate-a probability implied by the 50% interval of the final margin. */
export function jitterRange(c: NeedleContest): [number, number] {
  const pa = Math.min(0.995, Math.max(0.005, c.prob[c.pair[0]] ?? 0.5))
  const sigma = (c.margin.hi90 - c.margin.lo90) / (2 * 1.645)
  if (!(sigma > 1e-4)) return [pa, pa]
  const z = normInv(pa)
  const f = (m: number) => Math.min(0.995, Math.max(0.005, normCdf(z + (m - c.margin.median) / sigma)))
  return [f(c.margin.lo50), f(c.margin.hi50)]
}

export interface Side { id: string; name: string; short: string; group: PartyGroup; color: string }

export function sideOf(id: string, cands: SummaryCandidate[], fallbackName?: string): Side {
  const c = cands.find((x) => x.candidate_id === id)
  const group = partyGroup(c?.party ?? null, id)
  const name = c?.name ?? fallbackName ?? id
  const short = group === 'FOR' || group === 'AGAINST' ? name : lastName(name)
  return { id, name, short, group, color: GROUP_HEX[group] }
}

export const signed = (n: number): string => (n > 0 ? `+${n}` : n < 0 ? `−${Math.abs(n)}` : '0')

export interface NeedleText {
  leader: Side
  trailer: Side
  pLeader: number
  pctText: string
  tossUp: boolean
  headline: string
  marginText: string
  caption: string
}

export function needleText(c: NeedleContest, cands: SummaryCandidate[], opts: { measure: boolean; title: string }): NeedleText {
  const [a, b] = c.pair
  const pa = c.prob[a] ?? 0.5
  const aLeads = pa >= 0.5
  const leader = sideOf(aLeads ? a : b, cands)
  const trailer = sideOf(aLeads ? b : a, cands)
  const pLeader = aLeads ? pa : 1 - pa
  const pctText = pLeader >= 0.99 ? '>99%' : `${Math.round(pLeader * 100)}%`
  const tossUp = pLeader < 0.6
  const verbWin = opts.measure ? (leader.group === 'FOR' ? 'passing' : 'failing') : 'winning'
  const headline = tossUp
    ? 'Toss-up'
    : opts.measure
      ? `${opts.title} has a ${pctText} chance of ${verbWin}`
      : `${leader.name} has a ${pctText} chance of ${verbWin}`

  const m = c.margin
  const lead = aLeads ? m.median : -m.median
  const lo = aLeads ? m.lo90 : -m.hi90
  const hi = aLeads ? m.hi90 : -m.lo90
  const r = (v: number) => Math.round(v * 100)
  const marginText = `Projected margin: ${leader.short} ${signed(Math.max(0, r(lead)))} (${signed(r(lo))} to ${signed(r(hi))})`
  const pre = c.stage === 'pre'
  const caption = pre
    ? 'Pre-election estimate — the needle goes live when results arrive'
    : c.stage === 'early'
      ? 'Early count — under 5% of the expected vote is in, so this is still mostly the pre-election estimate'
      : c.stage === 'final'
        ? 'Counting is complete'
        : `Based on an estimated ${Math.round(c.pct_expected * 100)}% of the expected vote counted`
  return { leader, trailer, pLeader, pctText, tossUp, headline, marginText, caption }
}
