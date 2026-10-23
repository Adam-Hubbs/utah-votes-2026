import { Link } from 'react-router-dom'
import { useRatings, useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { Gate, Section } from '../components/Ui'
import { RatingChip, RatingStrip } from '../components/RatingChip'
import { SortableTable, type Column } from '../components/SortableTable'
import { consensus } from '../lib/ratings'
import { fmtDayYear, fmtPct } from '../lib/format'
import { useDocTitle } from '../lib/hooks'
import type { Ratings } from '../types/data'

export function ForecastsPage() {
  useDocTitle('Forecasts')
  const ratings = useRatings()
  const { currentElection } = useSite()
  const summary = useSummary(currentElection)
  const nameOf = (id: string) => summary?.contests.find((c) => c.contest_id === id)?.name ?? id.replace('us-house-', 'U.S. House District ')

  return (
    <div className="page">
      <header className="page-head">
        <div className="kicker">Forecasts</div>
        <h1 className="headline sm">Race ratings</h1>
        <p className="dek">How independent forecasters rate each Utah race. The consensus is the average of the sources, rounded to the nearest category.</p>
      </header>
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
      <Section>
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
