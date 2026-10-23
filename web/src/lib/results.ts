import type { ContestCandidate, CountyResult, SummaryCandidate } from '../types/data'
import { partyGroup, type PartyGroup } from './parties'

export interface Leader {
  id: string | null
  group: PartyGroup
  name: string
  margin: number // lead over second place as a share of total votes
  share: number
  second?: string
}

export function leaderOf(votes: Record<string, number>, total: number, cands: ContestCandidate[]): Leader {
  const ranked = cands.map((c) => ({ c, v: votes[c.candidate_id] ?? 0 })).sort((a, b) => b.v - a.v)
  if (!ranked.length || total <= 0 || ranked[0].v <= 0) return { id: null, group: 'NONE', name: '', margin: 0, share: 0 }
  const [a, b] = ranked
  return {
    id: a.c.candidate_id, group: partyGroup(a.c.party, a.c.candidate_id), name: a.c.name,
    margin: (a.v - (b?.v ?? 0)) / total, share: a.v / total, second: b?.c.name,
  }
}

/** Signed Republican-minus-Democratic margin (share of total); null if the race lacks one of them. */
export function repDemMargin(votes: Record<string, number>, total: number, cands: ContestCandidate[]): number | null {
  const r = cands.find((c) => c.party === 'REP')
  const d = cands.find((c) => c.party === 'DEM')
  if (!r || !d || total <= 0) return null
  return ((votes[r.candidate_id] ?? 0) - (votes[d.candidate_id] ?? 0)) / total
}

export const lastName = (name: string): string => {
  if (/^(don.t know|someone else|undecided|write-in|other)/i.test(name.trim())) return name.trim()
  const parts = name.replace(/\b(Jr\.?|Sr\.?|III|II)$/i, '').trim().split(/\s+/)
  return parts[parts.length - 1] ?? name
}

export function estRemaining(c: CountyResult): number {
  if (c.pct_expected <= 0) return c.expected_ballots
  return Math.max(0, c.expected_ballots - c.ballots_counted)
}

export const leadingCandidate = (cands: SummaryCandidate[]): SummaryCandidate | undefined =>
  [...cands].sort((a, b) => b.votes - a.votes)[0]

export const OFFICE_LABEL: Record<string, string> = {
  president: 'President', 'us-senate': 'U.S. Senate', governor: 'Governor', 'us-house': 'U.S. House', amendment: 'Constitutional Amendments',
  'state-house': 'Utah House', 'state-senate': 'Utah Senate', 'school-board': 'State School Board', retention: 'Judicial Retention',
  'attorney-general': 'Attorney General', treasurer: 'Treasurer', auditor: 'Auditor',
}
export const OFFICE_ORDER = ['president', 'us-senate', 'governor', 'us-house', 'attorney-general', 'treasurer', 'auditor', 'amendment', 'state-senate', 'state-house', 'school-board', 'retention']
export const MAPPABLE_OFFICES = new Set(['president', 'us-senate', 'governor', 'us-house', 'amendment', 'attorney-general', 'treasurer', 'auditor'])

export const marginText = (l: Leader): string => {
  const who = l.group === 'REP' ? 'R' : l.group === 'DEM' ? 'D' : lastName(l.name)
  return `${who}+${(l.margin * 100).toFixed(1)}`
}

/** Leader's margin signed so positive is Republican or For and negative is Democratic or Against; null for other leaders. */
export function signedMargin(l: Leader): number | null {
  if (!l.id) return null
  if (l.group === 'REP' || l.group === 'FOR') return l.margin
  if (l.group === 'DEM' || l.group === 'AGAINST') return -l.margin
  return null
}
