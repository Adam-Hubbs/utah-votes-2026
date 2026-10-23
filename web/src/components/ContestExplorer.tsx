import { useCallback, useMemo, useState } from 'react'
import type { Feature, Geometry } from 'geojson'
import { useContestResults, useGeo, useModel, usePlaces, useSummary, useTimeline } from '../data/hooks'
import { useSite } from '../data/site'
import type { ContestResults, CountyResult, ElectionModel, SummaryContest } from '../types/data'
import { candidateColors, partyGroup } from '../lib/parties'
import { NO_DATA, leaderFill } from '../lib/colors'
import { estRemaining, leaderOf, marginText, signedMargin } from '../lib/results'
import { fmtCompact, fmtInt, fmtMT, fmtMTFull, fmtPct } from '../lib/format'
import { CandidateRow } from './CandidateRow'
import { ChoroplethMap } from './ChoroplethMap'
import { MarginLegend } from './MapLegend'
import { PartyChip } from './PartyChip'
import { PollChart, type TSeries } from './PollChart'
import { ReportingMeter } from './ReportingMeter'
import { SortableTable, type Column } from './SortableTable'
import { LastUpdated } from './LastUpdated'
import { Gate, Section, Segmented, Stat, Unavailable } from './Ui'
import { TooltipFoot, TooltipHeader, TooltipNote, TooltipRow } from './Tooltip'

type F = Feature<Geometry, Record<string, unknown>>

interface Props {
  electionId: string
  contestId: string
  sections?: { timeline?: boolean; turnout?: boolean; counties?: boolean }
  headingLevel?: 'h2' | 'h3'
}

export function ContestExplorer({ electionId, contestId, sections = { timeline: true, turnout: true, counties: true } }: Props) {
  const summary = useSummary(electionId)
  const results = useContestResults(electionId, contestId)
  return (
    <Gate data={summary} what="Election summary">
      {(sum) => {
        const contest = sum.contests.find((c) => c.contest_id === contestId)
        if (!contest) return <Unavailable what="This contest" />
        return (
          <ContestBody electionId={electionId} summary={sum} contest={contest} results={results} sections={sections} />
        )
      }}
    </Gate>
  )
}

interface BodyProps {
  electionId: string
  summary: NonNullable<ReturnType<typeof useSummary>>
  contest: SummaryContest
  results: ReturnType<typeof useContestResults>
  sections: NonNullable<Props['sections']>
}

function ContestBody({ electionId, summary, contest, results, sections }: BodyProps) {
  const { mode, currentElection } = useSite()
  const isLive = summary.status === 'live' || (electionId === currentElection && mode === 'live')
  const colors = useMemo(() => candidateColors(contest.candidates), [contest.candidates])
  const maxPct = Math.max(...contest.candidates.map((c) => c.pct), 0.0001)
  const hasVotes = contest.total_votes > 0
  const rep = contest.reporting

  return (
    <div className="contest-body">
      <div className="contest-grid">
        <div className="contest-main">
          <div className="contest-head">
            <div>
              <h2 className="contest-title">{contest.name}</h2>
              <LastUpdated iso={summary.updated_at} status={summary.status} showRefresh={isLive} />
            </div>
            <div className="contest-status">
              {summary.status === 'final' ? <span className="call-badge">Official results</span> : hasVotes ? <span className="status-pill live"><i />Counting</span> : !hasVotes && summary.status === 'pre' ? <span className="status-pill">No results yet</span> : null}
            </div>
          </div>
          <div className="cand-list">
            {contest.candidates.map((c) => (
              <CandidateRow key={c.candidate_id} name={c.name} party={c.party} candidateId={c.candidate_id} incumbent={c.incumbent}
                votes={hasVotes ? c.votes : undefined} pct={hasVotes ? c.pct : undefined} maxPct={maxPct} color={colors[c.candidate_id]} winner={c.winner} />
            ))}
          </div>
          {hasVotes && (
            <div className="contest-foot">
              <span>{fmtInt(contest.total_votes)} votes counted</span>
              <span className="dot-sep">·</span>
              <span>{rep.counties_reporting} of {rep.counties_total} counties reporting</span>
            </div>
          )}
          {(isLive || hasVotes) && summary.status !== 'final' && (
            <div className="reporting-block">
              <div className="reporting-title">Est. {fmtPct(rep.pct_expected, 0)} of expected vote counted</div>
              <ReportingMeter pct={rep.pct_expected} lo={rep.pct_expected_lo} hi={rep.pct_expected_hi} showText={false} />
              <p className="note">Plausible range {fmtPct(rep.pct_expected_lo, 0)}–{fmtPct(rep.pct_expected_hi, 0)}, from a statistical model of how many ballots remain. Utah counts for about two weeks, so late ballots can shift margins.</p>
            </div>
          )}
          {summary.status === 'pre' && !hasVotes && <p className="note">Polls close at 8 p.m. MST on election night. Results appear here as counties report.</p>}
        </div>
        <div className="contest-map">
          <ContestMapPanel electionId={electionId} summary={summary} contest={contest} results={results} live={isLive} />
        </div>
      </div>

      {sections.counties !== false && (
        <Section title="Results by county" id="counties">
          <Gate data={results} what="County results">
            {(r) => <CountyTable results={r} contest={contest} live={isLive} final={summary.status === 'final'} />}
          </Gate>
        </Section>
      )}

      {sections.timeline !== false && isLive && (
        <Section title="Vote count over time" dek="How the statewide count has evolved since polls closed. Times are Mountain Time.">
          <TimelinePanel electionId={electionId} contest={contest} colors={colors} />
        </Section>
      )}
      {sections.turnout !== false && isLive && (
        <Section title="Statewide turnout" dek="Ballots counted so far against the model's estimate of the final total.">
          <TurnoutPanel electionId={electionId} />
        </Section>
      )}
    </div>
  )
}

function ContestMapPanel({ electionId, summary, contest, results, live }: { electionId: string; summary: BodyProps['summary']; contest: SummaryContest; results: BodyProps['results']; live: boolean }) {
  const precinctGeoName = summary.precinct_geo
  const counties = useGeo('counties')
  const hasPrecinctData = !!results && results.precincts.length > 0
  const [view, setView] = useState<'county' | 'precinct'>('county')
  const precincts = useGeo(view === 'precinct' && precinctGeoName ? precinctGeoName : null)
  const places = usePlaces()
  const [selected, setSelected] = useState<string | null>(null)

  const cands = results?.candidates ?? contest.candidates
  const colors = useMemo(() => candidateColors(contest.candidates), [contest.candidates])
  const byFips = useMemo(() => new Map((results?.counties ?? []).map((c) => [c.fips, c])), [results])
  const byPrecinct = useMemo(() => new Map((results?.precincts ?? []).map((p) => [p.precinct_id, p])), [results])
  const precinctOk = !!precinctGeoName && hasPrecinctData && precincts !== null
  const effective: 'county' | 'precinct' = view === 'precinct' && precinctOk ? 'precinct' : 'county'
  const hasData = contest.total_votes > 0

  const countyFeatures = useMemo(() => (counties ? (counties.features as F[]) : []), [counties])
  const precinctFeatures = useMemo(() => {
    if (!precincts) return []
    return (precincts.features as F[]).filter((f) => byPrecinct.has(String(f.properties?.precinct_id)))
  }, [precincts, byPrecinct])
  const features = effective === 'precinct' ? precinctFeatures : countyFeatures
  const fitTo = useMemo(() => {
    const inRace = countyFeatures.filter((f) => byFips.has(String(f.properties?.fips)))
    return inRace.length ? inRace : countyFeatures
  }, [countyFeatures, byFips])

  const idOf = useCallback((f: F) => String(f.properties?.[effective === 'precinct' ? 'precinct_id' : 'fips']), [effective])

  const unitVotes = useCallback((f: F): { votes: Record<string, number>; total: number; pct: number | null; name: string } | null => {
    if (effective === 'county') {
      const c = byFips.get(String(f.properties?.fips))
      return c ? { votes: c.votes, total: c.total, pct: c.pct_expected, name: `${c.name} County` } : null
    }
    const p = byPrecinct.get(String(f.properties?.precinct_id))
    const c = byFips.get(String(f.properties?.county_fips))
    return p ? { votes: p.votes, total: p.total, pct: c?.pct_expected ?? null, name: `Precinct ${String(f.properties?.name)} · ${c?.name ?? ''} County` } : null
  }, [effective, byFips, byPrecinct])

  const fill = useCallback((f: F) => {
    const u = unitVotes(f)
    if (!u || u.total <= 0) return NO_DATA
    const l = leaderOf(u.votes, u.total, cands)
    return l.id ? leaderFill(l.group, l.margin) : NO_DATA
  }, [unitVotes, cands])

  const hatch = useCallback((f: F) => {
    if (!live) return false
    const u = unitVotes(f)
    return !!u && u.pct != null && u.pct < 0.5 && u.total > 0
  }, [unitVotes, live])

  const tooltip = useCallback((f: F) => {
    const u = unitVotes(f)
    if (!u) return <div><TooltipHeader title={String(f.properties?.name ?? '')} /><TooltipNote>Not in this contest</TooltipNote></div>
    const l = leaderOf(u.votes, u.total, cands)
    const rows = [...cands].sort((a, b) => (u.votes[b.candidate_id] ?? 0) - (u.votes[a.candidate_id] ?? 0)).slice(0, 4)
    return (
      <div>
        <TooltipHeader title={u.name} subtitle={u.pct != null && live ? `Est. ${fmtPct(u.pct, 0)} counted` : undefined} />
        {u.total > 0 ? (
          <>
            {rows.map((c) => (
              <TooltipRow key={c.candidate_id} color={colors[c.candidate_id] ?? '#999'} label={c.name}
                value={fmtPct((u.votes[c.candidate_id] ?? 0) / u.total)} detail={fmtInt(u.votes[c.candidate_id] ?? 0)} />
            ))}
            {l.id && <TooltipFoot><span>Margin</span><b>{marginText(l)}</b></TooltipFoot>}
          </>
        ) : <TooltipNote>No votes counted yet</TooltipNote>}
      </div>
    )
  }, [unitVotes, cands, colors, live])

  const onSelect = useCallback((f: F | null) => {
    if (!f) { setSelected(null); return }
    const id = idOf(f)
    setSelected((s) => (s === id ? null : id))
  }, [idOf])

  const groupsPresent = useMemo(() => {
    const g = new Set(contest.candidates.map((c) => partyGroup(c.party, c.candidate_id)))
    return (['DEM', 'REP', 'THIRD', 'FOR', 'AGAINST'] as const).filter((x) => g.has(x))
  }, [contest.candidates])

  return (
    <div className="map-panel">
      <div className="map-toolbar">
        <Segmented label="Map detail" value={effective} onChange={(v) => { setView(v); setSelected(null) }}
          options={[{ value: 'county', label: 'County' }, { value: 'precinct', label: 'Precinct', disabled: !precinctGeoName || !hasPrecinctData }]} />
        {selected && <button type="button" className="link-btn" onClick={() => setSelected(null)}>Reset zoom</button>}
      </div>
      {counties === undefined || (effective === 'precinct' && precincts === undefined) ? (
        <div className="map-placeholder">Loading map…</div>
      ) : counties === null ? (
        <Unavailable what="Map geometry" />
      ) : (
        <ChoroplethMap features={features} idOf={idOf} fill={fill} hatch={hatch} tooltip={tooltip} onSelect={onSelect} selectedId={selected}
          focusId={effective === 'county' ? selected : undefined} fitTo={fitTo} overlay={effective === 'precinct' ? countyFeatures.filter((f) => byFips.has(String(f.properties?.fips))) : undefined}
          labels={places ?? undefined} strokeWidth={effective === 'precinct' ? 0.25 : 0.8}
          ariaLabel={`Map of ${contest.name} results by ${effective}${hasData ? '' : '. No results yet.'}`} />
      )}
      {view === 'precinct' && !precinctOk && precincts !== undefined && <p className="note">Precinct results are not available for this election{electionId ? '' : ''}.</p>}
      <MarginLegend groups={groupsPresent.length ? [...groupsPresent] : ['DEM', 'REP']} hatchNote={live} />
      {effective === 'precinct' && summary.precinct_geo && <p className="note small">Precinct lines are those used for the {summary.precinct_geo.replace('precincts_', '')} election and are not comparable to other years. Grey precincts cast no votes in this contest.</p>}
    </div>
  )
}

export function CountyTable({ results, contest, live, final = false }: { results: ContestResults; contest: SummaryContest; live: boolean; final?: boolean }) {
  const cands = results.candidates
  const colors = useMemo(() => candidateColors(contest.candidates), [contest.candidates])
  const rows = results.counties
  const measure = contest.candidates.some((c) => partyGroup(c.party, c.candidate_id) === 'FOR')
  const columns: Column<CountyResult>[] = [
    { key: 'name', header: 'County', sort: (r) => r.name, render: (r) => <b>{r.name}</b> },
    {
      key: 'leader', header: 'Leader', sort: (r) => leaderOf(r.votes, r.total, cands).name,
      render: (r) => {
        const l = leaderOf(r.votes, r.total, cands)
        if (!l.id) return <span className="muted">–</span>
        const c = cands.find((x) => x.candidate_id === l.id)
        return <span className="leader-cell"><i style={{ background: colors[l.id] }} />{l.name}{' '}<PartyChip party={c?.party ?? null} id={l.id} /></span>
      },
    },
    {
      key: 'margin', header: 'Margin', align: 'right', marginSort: { value: (r) => signedMargin(leaderOf(r.votes, r.total, cands)), kind: measure ? 'measure' : 'party' },
      render: (r) => {
        const l = leaderOf(r.votes, r.total, cands)
        if (!l.id) return '–'
        return <span className="num">{marginText(l)}</span>
      },
    },
    { key: 'total', header: 'Votes', align: 'right', sort: (r) => r.total, render: (r) => <span className="num">{fmtInt(r.total)}</span> },
  ]
  if (final) {
    // Certified results: every county is fully counted, so the counting columns would only show 100% and 0.
  } else if (live || contest.total_votes > 0) {
    columns.push(
      { key: 'pct', header: 'Est. % counted', title: 'Estimated share of expected vote counted', sort: (r) => r.pct_expected, render: (r) => <ReportingMeter pct={r.pct_expected} lo={r.pct_expected_lo} hi={r.pct_expected_hi} size="sm" /> },
      { key: 'rem', header: 'Est. votes left', align: 'right', sort: (r) => estRemaining(r), render: (r) => <span className="num">{r.pct_expected >= 0.999 ? '0' : `~${fmtCompact(estRemaining(r))}`}</span> },
    )
  } else {
    columns.push({ key: 'exp', header: 'Expected ballots', align: 'right', sort: (r) => r.expected_ballots, render: (r) => <span className="num">{fmtInt(r.expected_ballots)}</span> })
  }
  return <SortableTable rows={rows} columns={columns} rowKey={(r) => r.fips} initialSort={{ key: 'total', dir: 'desc' }} caption={`${contest.name} results by county`} />
}

function TimelinePanel({ electionId, contest, colors }: { electionId: string; contest: SummaryContest; colors: Record<string, string> }) {
  const timeline = useTimeline(electionId)
  const [metric, setMetric] = useState<'share' | 'votes'>('share')
  return (
    <Gate data={timeline} what="The vote timeline">
      {(t) => {
        const pts = t.contests[contest.contest_id]
        if (!pts?.length) return <Unavailable what="The vote timeline for this contest" />
        const series: TSeries[] = contest.candidates.map((c) => ({
          id: c.candidate_id, label: c.name, endLabel: c.name.split(' ').pop(), color: colors[c.candidate_id],
          line: pts.map((p) => ({ x: new Date(p.t), y: metric === 'share' ? (p.total ? ((p.votes[c.candidate_id] ?? 0) / p.total) * 100 : 0) : (p.votes[c.candidate_id] ?? 0) })),
        }))
        return (
          <>
            <div className="chart-toolbar"><Segmented label="Metric" value={metric} onChange={setMetric} options={[{ value: 'share', label: 'Vote share' }, { value: 'votes', label: 'Votes' }]} /></div>
            <PollChart series={series} height={300} yFormat={metric === 'share' ? (v) => `${v}%` : fmtCompact} valueFormat={metric === 'share' ? (v) => `${v.toFixed(1)}%` : fmtInt}
              yDomain={metric === 'share' ? [0, 100] : undefined} xTickFormat={fmtMT} tipDateFormat={fmtMTFull} minSpanDays={0.05}
              ariaLabel={`${contest.name} ${metric} over time`} />
          </>
        )
      }}
    </Gate>
  )
}

function TurnoutPanel({ electionId }: { electionId: string }) {
  const model = useModel(electionId)
  const summary = useSummary(electionId)
  return (
    <Gate data={model} what="The turnout model">
      {(m: ElectionModel) => {
        const s = m.statewide
        const t = summary ?? null
        const lo = s.expected_lo / s.expected_median, hi = s.expected_hi / s.expected_median
        const pct = s.counted / s.expected_median
        return (
          <div className="turnout-grid">
            <div>
              <div className="stat-row">
                <Stat label="Ballots counted" value={fmtInt(s.counted)} />
                <Stat label="Expected final" value={fmtInt(s.expected_median)} sub={`${fmtInt(s.expected_lo)} – ${fmtInt(s.expected_hi)}`} />
                {t && <Stat label="Registered voters" value={fmtInt(t.turnout.registered)} sub={`${fmtPct(s.expected_median / t.turnout.registered, 0)} expected turnout`} />}
              </div>
              <ReportingMeter pct={pct} lo={pct / hi} hi={pct / lo} label="Statewide ballots counted vs expected" />
              <p className="note">{m.method}</p>
            </div>
            <PollChart height={220} ariaLabel="Ballots counted over time"
              series={[
                { id: 'expected', label: 'Expected final (median)', endLabel: 'Expected', color: '#999', dashed: true, line: m.history.map((h) => ({ x: new Date(h.t), y: h.expected_median })) },
                { id: 'counted', label: 'Counted', color: '#121212', line: m.history.map((h) => ({ x: new Date(h.t), y: h.counted })) },
              ]}
              yFormat={fmtCompact} valueFormat={fmtInt} xTickFormat={fmtMT} tipDateFormat={fmtMTFull} minSpanDays={0.05} />
          </div>
        )
      }}
    </Gate>
  )
}

