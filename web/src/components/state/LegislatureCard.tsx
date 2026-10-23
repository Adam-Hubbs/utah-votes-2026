import { Link } from 'react-router-dom'
import { useMemo } from 'react'
import { useLegislature } from '../../data/legislature'
import { useSummary } from '../../data/hooks'
import { useSite } from '../../data/site'
import { seatLabel, seatStates, tally } from '../../lib/legislature'

/** Compact Overview card: current (or live) party split in each chamber. */
export function LegislatureCard() {
  const { mode, currentElection } = useSite()
  const summary = useSummary(currentElection)
  const leg = useLegislature()
  const byId = useMemo(() => new Map((summary?.contests ?? []).map((c) => [c.contest_id, c])), [summary])
  const started = mode !== 'pre' && (summary?.contests ?? []).some((c) => c.office.startsWith('state-') && c.total_votes > 0)
  if (!leg) return null
  return (
    <article className="measure-card leg-card">
      <h3><Link to="/state">State Legislature</Link></h3>
      {(['house', 'senate'] as const).map((ch) => {
        const t = tally(seatStates(ch, leg.chambers[ch], byId, started))
        const n = (b: 'DEM' | 'REP') => t[b].won + t[b].holdover + t[b].holder + t[b].leading
        const total = leg.chambers[ch].seats
        return (
          <div key={ch} className="leg-card-row">
            <div className="leg-card-label"><span>{seatLabel(ch)}</span><span><b className="dem-text">{n('DEM')} D</b> · <b className="rep-text">{n('REP')} R</b></span></div>
            <div className="leg-card-bar" aria-hidden>
              <i className="dem" style={{ width: `${(n('DEM') / total) * 100}%` }} />
              <i className="rep" style={{ width: `${(n('REP') / total) * 100}%`, marginLeft: 'auto' }} />
            </div>
          </div>
        )
      })}
      <div className="rc-foot-text">{started ? 'Seats won, leading and not up.' : 'Current seats.'} <Link to="/state">Judges, school board and maps →</Link></div>
    </article>
  )
}
