import type { ContestResults } from '../types/data'

/** R minus the Democrat if one is on the ballot, otherwise R minus the strongest opponent. */
export function rMargin(r: ContestResults, fips: string): number | null {
  const c = r.counties.find((x) => x.fips === fips)
  if (!c || c.total <= 0) return null
  const rep = r.candidates.find((x) => x.party === 'REP')
  if (!rep) return null
  const dem = r.candidates.find((x) => x.party === 'DEM')
  const rv = c.votes[rep.candidate_id] ?? 0
  const other = dem ? (c.votes[dem.candidate_id] ?? 0) : Math.max(0, ...r.candidates.filter((x) => x !== rep).map((x) => c.votes[x.candidate_id] ?? 0))
  return (rv - other) / c.total
}
