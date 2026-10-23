export type PartyGroup = 'REP' | 'DEM' | 'THIRD' | 'FOR' | 'AGAINST' | 'NONE'

export const PARTY_NAMES: Record<string, string> = {
  REP: 'Republican', DEM: 'Democratic', LIB: 'Libertarian', CON: 'Constitution', IAP: 'Independent American',
  UUP: 'United Utah', GRN: 'Green', FWD: 'Forward', NPA: 'No party affiliation', UNA: 'Unaffiliated', OTH: 'Other',
}

export const PARTY_SHORT: Record<string, string> = {
  REP: 'R', DEM: 'D', LIB: 'Lib.', CON: 'Con.', IAP: 'IAP', UUP: 'UUP', GRN: 'Grn.', FWD: 'Fwd.', NPA: 'NPA', UNA: 'Unaff.', OTH: 'Oth.',
}

const FOR_IDS = new Set(['for', 'yes', 'retain'])
const AGAINST_IDS = new Set(['against', 'no', 'not-retain'])

export function partyGroup(party: string | null | undefined, candidateId?: string): PartyGroup {
  if (party === 'REP') return 'REP'
  if (party === 'DEM') return 'DEM'
  if (party) return 'THIRD'
  if (candidateId && FOR_IDS.has(candidateId)) return 'FOR'
  if (candidateId && AGAINST_IDS.has(candidateId)) return 'AGAINST'
  return 'NONE'
}

const THIRD_SHADES = ['#E3B505', '#A67C00', '#F0CB45', '#7A5C00', '#C99A00', '#D9C36A']

export const GROUP_COLOR: Record<PartyGroup, string> = {
  REP: 'var(--rep)', DEM: 'var(--dem)', THIRD: 'var(--third)', FOR: 'var(--for)', AGAINST: 'var(--against)', NONE: 'var(--ink-3)',
}

export const GROUP_HEX: Record<PartyGroup, string> = {
  REP: '#D6303A', DEM: '#2563B5', THIRD: '#E3B505', FOR: '#17808A', AGAINST: '#B5651D', NONE: '#767676',
}

interface CandLike { candidate_id: string; party: string | null }

/** Colour per candidate; several third-party candidates in one race get distinct yellows. */
export function candidateColors(cands: CandLike[]): Record<string, string> {
  let third = 0
  const out: Record<string, string> = {}
  for (const c of cands) {
    const g = partyGroup(c.party, c.candidate_id)
    out[c.candidate_id] = g === 'THIRD' ? THIRD_SHADES[third++ % THIRD_SHADES.length] : GROUP_HEX[g]
  }
  return out
}

export const partyLabel = (p: string | null | undefined): string => (p ? (PARTY_NAMES[p] ?? p) : '')
export const partyAbbr = (p: string | null | undefined): string => (p ? (PARTY_SHORT[p] ?? p) : '')
