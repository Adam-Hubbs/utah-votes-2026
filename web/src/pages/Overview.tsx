import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import type { Feature, Geometry } from 'geojson'
import { useAverages, useCandidates, useGeo, useMeasures, useNational, usePolls, useRatings, useSummary } from '../data/hooks'
import { useSite } from '../data/site'
import { RaceCard } from '../components/RaceCard'
import { ChoroplethMap } from '../components/ChoroplethMap'
import { Countdown, LastUpdated } from '../components/LastUpdated'
import { Section, Stat } from '../components/Ui'
import { Sparkline } from '../components/Sparkline'
import { LatestPolls } from '../components/PollList'
import { ReportingMeter } from '../components/ReportingMeter'
import { ResultsBar } from '../components/ResultsBar'
import { RATING_FILL, NO_DATA, leaderFill } from '../lib/colors'
import { consensus } from '../lib/ratings'
import { leadingCandidate } from '../lib/results'
import { partyGroup } from '../lib/parties'
import { fmtInt, fmtPct, fmtDayYear } from '../lib/format'
import { useDocTitle } from '../lib/hooks'

type F = Feature<Geometry, Record<string, unknown>>
const HOUSE = ['us-house-1', 'us-house-2', 'us-house-3', 'us-house-4']

export function Overview() {
  useDocTitle('')
  const { config, mode, currentElection } = useSite()
  const summary = useSummary(currentElection)
  const candidates = useCandidates()
  const averages = useAverages()
  const ratings = useRatings()
  const polls = usePolls()
  const national = useNational()
  const measures = useMeasures()
  const districts = useGeo('cd2026')
  const counties = useGeo('counties')

  const showLive = mode !== 'pre'
  const contests = summary?.contests ?? []
  const byId = useMemo(() => new Map(contests.map((c) => [c.contest_id, c])), [contests])
  const houseIds = config.featured_contests.filter((c) => c.startsWith('us-house')).length ? config.featured_contests.filter((c) => c.startsWith('us-house')) : HOUSE
  const measureIds = config.featured_contests.filter((c) => c.startsWith('amendment'))
  const turnout = summary?.turnout

  const districtFill = (f: F): string => {
    const id = `us-house-${String(f.properties?.district)}`
    if (showLive) {
      const c = byId.get(id)
      if (c && c.total_votes > 0) {
        const [a, b] = [...c.candidates].sort((x, y) => y.votes - x.votes)
        return leaderFill(partyGroup(a.party, a.candidate_id), a.pct - (b?.pct ?? 0))
      }
      return NO_DATA
    }
    const cons = consensus(ratings, id)
    return cons ? RATING_FILL[cons.index] : NO_DATA
  }
  const districtTip = (f: F) => {
    const id = `us-house-${String(f.properties?.district)}`
    const c = byId.get(id)
    const cons = consensus(ratings, id)
    const lead = c && c.total_votes > 0 ? leadingCandidate(c.candidates) : null
    return (
      <div>
        <div className="tt-title">District {String(f.properties?.district)}</div>
        {showLive && lead ? <div className="tt-row"><span>{lead.name} leads</span><b>{fmtPct(lead.pct)}</b></div> : cons ? <div className="tt-row"><span>Consensus</span><b>{cons.label}</b></div> : <div className="tt-muted">No rating yet</div>}
        <div className="tt-muted">Click for the race page</div>
      </div>
    )
  }

  return (
    <div className="page overview">
      <section className="hero">
        <div className="kicker">{showLive ? (mode === 'live' ? 'Election night' : 'Final results') : 'Utah · 2026 General Election'}</div>
        <h1 className="headline">{showLive ? 'Utah election results' : 'Utah’s new congressional map is on the ballot for the first time'}</h1>
        <p className="dek">
          {showLive
            ? 'Live results for the four U.S. House districts, both constitutional amendments, and every legislative and school board contest, with estimates of how much vote is still to come.'
            : 'A court-ordered map creates a Salt Lake County–based district. Follow the polls, expert ratings and, on election night, live results with estimates of the vote still to be counted.'}
        </p>
        <div className="status-strip">
          {mode === 'pre' && (
            <>
              <Stat label="Polls close in" value={<Countdown target={config.polls_close_utc} />} sub={`Election Day · ${fmtDayYear(config.election_date)} · 8 p.m. MST`} />
              <Stat label="Registered voters" value={turnout?.registered ? fmtInt(turnout.registered) : '–'} sub="Utah votes almost entirely by mail" />
            </>
          )}
          {showLive && turnout && (
            <>
              <Stat label="Ballots counted" value={fmtInt(turnout.ballots_counted)} sub={<LastUpdated iso={summary?.updated_at} />} />
              <div className="stat stat-meter">
                <div className="stat-label">Est. expected vote counted</div>
                <div className="stat-value">{fmtPct(turnout.pct_expected, 0)}</div>
                <ReportingMeter pct={turnout.pct_expected} lo={turnout.expected_lo ? turnout.ballots_counted / turnout.expected_hi : undefined} hi={turnout.expected_lo ? turnout.ballots_counted / turnout.expected_lo : undefined} showText={false} />
                <div className="stat-sub">Expected final: {fmtInt(turnout.expected_lo)}–{fmtInt(turnout.expected_hi)} ballots</div>
              </div>
            </>
          )}
        </div>
      </section>

      <Section title="U.S. House" dek="All four seats are up, on the new 2026 district lines." aside={<Link to="/results" className="more">All results →</Link>}>
        <div className="race-grid">
          {houseIds.map((id) => (
            <RaceCard key={id} contestId={id} title={`District ${id.split('-').pop()}`}
              subtitle={id === 'us-house-1' ? 'Salt Lake County–based' : undefined}
              roster={candidates?.[id]} avg={averages?.contests[id]} live={byId.get(id)} showLive={showLive} ratings={ratings} />
          ))}
        </div>
      </Section>

      <div className="two-col">
        <Section title="The new districts" dek={showLive ? 'Shaded by the current leader. Lighter means a closer margin.' : 'Shaded by the consensus of race ratings.'}>
          {districts && counties ? (
            <>
              <ChoroplethMap features={districts.features as F[]} idOf={(f) => String(f.properties?.district)} fill={districtFill} tooltip={districtTip}
                overlay={counties.features as F[]} overlayWidth={0.5} strokeWidth={1.5} strokeColor="#fff" zoomable={false} aspect={1.1} maxHeight={520}
                onSelect={(f) => { if (f) window.location.hash = `#/race/us-house-${String(f.properties?.district)}` }}
                ariaLabel="Map of Utah's four 2026 congressional districts" />
              {!showLive && (
                <div className="legend rating-legend">
                  <div className="legend-title">Consensus rating</div>
                  <div className="rating-legend-bar">{RATING_FILL.map((c, i) => <i key={c} style={{ background: c }} title={ratings?.scale[i]} />)}</div>
                  <div className="legend-ends"><span>Solid D</span><span>Toss-up</span><span>Solid R</span></div>
                </div>
              )}
            </>
          ) : <div className="map-placeholder">{districts === null ? 'District map not yet available.' : 'Loading map…'}</div>}
        </Section>
        <div>
          <Section title="Constitutional amendments">
            <div className="measure-cards">
              {measureIds.map((id) => {
                const c = byId.get(id)
                const info = measures?.[id]
                const items = c?.candidates ?? []
                const live = showLive && c && c.total_votes > 0
                return (
                  <article className="measure-card" key={id}>
                    <h3><Link to={`/race/${id}`}>{c?.name ?? id.replace('amendment-', 'Amendment ').toUpperCase().replace('AMENDMENT', 'Amendment')}</Link></h3>
                    {info && <p>{info.title}</p>}
                    {live ? (
                      <>
                        <ResultsBar items={items.map((i) => ({ candidate_id: i.candidate_id, name: i.name, party: null, pct: i.pct }))} />
                        <div className="measure-vals">{items.map((i) => <span key={i.candidate_id}>{i.name} <b>{fmtPct(i.pct)}</b></span>)}</div>
                        {c && <div className="rc-foot-text">Est. {fmtPct(c.reporting.pct_expected, 0)} of expected vote counted</div>}
                      </>
                    ) : <div className="rc-foot-text">No public polling. {info ? '' : 'Description pending.'}</div>}
                  </article>
                )
              })}
            </div>
          </Section>
          <Section title="National backdrop">
            {national ? (
              <div className="national-strip">
                <NationalStat label="Generic ballot" series={national.generic_ballot.series.map((p) => Number(p.DEM) - Number(p.REP))} value={Number(national.generic_ballot.latest.DEM) - Number(national.generic_ballot.latest.REP)} fmt={(v) => (Math.abs(v) < 0.05 ? 'Even' : `${v > 0 ? 'D' : 'R'}+${Math.abs(v).toFixed(1)}`)} color="var(--dem)" />
                <NationalStat label="Trump approval (net)" series={national.approval.series.map((p) => Number(p.approve) - Number(p.disapprove))} value={Number(national.approval.latest.approve) - Number(national.approval.latest.disapprove)} fmt={(v) => `${v > 0 ? '+' : '−'}${Math.abs(v).toFixed(1)}`} color="var(--ink-2)" />
              </div>
            ) : <div className="unavailable">National polling not yet available.</div>}
            <p className="note"><Link to="/polls">National trackers →</Link></p>
          </Section>
        </div>
      </div>

      <Section title="Latest polls" aside={<Link to="/polls" className="more">Poll tracker →</Link>}>
        {polls ? <LatestPolls polls={polls.filter((p) => p.stage === 'general')} limit={6} names={(id) => byId.get(id)?.name ?? id.replace('us-house-', 'U.S. House District ')} /> : <div className="unavailable">Polls not yet available.</div>}
      </Section>
    </div>
  )
}

function NationalStat({ label, value, series, fmt, color }: { label: string; value: number; series: number[]; fmt: (v: number) => string; color: string }) {
  return (
    <div className="national-stat">
      <div className="stat-label">{label}</div>
      <div className="stat-value">{fmt(value)}</div>
      <Sparkline values={series.filter((_, i) => i % 2 === 0)} width={140} height={34} color={color} />
    </div>
  )
}
