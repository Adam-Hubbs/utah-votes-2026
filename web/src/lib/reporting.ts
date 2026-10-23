import { useSite } from '../data/site'
import { useSummary } from '../data/hooks'

/** Before this many hours after the 8 p.m. close, or while the model's 90% range is wider than ROUGH_WIDTH, "% counted" is shown as a range. */
export const ROUGH_HOURS = 36
export const ROUGH_WIDTH = 0.25

export function useIsRough(lo?: number | null, hi?: number | null): boolean {
  const { config, mode, now, currentElection } = useSite()
  const summary = useSummary(currentElection)
  const wide = lo != null && hi != null && hi - lo > ROUGH_WIDTH
  // Measure from the data's own timestamp so a stale page or the simulation is judged by when the count was taken.
  const asOf = summary?.updated_at ? Date.parse(summary.updated_at) : now
  const hours = (asOf - Date.parse(config.polls_close_utc)) / 3_600_000
  return wide || (mode === 'live' && hours < ROUGH_HOURS)
}

/** "55–80%" with the ends rounded outwards to 5 points so the range never looks more exact than it is. */
export function roughRange(lo: number, hi: number): string {
  const a = Math.max(0, Math.floor((lo * 100) / 5) * 5)
  // Rounding 96% up to "100%" would suggest the count could already be complete.
  const b = Math.min(hi >= 0.995 ? 100 : 99, Math.ceil((hi * 100) / 5) * 5)
  return `${a}–${b}%`
}
