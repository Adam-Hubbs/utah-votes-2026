import type { LegSeat } from '../types/legislature'
import type { NeedleContest, NeedleFile, SummaryCandidate } from '../types/data'

/** Single source of truth for how race ratings are cut; documented on the Methodology page. */
export const WIN_PROB_CUTS = { safe: 0.97, likely: 0.85, lean: 0.65 } as const
/** Fallback when no forecast exists: absolute 2024 presidential margin in the district (proportion). */
export const PRES_MARGIN_CUTS = { safe: 0.2, likely: 0.1, lean: 0.05 } as const

export type Tier = 'toss-up' | 'lean' | 'likely' | 'safe' | 'uncontested'
export const TIER_ORDER: Tier[] = ['toss-up', 'lean', 'likely', 'safe', 'uncontested']
export const TIER_NAME: Record<Tier, string> = { 'toss-up': 'Toss-up', lean: 'Lean', likely: 'Likely', safe: 'Safe', uncontested: 'Uncontested' }

export interface SeatRating {
  tier: Tier
  party: 'REP' | 'DEM' | null
  label: string
  source: 'model' | 'fundamentals' | 'uncontested'
  /** Favourite's win probability from the model, when available. */
  prob: number | null
  detail: string
  /** Ascending = most competitive first. */
  sortKey: number
}

const label = (tier: Tier, party: 'REP' | 'DEM' | null): string =>
  tier === 'toss-up' || tier === 'uncontested' || !party ? TIER_NAME[tier] : `${TIER_NAME[tier]} ${party === 'REP' ? 'R' : 'D'}`

function tierFromProb(p: number): Tier {
  if (p >= WIN_PROB_CUTS.safe) return 'safe'
  if (p >= WIN_PROB_CUTS.likely) return 'likely'
  if (p >= WIN_PROB_CUTS.lean) return 'lean'
  return 'toss-up'
}

function tierFromMargin(m: number): Tier {
  const a = Math.abs(m)
  if (a >= PRES_MARGIN_CUTS.safe) return 'safe'
  if (a >= PRES_MARGIN_CUTS.likely) return 'likely'
  if (a >= PRES_MARGIN_CUTS.lean) return 'lean'
  return 'toss-up'
}

/** Earliest forecast for the contest, so the rating stays the pre-election one once votes are counted. */
function preElectionProb(n: NeedleContest | undefined): Record<string, number> | null {
  if (!n || n.forecast === false) return null
  if (n.stage === 'pre') return n.prob
  return n.history?.[0]?.prob ?? null
}

export function rateSeat(seat: LegSeat, candidates: SummaryCandidate[] | undefined, needle: NeedleFile | null | undefined): SeatRating {
  if (seat.uncontested || (candidates && candidates.length === 1)) {
    return { tier: 'uncontested', party: null, label: 'Uncontested', source: 'uncontested', prob: null, detail: 'Only one candidate on the ballot.', sortKey: 100 }
  }
  const prob = seat.contest_id ? preElectionProb(needle?.contests[seat.contest_id]) : null
  const entries = prob ? Object.entries(prob).sort((a, b) => b[1] - a[1]) : []
  if (entries.length >= 2) {
    const [favId, p] = entries[0]
    const tier = tierFromProb(p)
    const party = candidates?.find((c) => c.candidate_id === favId)?.party
    const side = party === 'REP' || party === 'DEM' ? party : null
    return {
      tier, party: side, label: label(tier, side), source: 'model', prob: p,
      detail: 'Based on our pre-election forecast.',
      sortKey: TIER_ORDER.indexOf(tier) * 10 + (1 - p),
    }
  }
  const m = seat.pres24_margin
  if (m == null) return { tier: 'toss-up', party: null, label: 'Toss-up', source: 'fundamentals', prob: null, detail: 'No forecast or 2024 presidential margin available.', sortKey: 5 }
  const tier = tierFromMargin(m)
  const party = m > 0 ? 'REP' : 'DEM'
  return {
    tier, party: tier === 'toss-up' ? null : party, label: label(tier, party), source: 'fundamentals', prob: null,
    detail: `No forecast for this race; based on the 2024 presidential margin (${m > 0 ? 'R' : 'D'}+${Math.abs(m * 100).toFixed(0)}).`,
    sortKey: TIER_ORDER.indexOf(tier) * 10 + (1 - Math.min(1, Math.abs(m))),
  }
}

export type TierFilter = 'all' | 'competitive' | Tier
export const matchesTier = (r: SeatRating, f: TierFilter): boolean =>
  f === 'all' ? true : f === 'competitive' ? r.tier === 'toss-up' || r.tier === 'lean' : r.tier === f
