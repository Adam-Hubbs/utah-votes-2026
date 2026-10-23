import { useMemo } from 'react'
import { Link, useParams } from 'react-router-dom'
import type { Feature, Geometry } from 'geojson'
import { useAverages, useBaselines, useCandidates, useDemographics, useGeo, useMeasures, usePolls, useRatings, useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { ContestExplorer } from '../components/ContestExplorer'
import { Gate, Section, Unavailable } from '../components/Ui'
import { PollTracker } from '../components/PollTracker'
import { PartyChip } from '../components/PartyChip'
import { RatingChip, RatingStrip } from '../components/RatingChip'
import { ChoroplethMap } from '../components/ChoroplethMap'
import { DemoCompare } from '../components/DemoCompare'
import { candidateColors } from '../lib/parties'
import { consensus } from '../lib/ratings'
import { fmtInt, fmtMargin } from '../lib/format'
import { useDocTitle } from '../lib/hooks'

type F = Feature<Geometry, Record<string, unknown>>

export function RacePage() {
  const { contestId = 'us-house-1' } = useParams()
  const { currentElection, mode, config } = useSite()
  const summary = useSummary(currentElection)
  const ratings = useRatings()
  const candidates = useCandidates()
  const averages = useAverages()
  const polls = usePolls()
  const measures = useMeasures()
  const contest = summary?.contests.find((c) => c.contest_id === contestId)
  const isHouse = contestId.startsWith('us-house-')
  const district = isHouse ? Number(contestId.split('-').pop()) : null
  const title = contest?.name ?? (isHouse ? `U.S. House District ${district}` : contestId.replace('amendment-', 'Constitutional Amendment ').toUpperCase().replace('CONSTITUTIONAL AMENDMENT', 'Constitutional Amendment'))
  useDocTitle(title)

  const roster = candidates?.[contestId]
  const colors = useMemo(() => candidateColors(roster ?? []), [roster])
  const cons = consensus(ratings, contestId)
  const ratingRow = ratings?.ratings?.[contestId]
  const info = measures?.[contestId]
  const featured = config.featured_contests

  return (
    <div className="page">
      <nav className="race-tabs" aria-label="Races">
        {featured.map((id) => (
          <Link key={id} to={`/race/${id}`} className={id === contestId ? 'on' : ''}>{id.startsWith('amendment-') ? `Amendment ${id.slice(10).toUpperCase()}` : id.replace('us-house-', 'District ')}</Link>
        ))}
      </nav>
      <header className="page-head">
        <div className="kicker">{isHouse ? 'U.S. House · 2026 map' : 'Constitutional amendment'}</div>
        <h1 className="headline sm">{title}</h1>
        {isHouse && district === 1 && <p className="dek">The new District 1 is based in Salt Lake County and leans Democratic.</p>}
        {!isHouse && (info ? <p className="dek">{info.title}</p> : <p className="dek">Utah voters decide this question on the November ballot.</p>)}
      </header>

      {!isHouse && (
        <Section title="What the amendment does">
          {info ? (
            <div className="measure-detail">
              <p>{info.summary}</p>
              {info.for_means && <p><b className="for-text">A vote for</b> {info.for_means}</p>}
              {info.against_means && <p><b className="against-text">A vote against</b> {info.against_means}</p>}
              {info.source_url && <p className="note"><a href={info.source_url} target="_blank" rel="noreferrer">Official ballot language</a></p>}
            </div>
          ) : <Unavailable what="The amendment description" />}
        </Section>
      )}

      {isHouse && (
        <Section title="Candidates">
          <Gate data={candidates} what="Candidates">
            {(c) => (
              <div className="cand-cards">
                {(c[contestId] ?? []).map((x) => (
                  <div className="cand-card" key={x.candidate_id}>
                    <div className="cand-card-bar" style={{ background: colors[x.candidate_id] }} />
                    <div className="cand-card-name">{x.name}</div>
                    <div className="cand-card-meta"><PartyChip party={x.party} id={x.candidate_id} long />{x.incumbent && <span className="tag">Incumbent</span>}</div>
                    {x.bio && <p>{x.bio}</p>}
                    {x.website && <a href={x.website} target="_blank" rel="noreferrer">Campaign site</a>}
                  </div>
                ))}
              </div>
            )}
          </Gate>
        </Section>
      )}

      {isHouse && (
        <Section title="Race ratings" dek="Where independent forecasters see the race.">
          <Gate data={ratings} what="Race ratings">
            {(r) => ratingRow ? (
              <div className="ratings-block">
                <div className="ratings-chips">
                  {cons && <div className="rating-source consensus"><span>Consensus</span><RatingChip label={cons.label} scale={r.scale} /></div>}
                  {r.sources.map((s) => (
                    <div className="rating-source" key={s.id}><span>{s.url ? <a href={s.url} target="_blank" rel="noreferrer">{s.name}</a> : s.name}</span><RatingChip label={ratingRow[s.id]} scale={r.scale} /></div>
                  ))}
                </div>
                <RatingStrip ratings={ratingRow} scale={r.scale} sources={r.sources} />
              </div>
            ) : <Unavailable what="Ratings for this race" />}
          </Gate>
        </Section>
      )}

      <Section title={mode === 'pre' ? 'Election night results' : 'Results'} id="results">
        {mode === 'pre' ? (
          <div className="callout">Results will appear here on election night. Polls close at 8 p.m. MST on {config.election_date}.</div>
        ) : null}
        {mode !== 'pre' && <ContestExplorer electionId={currentElection} contestId={contestId} />}
      </Section>

      {isHouse && (
        <Section title="Polling" id="polling">
          <Gate data={polls} what="Polls">
            {(p) => <PollTracker contestId={contestId} avg={averages?.contests[contestId]} polls={p} today={new Date()} />}
          </Gate>
        </Section>
      )}

      {isHouse && district != null && <DistrictProfile district={district} />}
    </div>
  )
}

function DistrictProfile({ district }: { district: number }) {
  const districts = useGeo('cd2026')
  const counties = useGeo('counties')
  const demo = useDemographics('cd2026')
  const state = useDemographics('state')
  const baselines = useBaselines('cd2026')
  const unit = demo?.units.find((u) => u.id === String(district))
  const entries = baselines?.districts?.[String(district)]

  const fill = (f: F) => (Number(f.properties?.district) === district ? 'var(--ink)' : '#e4e4e4')
  return (
    <>
      <div className="two-col">
        <Section title="The district">
          {districts ? (
            <ChoroplethMap features={districts.features as F[]} idOf={(f) => String(f.properties?.district)} fill={fill} overlay={(counties?.features as F[] | undefined)} overlayWidth={0.4}
              fitTo={(districts.features as F[]).filter((f) => Number(f.properties?.district) === district)}
              strokeWidth={1.2} zoomable={false} aspect={1} maxHeight={480} ariaLabel={`Map of 2026 congressional district ${district}`}
              tooltip={(f) => <div className="tt-title">District {String(f.properties?.district)}</div>} />
          ) : <div className="map-placeholder">{districts === null ? 'District map not yet available.' : 'Loading map…'}</div>}
          <p className="note">2026 district lines, with county boundaries. Lines were redrawn by court order in 2025 and differ from the 2022–2024 districts.</p>
        </Section>
        <Section title="Who lives here" dek={unit ? `${fmtInt(unit.population)} residents · ${demo?.source}` : undefined}>
          <Gate data={demo} what="District demographics">
            {() => unit ? <DemoCompare unit={unit} state={state?.units[0]} unitLabel={`District ${district}`} /> : <Unavailable what="Demographics for this district" />}
          </Gate>
        </Section>
      </div>

      <Section title="How this district has voted" dek="Past statewide contests re-aggregated to the new district lines. These are estimates: past precinct results are allocated to today’s districts by population.">
        <Gate data={baselines} what="District history">
          {(b) => entries?.length ? (
            <>
              <div className="baseline-list">
                {entries.map((e) => (
                  <div className="baseline-row" key={`${e.election_id}-${e.contest_id}`}>
                    <span className="bl-name">{e.name}</span>
                    <MarginBar margin={e.margin} />
                    <span className={`bl-val ${e.margin > 0 ? 'r' : 'd'}`}>{fmtMargin(e.margin)}</span>
                  </div>
                ))}
              </div>
              <p className="note">Method: {b.method}. Labelled “re-aggregated to the new district lines.”</p>
            </>
          ) : <Unavailable what="District history" />}
        </Gate>
      </Section>
    </>
  )
}

export function MarginBar({ margin, max = 0.6 }: { margin: number; max?: number }) {
  const w = Math.min(1, Math.abs(margin) / max) * 50
  return (
    <span className="margin-bar" aria-hidden>
      <i className="mid" />
      <i className={margin > 0 ? 'r' : 'd'} style={margin > 0 ? { left: '50%', width: `${w}%` } : { right: '50%', width: `${w}%` }} />
    </span>
  )
}

