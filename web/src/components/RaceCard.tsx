import { Link } from 'react-router-dom'
import type { CandidateBio, ContestAverage, NeedleContest, Ratings, SummaryContest } from '../types/data'
import { candidateColors } from '../lib/parties'
import { consensus } from '../lib/ratings'
import { fmtInt, fmtPct } from '../lib/format'
import { lastName } from '../lib/results'
import { PartyChip } from './PartyChip'
import { RatingChip } from './RatingChip'
import { ReportingMeter } from './ReportingMeter'
import { ResultsBar } from './ResultsBar'
import { ForecastSummary } from './ForecastSummary'

interface Props {
  contestId: string
  title: string
  subtitle?: string
  roster?: CandidateBio[]
  avg?: ContestAverage
  live?: SummaryContest
  showLive: boolean
  ratings?: Ratings | null
  needle?: NeedleContest
}

/** Results area shows counted votes only; before the count it lists candidates with an explicit empty state. */
export function RaceCard({ contestId, title, subtitle, roster = [], avg, live, showLive, ratings, needle }: Props) {
  const cons = consensus(ratings, contestId)
  const useLive = showLive && live && live.total_votes > 0

  type Row = { id: string; name: string; party: string | null; incumbent: boolean; value: number | null; winner?: boolean }
  const preRank = (r: Row) => [-(needle?.prob[r.id] ?? -1), r.party === 'REP' || r.party === 'DEM' ? 0 : 1]
  const rows: Row[] = useLive && live
    ? live.candidates
        .map((c) => ({ id: c.candidate_id, name: c.name, party: c.party, incumbent: c.incumbent, value: c.pct, winner: c.winner }))
        .sort((a, b) => (b.value ?? 0) - (a.value ?? 0))
    : (roster.length ? roster : (avg?.latest ?? []).map((l) => ({ candidate_id: l.candidate_id, name: l.name, party: l.party, incumbent: false })))
      .map((c) => ({ id: c.candidate_id, name: c.name, party: c.party, incumbent: !!c.incumbent, value: null }))
      // Ballot order would bury the major-party nominees behind minor candidates before any votes exist.
      .sort((a, b) => {
        const [pa, ma] = preRank(a)
        const [pb, mb] = preRank(b)
        return pa - pb || ma - mb
      })
  const colors = candidateColors(rows.map((r) => ({ candidate_id: r.id, party: r.party })))
  const top = rows.slice(0, 2)
  const others = rows.slice(2)
  const barItems = useLive ? rows.map((r) => ({ candidate_id: r.id, name: r.name, party: r.party, pct: r.value ?? 0 })) : []
  const forecastCands = live?.candidates ?? rows.map((r) => ({ candidate_id: r.id, name: r.name, party: r.party }))
  const showForecast = needle && !showLive

  return (
    <article className={`race-card${useLive ? ' is-live' : ''}`}>
      <header className="race-card-head">
        <div>
          <h3><Link to={`/race/${contestId}`}>{title}</Link></h3>
          {subtitle && <div className="race-sub">{subtitle}</div>}
        </div>
        {cons && <div className="race-cons"><span className="label">Consensus</span><RatingChip label={cons.label} scale={ratings?.scale} compact /></div>}
      </header>
      {useLive && <div className="results-label">Votes counted so far</div>}
      <div className="race-card-rows">
        {top.map((r) => (
          <div key={r.id} className={`rc-row${r.winner ? ' winner' : ''}`}>
            <span className="cand-swatch" style={{ background: colors[r.id] }} aria-hidden />
            <span className="rc-name">{r.name}{r.incumbent ? ' (i)' : ''} <PartyChip party={r.party} id={r.id} /></span>
            {useLive && <span className="rc-val">{r.value == null ? '–' : fmtPct(r.value)}</span>}
          </div>
        ))}
        {others.length > 0 && (
          <div className="rc-others">
            {others.map((r) => <span key={r.id}>{lastName(r.name)}{useLive && r.value != null ? ` ${fmtPct(r.value, 0)}` : ''}</span>)}
          </div>
        )}
      </div>
      {useLive ? <ResultsBar items={barItems} /> : <div className="results-empty">No votes counted yet. Polls close 8 p.m. MT Nov 3.</div>}
      {showForecast && <ForecastSummary needle={needle} candidates={forecastCands} title={title} compact />}
      {useLive && live ? (
        <div className="rc-foot">
          <ReportingMeter pct={live.reporting.pct_expected} lo={live.reporting.pct_expected_lo} hi={live.reporting.pct_expected_hi} size="sm" />
          <span className="rc-foot-text">Est. expected vote counted · {fmtInt(live.total_votes)} votes</span>
        </div>
      ) : (
        <div className="rc-foot rc-foot-text">
          {avg ? <Link className="poll-link" to={`/polls?contest=${contestId}`}>Polls →</Link> : 'No polls yet'}
        </div>
      )}
    </article>
  )
}
