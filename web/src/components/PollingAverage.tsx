import type { ContestAverage, Poll } from '../types/data'
import { candidateColors } from '../lib/parties'
import { fmtDay, fmtDateRange } from '../lib/format'
import { lastName } from '../lib/results'

/** Polling average drawn as hollow markers on a hatched range, never as filled bars: it is what polls say, not votes. */
export function PollingAverage({ avg, polls = [], compact = false }: { avg?: ContestAverage; polls?: Poll[]; compact?: boolean }) {
  if (!avg || !avg.latest.length) return <div className="poll-avg empty"><div className="poll-tag">Polls · not votes</div><div className="pa-meta">No polls of this race yet.</div></div>
  const colors = candidateColors(avg.latest)
  const n = avg.n_polls
  const start = polls.length ? polls.reduce((m, p) => (p.start_date < m ? p.start_date : m), polls[0].start_date) : null
  const end = polls.length ? polls.reduce((m, p) => (p.end_date > m ? p.end_date : m), polls[0].end_date) : avg.series.length ? avg.series[avg.series.length - 1].date : null
  const when = start && end ? (start === end ? `fielded ${fmtDay(end)}` : `fielded ${fmtDateRange(start, end)}`) : end ? `through ${fmtDay(end)}` : ''
  const sorted = [...avg.latest].sort((x, y) => y.avg - x.avg)
  return (
    <div className={`poll-avg${compact ? ' compact' : ''}`}>
      <div className="poll-tag">Polling average <span>· polls, not votes</span></div>
      <div className="pa-rows">
        {sorted.map((l) => (
          <div className="pa-row" key={l.candidate_id}>
            <span className="pa-name">{lastName(l.name)}</span>
            <span className="pa-track" aria-hidden>
              <i className="pa-range" style={{ left: `${l.lo}%`, width: `${Math.max(1, l.hi - l.lo)}%`, borderColor: colors[l.candidate_id] }} />
              <i className="pa-dot" style={{ left: `${l.avg}%`, borderColor: colors[l.candidate_id] }} />
            </span>
            <span className="pa-val">{Math.round(l.avg)}% <small>({Math.round(l.lo)}–{Math.round(l.hi)})</small></span>
          </div>
        ))}
      </div>
      <div className="pa-meta">{n === 1 ? 'Based on 1 poll' : `Based on ${n} polls`}{when ? `, ${when}` : ''}. Hollow marker: average. Hatched bar: uncertainty range.</div>
    </div>
  )
}
