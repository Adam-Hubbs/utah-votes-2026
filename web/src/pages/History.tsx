import { useMemo, useState } from 'react'
import type { Feature, Geometry } from 'geojson'
import { useContestResults, useCountyTrends, useGeo, useResultsIndex } from '../data/hooks'
import { useSite } from '../data/site'
import { ContestExplorer } from '../components/ContestExplorer'
import { ContestSelect, ElectionSelect } from '../components/ElectionPicker'
import { Gate, Section, Segmented, Select } from '../components/Ui'
import { ChoroplethMap } from '../components/ChoroplethMap'
import { MiniTrend } from '../components/MiniTrend'
import { SortableTable, type Column } from '../components/SortableTable'
import { divergingFill, NO_DATA, rampFor } from '../lib/colors'
import { ContinuousLegend } from '../components/MapLegend'
import { rMargin } from '../lib/swing'
import { fmtMargin } from '../lib/format'
import { useDocTitle } from '../lib/hooks'
import type { IndexElection } from '../types/data'
import { TooltipHeader, TooltipRow } from '../components/Tooltip'

type F = Feature<Geometry, Record<string, unknown>>

export function HistoryPage() {
  useDocTitle('History')
  const index = useResultsIndex()
  const { currentElection } = useSite()
  const past = useMemo(() => (index?.elections ?? []).filter((e) => e.election_id !== currentElection), [index, currentElection])
  const [electionId, setElectionId] = useState('2024-general')
  const election = past.find((e) => e.election_id === electionId) ?? past[0]
  const [contestPick, setContestPick] = useState<string>('president')
  const contestId = election?.contests.some((c) => c.contest_id === contestPick) ? contestPick : (election?.contests[0]?.contest_id ?? '')

  return (
    <div className="page">
      <header className="page-head">
        <div className="kicker">History</div>
        <h1 className="headline sm">Past elections</h1>
        <p className="dek">County and precinct results from earlier elections, how counties have moved over time, and swing between contests.</p>
      </header>
      <div className="callout">
        <b>Lines have changed.</b> Utah’s congressional districts were redrawn for 2026, so a 2024 “District 2” is not the 2026 District 2. Precincts are redrawn every cycle too, so each map uses the precinct lines of its own election and precinct maps from different years should not be overlaid. Race pages show past results re-aggregated to the new district lines.
      </div>
      <Gate data={index} what="The election list">
        {() => (
          <>
            <div className="selectors">
              <ElectionSelect elections={past} value={election?.election_id ?? ''} onChange={(id) => { setElectionId(id) }} />
              <ContestSelect election={election} value={contestId} onChange={setContestPick} />
            </div>
            {election && contestId && <ContestExplorer key={`${election.election_id}/${contestId}`} electionId={election.election_id} contestId={contestId} sections={{ counties: true, timeline: false }} />}
            <Section title="How counties have moved" dek="Margin by county in presidential, gubernatorial and Senate contests, 2016–2024. Right of the dashed line is Republican.">
              <Trends />
            </Section>
            <Section title="Swing between two contests" dek="Change in the county Republican margin from the first contest to the second. Red counties moved toward Republicans; blue counties moved toward Democrats.">
              <Swing past={past} />
            </Section>
          </>
        )}
      </Gate>
    </div>
  )
}

function Trends() {
  const trends = useCountyTrends()
  return (
    <Gate data={trends} what="County trends">
      {(t) => {
        const fipsList = Object.keys(t.counties)
        const names: Record<string, string> = {}
        return (
          <TrendGrid fips={fipsList} data={t.counties} names={names} />
        )
      }}
    </Gate>
  )
}

function TrendGrid({ fips, data, names }: { fips: string[]; data: Record<string, import('../types/data').CountyTrendEntry[]>; names: Record<string, string> }) {
  const counties = useGeo<{ fips: string; name: string }>('counties')
  const [metric, setMetric] = useState<'margin' | 'turnout'>('margin')
  const [contest, setContest] = useState<'president' | 'all'>('president')
  counties?.features.forEach((f) => { names[f.properties.fips] = f.properties.name })
  const rows = fips.map((f) => {
    const all = data[f] ?? []
    const entries = all.filter((e) => (contest === 'all' ? true : e.contest_id === 'president'))
    return { fips: f, entries }
  }).filter((r) => r.entries.length > 1)
  const vals = rows.flatMap((r) => r.entries.map((e) => (metric === 'margin' ? e.margin : (e.turnout ?? 0))))
  const lo = Math.min(...vals), hi = Math.max(...vals)
  const hasTurnout = Object.values(data).some((entries) => entries.some((e) => e.turnout != null))
  return (
    <>
      <div className="chart-toolbar">
        <Segmented label="Metric" value={metric} onChange={setMetric} options={hasTurnout ? [{ value: 'margin', label: 'R–D margin' }, { value: 'turnout', label: 'Turnout' }] : [{ value: 'margin', label: 'R–D margin' }]} />
        <Segmented label="Contests" value={contest} onChange={setContest} options={[{ value: 'president', label: 'President' }, { value: 'all', label: 'All contests' }]} />
      </div>
      <div className="trend-grid">
        {rows.map((r) => {
          const last = r.entries[r.entries.length - 1]
          const v = metric === 'margin' ? last.margin : (last.turnout ?? 0)
          return (
            <figure className="trend-cell" key={r.fips}>
              <figcaption><b>{names[r.fips] ?? r.fips}</b><span className={metric === 'margin' ? (v > 0 ? 'r' : 'd') : ''}>{metric === 'margin' ? fmtMargin(v, 0) : `${Math.round(v * 100)}%`}</span></figcaption>
              <MiniTrend values={r.entries.map((e) => (metric === 'margin' ? e.margin : (e.turnout ?? 0)))} years={r.entries.map((e) => e.year + (contest === 'all' ? (e.contest_id === 'president' ? 0 : 0.2) : 0))}
                yMin={lo} yMax={hi} zero={metric === 'margin'} color={metric === 'margin' ? (v > 0 ? 'var(--rep)' : 'var(--dem)') : 'var(--ink-2)'} />
            </figure>
          )
        })}
      </div>
    </>
  )
}

function ElectionContestPicker({ elections, value, onChange, label }: { elections: IndexElection[]; value: { e: string; c: string }; onChange: (v: { e: string; c: string }) => void; label: string }) {
  const el = elections.find((x) => x.election_id === value.e)
  return (
    <div className="pair-picker">
      <Select label={`${label}: election`} value={value.e} onChange={(e) => onChange({ e, c: elections.find((x) => x.election_id === e)?.contests.find((c) => c.office === elections.find((x) => x.election_id === value.e)?.contests.find((cc) => cc.contest_id === value.c)?.office)?.contest_id ?? elections.find((x) => x.election_id === e)?.contests[0]?.contest_id ?? '' })}>
        {elections.map((e) => <option key={e.election_id} value={e.election_id}>{e.name}</option>)}
      </Select>
      <ContestSelect election={el} value={value.c} onChange={(c) => onChange({ e: value.e, c })} />
    </div>
  )
}

function Swing({ past }: { past: IndexElection[] }) {
  const [a, setA] = useState({ e: '2022-general', c: 'us-senate' })
  const [b, setB] = useState({ e: '2024-general', c: 'us-senate' })
  const ra = useContestResults(a.e, a.c)
  const rb = useContestResults(b.e, b.c)
  const counties = useGeo<{ fips: string; name: string }>('counties')
  const [selected, setSelected] = useState<string | null>(null)
  const swings = useMemo(() => {
    if (!ra || !rb || !counties) return null
    return counties.features.map((f) => {
      const ma = rMargin(ra, f.properties.fips), mb = rMargin(rb, f.properties.fips)
      return { fips: f.properties.fips, name: f.properties.name, ma, mb, swing: ma != null && mb != null ? mb - ma : null }
    })
  }, [ra, rb, counties])
  const map = useMemo(() => new Map((swings ?? []).map((s) => [s.fips, s])), [swings])
  const columns: Column<NonNullable<typeof swings>[number]>[] = [
    { key: 'name', header: 'County', sort: (r) => r.name, render: (r) => <b>{r.name}</b> },
    { key: 'ma', header: 'First', align: 'right', marginSort: { value: (r) => r.ma }, render: (r) => <span className="num">{r.ma == null ? '–' : fmtMargin(r.ma)}</span> },
    { key: 'mb', header: 'Second', align: 'right', marginSort: { value: (r) => r.mb }, render: (r) => <span className="num">{r.mb == null ? '–' : fmtMargin(r.mb)}</span> },
    { key: 'swing', header: 'Swing', align: 'right', marginSort: { value: (r) => r.swing }, render: (r) => <span className={`num ${r.swing != null && r.swing > 0 ? 'r' : 'd'}`}>{r.swing == null ? '–' : `${r.swing > 0 ? 'R' : 'D'} ${Math.abs(r.swing * 100).toFixed(1)}`}</span> },
  ]
  return (
    <div>
      <div className="swing-pickers">
        <ElectionContestPicker elections={past} value={a} onChange={setA} label="From" />
        <ElectionContestPicker elections={past} value={b} onChange={setB} label="To" />
      </div>
      {swings && counties ? (
        <div className="two-col eq swing-body">
          <div>
            <ChoroplethMap features={counties.features as F[]} idOf={(f) => String(f.properties?.fips)} selectedId={selected} onSelect={(f) => setSelected(f ? String(f.properties?.fips) : null)}
              fill={(f) => { const s = map.get(String(f.properties?.fips)); return s?.swing == null ? NO_DATA : divergingFill(s.swing, 0.2) }}
              tooltip={(f) => { const s = map.get(String(f.properties?.fips)); return <div><TooltipHeader title={`${s?.name} County`} /><TooltipRow label="First" value={s?.ma == null ? '–' : fmtMargin(s.ma)} /><TooltipRow label="Second" value={s?.mb == null ? '–' : fmtMargin(s.mb)} /></div> }}
              aspect={1.1} maxHeight={520} ariaLabel="Map of change in county Republican margin" />
            <ContinuousLegend title="Swing in Republican margin" lo="More Democratic" hi="More Republican" colors={[...rampFor('DEM').slice().reverse(), '#f2f2f2', ...rampFor('REP')]} />
          </div>
          <SortableTable rows={swings} columns={columns} rowKey={(r) => r.fips} initialSort={{ key: 'swing', dir: 'desc' }} activeKey={selected} onRowClick={(r) => setSelected(r.fips)} maxHeight={520} />
        </div>
      ) : <div className="map-placeholder">Pick two contests with county results.</div>}
      <p className="note">Margins are Republican minus Democratic share of all votes cast. Where no Democrat ran, the strongest opponent is used.</p>
    </div>
  )
}
