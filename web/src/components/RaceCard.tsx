import { Link } from 'react-router-dom'
import type { AverageLatest, CandidateBio, ContestAverage, Ratings, SummaryContest } from '../types/data'
import { candidateColors } from '../lib/parties'
import { consensus } from '../lib/ratings'
import { fmtInt, fmtPct, fmtPts } from '../lib/format'
import { lastName } from '../lib/results'
import { PartyChip } from './PartyChip'
import { RatingChip } from './RatingChip'
import { ReportingMeter } from './ReportingMeter'
import { ResultsBar } from './ResultsBar'

interface Props {
  contestId: string
  title: string
  subtitle?: string
  roster?: CandidateBio[]
  avg?: ContestAverage
  live?: SummaryContest
  showLive: boolean
  ratings?: Ratings | null
}

export function RaceCard({ contestId, title, subtitle, roster = [], avg, live, showLive, ratings }: Props) {
  const cons = consensus(ratings, contestId)
  const useLive = showLive && live && live.total_votes > 0

  type Row = { id: string; name: string; party: string | null; incumbent: boolean; value: number | null; winner?: boolean }
  let rows: Row[]
  if (useLive && live) {
    rows = live.candidates.map((c) => ({ id: c.candidate_id, name: c.name, party: c.party, incumbent: c.incumbent, value: c.pct, winner: c.winner }))
  } else {
    const latest = new Map<string, AverageLatest>((avg?.latest ?? []).map((l) => [l.candidate_id, l]))
    const base = roster.length ? roster : (avg?.latest ?? []).map((l) => ({ candidate_id: l.candidate_id, name: l.name, party: l.party, incumbent: false }))
    rows = base.map((c) => ({ id: c.candidate_id, name: c.name, party: c.party, incumbent: !!c.incumbent, value: latest.has(c.candidate_id) ? latest.get(c.candidate_id)!.avg / 100 : null }))
      .sort((a, b) => (b.value ?? -1) - (a.value ?? -1))
  }
  const colors = candidateColors(rows.map((r) => ({ candidate_id: r.id, party: r.party })))
  const top = rows.slice(0, 2)
  const others = rows.slice(2)
  const barItems = rows.filter((r) => r.value != null).map((r) => ({ candidate_id: r.id, name: r.name, party: r.party, pct: r.value ?? 0 }))

  return (
    <article className="race-card">
      <header className="race-card-head">
        <div>
          <h3><Link to={`/race/${contestId}`}>{title}</Link></h3>
          {subtitle && <div className="race-sub">{subtitle}</div>}
        </div>
        {cons && <div className="race-cons"><span className="label">Consensus</span><RatingChip label={cons.label} scale={ratings?.scale} compact /></div>}
      </header>
      <div className="race-card-rows">
        {top.map((r) => (
          <div key={r.id} className={`rc-row${r.winner ? ' winner' : ''}`}>
            <span className="cand-swatch" style={{ background: colors[r.id] }} aria-hidden />
            <span className="rc-name">{r.name}{r.incumbent ? ' (i)' : ''} <PartyChip party={r.party} id={r.id} /></span>
            <span className="rc-val">{r.value == null ? '–' : useLive ? fmtPct(r.value) : fmtPts(r.value * 100)}</span>
          </div>
        ))}
        {others.length > 0 && (
          <div className="rc-others">
            {others.map((r) => <span key={r.id}>{lastName(r.name)} {r.value == null ? '' : useLive ? fmtPct(r.value, 0) : fmtPts(r.value * 100)}</span>)}
          </div>
        )}
      </div>
      {barItems.length > 0 && <ResultsBar items={barItems} muted={!useLive} />}
      {useLive && live ? (
        <div className="rc-foot">
          <ReportingMeter pct={live.reporting.pct_expected} lo={live.reporting.pct_expected_lo} hi={live.reporting.pct_expected_hi} size="sm" />
          <span className="rc-foot-text">Est. expected vote counted · {fmtInt(live.total_votes)} votes{live.call ? ' · Called' : ''}</span>
        </div>
      ) : (
        <div className="rc-foot rc-foot-text">
          {avg ? `Poll average · ${avg.n_polls === 1 ? 'based on 1 poll' : `${avg.n_polls} polls`}` : 'No polls yet'}
        </div>
      )}
    </article>
  )
}
