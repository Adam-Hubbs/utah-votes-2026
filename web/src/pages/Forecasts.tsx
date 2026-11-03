import { Link } from 'react-router-dom'
import { useCandidates, useNeedle, useRatings, useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { ForecastSummary } from '../components/ForecastSummary'
import { sideOf, signed, type NamedCandidate } from '../lib/needle'
import { Gate, Section } from '../components/Ui'
import { PartyChip } from '../components/PartyChip'
import { RatingChip, RatingStrip } from '../components/RatingChip'
import { SortableTable, type Column } from '../components/SortableTable'
import { consensus } from '../lib/ratings'
import { fmtDayYear, fmtPct } from '../lib/format'
import { useDocTitle } from '../lib/hooks'
import type { NeedleContest, Ratings } from '../types/data'

export function ForecastsPage() {
  useDocTitle('Forecasts')
  const ratings = useRatings()
  const { currentElection, config, mode } = useSite()
  const summary = useSummary(currentElection)
  const needle = useNeedle(currentElection)
  const roster = useCandidates()
  const nameOf = (id: string) => summary?.contests.find((c) => c.contest_id === id)?.name
    ?? id.replace('us-house-', 'U.S. House District ').replace('state-senate-', 'State Senate ').replace('state-house-', 'State House ').replace('amendment-', 'Amendment ').replace('Amendment a', 'Amendment A').replace('Amendment b', 'Amendment B')
  const candsOf = (id: string): NamedCandidate[] => {
    const fromSummary = summary?.contests.find((c) => c.contest_id === id)?.candidates
    if (fromSummary?.length) return fromSummary
    return roster?.[id] ?? []
  }
  const featured = config.featured_contests.filter((id) => needle?.contests[id])
  const others = Object.keys(needle?.contests ?? {}).filter((id) => !config.featured_contests.includes(id))
  const nameFallback = (slug: string) => slug.split('-').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')

  return (
    <div className="page">
      <header className="page-head">
        <div className="kicker">Forecasts</div>
        <h1 className="headline sm">Our forecast, and outside views</h1>
        <p className="dek">Our model’s projection of each race, followed by what expert raters and prediction markets think. None of these are election results.</p>
      </header>
      {needle && featured.length > 0 && (
        <Section title={mode === 'pre' ? 'Our forecast' : 'Projection'} dek={mode === 'pre' ? 'Based on the polling average, 2024 results in the new district and the national environment. Updated ' + fmtDayYear(needle.updated_at) + '.' : 'During and after counting this is a live projection of the final result, not the count. Pre-election forecasts are replaced as votes arrive.'}
          aside={<Link to="/methodology" className="more">Methodology →</Link>}>
          <div className="forecast-grid">
            {featured.map((id) => (
              <div className="forecast-card" key={id}>
                <h3><Link to={`/race/${id}`}>{nameOf(id)}</Link></h3>
                <ForecastSummary needle={needle.contests[id]} candidates={candsOf(id)} title={nameOf(id)} measure={id.startsWith('amendment-')} showNote={false} />
              </div>
            ))}
          </div>
        </Section>
      )}
      {needle && others.length > 0 && (
        <Section title="Legislature" dek="Win probability for the contests our model covers. Click a column to sort.">
          <LegislatureForecastTable ids={others} needle={needle.contests} nameOf={nameOf} candsOf={candsOf} nameFallback={nameFallback} />
        </Section>
      )}
      <h2 className="section-title outside-views">Outside views</h2>
      <Gate data={ratings} what="Race ratings">
        {(r) => <RatingsTable ratings={r} nameOf={nameOf} />}
      </Gate>
    </div>
  )
}

function RatingsTable({ ratings, nameOf }: { ratings: Ratings; nameOf: (id: string) => string }) {
  const ids = Object.keys(ratings.ratings)
  const rows = ids.map((id) => ({ id, cons: consensus(ratings, id) }))
  const columns: Column<{ id: string; cons: ReturnType<typeof consensus> }>[] = [
    { key: 'race', header: 'Race', className: 'nowrap', sort: (r) => r.id, render: (r) => <Link to={`/race/${r.id}`}><b>{nameOf(r.id)}</b></Link> },
    ...ratings.sources.map((s): Column<{ id: string; cons: ReturnType<typeof consensus> }> => ({
      key: s.id, header: s.url ? <a href={s.url} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>{s.name}</a> : s.name, align: 'center',
      sort: (r) => ratings.scale.findIndex((l) => l === ratings.ratings[r.id]?.[s.id]),
      render: (r) => <RatingChip label={ratings.ratings[r.id]?.[s.id]} scale={ratings.scale} />,
    })),
    { key: 'cons', header: 'Consensus', align: 'center', className: 'cons-col', sort: (r) => r.cons?.index ?? null, render: (r) => <RatingChip label={r.cons?.label} scale={ratings.scale} /> },
  ]
  const odds = ratings.forecasts
  const marketSources = [...new Set(Object.values(odds ?? {}).flatMap((v) => v.map((x) => x.source)))]
  return (
    <>
      <Section title="Race ratings" dek="How independent forecasters rate each Utah race. The consensus is the average of the sources, rounded to the nearest category.">
        <SortableTable rows={rows} columns={columns} rowKey={(r) => r.id} initialSort={{ key: 'race', dir: 'asc' }} caption="Race ratings by source" />
        <p className="note">Ratings updated {fmtDayYear(ratings.updated_at)}. Safe, Solid, Likely, Lean and Toss-up are each source’s own wording, mapped to one seven-point scale.</p>
      </Section>
      <Section title="On the scale" dek="Each dot is one source’s rating.">
        <div className="strip-list">
          {rows.map((r) => (
            <div className="strip-row" key={r.id}>
              <Link to={`/race/${r.id}`} className="strip-name">{nameOf(r.id)}</Link>
              <RatingStrip ratings={ratings.ratings[r.id]} scale={ratings.scale} sources={ratings.sources} />
            </div>
          ))}
        </div>
      </Section>
      {odds && Object.keys(odds).length > 0 && (
        <Section title="Prediction markets" dek="Implied probability of a Democratic win. Market prices, not polls or models.">
          <div className="table-wrap">
            <table className="data-table">
              <thead><tr><th>Race</th>{marketSources.map((k) => <th key={k} className="right">{k}</th>)}</tr></thead>
              <tbody>
                {Object.entries(odds).map(([id, v]) => (
                  <tr key={id}>
                    <td><Link to={`/race/${id}`}>{nameOf(id)}</Link></td>
                    {marketSources.map((k) => {
                      const m = v.find((x) => x.source === k)
                      return <td key={k} className="right num">{m ? fmtPct(m.prob_dem, 0) : '–'}</td>
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>
      )}
    </>
  )
}

interface FcRow { id: string; nc: NeedleContest }

function LegislatureForecastTable({ ids, needle, nameOf, candsOf, nameFallback }: {
  ids: string[]; needle: Record<string, NeedleContest>; nameOf: (id: string) => string; candsOf: (id: string) => NamedCandidate[]; nameFallback: (slug: string) => string
}) {
  const rows: FcRow[] = ids.map((id) => ({ id, nc: needle[id] }))
  const fav = (r: FcRow) => {
    const [a, b] = r.nc.pair
    const pa = r.nc.prob[a] ?? 0.5
    const id = pa >= 0.5 ? a : b
    const cands = candsOf(r.id)
    const side = sideOf(id, cands, nameFallback(id))
    const party = cands.find((c) => c.candidate_id === id)?.party ?? null
    return { side, party, p: Math.max(pa, 1 - pa), lead: (pa >= 0.5 ? 1 : -1) * r.nc.margin.median }
  }
  const columns: Column<FcRow>[] = [
    { key: 'race', header: 'Contest', className: 'nowrap', sort: (r) => r.id, render: (r) => <b>{nameOf(r.id)}</b> },
    { key: 'fav', header: 'Favored', sort: (r) => fav(r).side.name, render: (r) => { const f = fav(r); return <>{f.side.name} <PartyChip party={f.party} id={f.side.id} /></> } },
    { key: 'p', header: 'Chance to win', align: 'right', className: 'fc-pct', sort: (r) => fav(r).p, render: (r) => { const p = fav(r).p; return p >= 0.99 ? '>99%' : `${Math.round(p * 100)}%` } },
    { key: 'm', header: 'Projected margin', align: 'right', sort: (r) => fav(r).lead, render: (r) => `${signed(Math.round(fav(r).lead * 100))} pts` },
  ]
  return <div className="legis-forecast"><SortableTable rows={rows} columns={columns} rowKey={(r) => r.id} initialSort={{ key: 'p', dir: 'asc' }} caption="Legislative contests: our forecast" /></div>
}
