import type { LegChamber, LegSeat } from '../types/legislature'
import type { SummaryCandidate, SummaryContest } from '../types/data'

export type Bucket = 'DEM' | 'REP' | 'OTH'
export type SeatStatus = 'won' | 'leading' | 'holder' | 'holdover' | 'pending' | 'untracked' | 'vacant'

export const bucketOf = (party: string | null | undefined): Bucket | null =>
  party === 'REP' ? 'REP' : party === 'DEM' ? 'DEM' : party ? 'OTH' : null

export interface SeatState {
  seat: LegSeat
  chamber: 'house' | 'senate'
  contest: SummaryContest | null
  status: SeatStatus
  bucket: Bucket | null
  leader: SummaryCandidate | null
  margin: number
  flip: boolean
  pctCounted: number
  called: boolean
}

export function seatStates(chamber: 'house' | 'senate', data: LegChamber, byId: Map<string, SummaryContest>, started: boolean): SeatState[] {
  return data.seats_list.map((seat) => {
    const contest = seat.contest_id ? (byId.get(seat.contest_id) ?? null) : null
    const base = { seat, chamber, contest, leader: null, margin: 0, flip: false, pctCounted: contest?.reporting.pct_expected ?? 0, called: false }
    const holder = bucketOf(seat.holder_party)
    if (!seat.up) return { ...base, status: 'holdover' as const, bucket: holder }
    if (started) {
      if (!contest) return { ...base, status: 'untracked' as const, bucket: null }
      const ranked = [...contest.candidates].sort((a, b) => b.votes - a.votes)
      if (contest.total_votes <= 0 || ranked[0].votes <= 0) return { ...base, status: 'pending' as const, bucket: null }
      const winner = contest.candidates.find((c) => c.winner) ?? null
      const lead = winner ?? ranked[0]
      const bucket = bucketOf(lead.party ?? 'OTH')
      return {
        ...base, leader: lead, bucket, status: winner ? ('won' as const) : ('leading' as const), called: !!winner,
        margin: lead.pct - (ranked.find((c) => c.candidate_id !== lead.candidate_id)?.pct ?? 0),
        flip: !!holder && !!bucket && holder !== bucket,
      }
    }
    if (seat.vacant) return { ...base, status: 'vacant' as const, bucket: null }
    return { ...base, status: 'holder' as const, bucket: holder }
  })
}

export interface Tally {
  DEM: Record<SeatStatus, number>
  REP: Record<SeatStatus, number>
  OTH: Record<SeatStatus, number>
  none: Record<SeatStatus, number>
  total: Record<Bucket, number>
  flips: { from: Bucket; to: Bucket; district: number }[]
}

const zero = (): Record<SeatStatus, number> => ({ won: 0, leading: 0, holder: 0, holdover: 0, pending: 0, untracked: 0, vacant: 0 })

export function tally(states: SeatState[]): Tally {
  const t: Tally = { DEM: zero(), REP: zero(), OTH: zero(), none: zero(), total: { DEM: 0, REP: 0, OTH: 0 }, flips: [] }
  for (const s of states) {
    t[s.bucket ?? 'none'][s.status]++
    if (s.bucket) t.total[s.bucket]++
    const holder = bucketOf(s.seat.holder_party)
    if (s.flip && holder && s.bucket) t.flips.push({ from: holder, to: s.bucket, district: s.seat.district })
  }
  return t
}

const GROUP: Record<string, number> = { DEM: 0, OTH: 1, none: 2, REP: 3 }
// Within a party the most certain seats sit at the outer edge, so the undecided middle shrinks as results come in.
const OUTER_FIRST: Record<SeatStatus, number> = { holdover: 0, won: 1, leading: 2, holder: 2, pending: 3, untracked: 3, vacant: 4 }

/** Seats in left-to-right bar order: D, other, undecided, R. */
export function barOrder(states: SeatState[]): SeatState[] {
  const key = (s: SeatState): number => {
    const g = GROUP[s.bucket ?? 'none']
    const w = OUTER_FIRST[s.status]
    return g * 100 + (g === 3 ? 10 - w : w)
  }
  return [...states].sort((a, b) => key(a) - key(b) || a.seat.district - b.seat.district)
}

export const seatLabel = (chamber: 'house' | 'senate'): string => (chamber === 'house' ? 'Utah House' : 'Utah Senate')
